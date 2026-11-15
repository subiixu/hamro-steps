import { v } from "convex/values";
import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";
import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { requireUser } from "./lib/access";
import { revokeAppleToken } from "./lib/apple";
import { deleteBlob, deleteUserData } from "./lib/cleanup";
import {
  APPLE_REVOKE_RETRY_DELAYS_MS,
  MAX_PHOTO_BYTES,
  ORPHAN_BLOB_AGE_MS,
  ORPHAN_SWEEP_BATCH,
} from "./lib/constants";
import { fail } from "./lib/errors";
import { checkBirthday, cleanCity, photoUrl } from "./lib/profile";
import { cleanName } from "./lib/validate";

/**
 * How long a queued Apple revoke may sit past its `nextAttemptAt` before the
 * recovery cron reschedules it. Longer than an action's 10-minute limit, so
 * an attempt that's merely running is never doubled.
 */
export const APPLE_REVOKE_RECOVERY_GRACE_MS = 15 * 60_000;

/** Overdue rows the recovery cron reschedules per run; the rest wait an hour. */
const APPLE_REVOKE_RECOVERY_BATCH = 100;

/** Wait before retry `attempt` (0-based): the backoff list, then its last entry (daily) forever. */
export function appleRevokeDelay(attempt: number): number {
  const delays = APPLE_REVOKE_RETRY_DELAYS_MS;
  return delays[Math.min(attempt, delays.length - 1)]!;
}

/** The signed-in user's profile. `needsName` → show the one name field. */
export const me = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    return {
      userId: user._id,
      name: user.name ?? null,
      needsName: !user.name,
      avatarColor: user.avatarColor,
      timezone: user.timezone ?? null,
      lastSyncedAt: user.lastSyncedAt ?? null,
      photoUrl: await photoUrl(ctx, user),
      city: user.city ?? null,
      birthday: user.birthday ?? null,
    };
  },
});

/**
 * Each field may be omitted. `city`: trimmed, max 40, "" clears it.
 * `birthday`: "YYYY-MM-DD", real, not future, year ≥ 1900; null clears it.
 */
export const updateProfile = mutation({
  args: {
    name: v.optional(v.string()),
    timezone: v.optional(v.string()),
    city: v.optional(v.string()),
    birthday: v.optional(v.union(v.string(), v.null())),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const patch: { name?: string; timezone?: string; city?: string; birthday?: string } = {};
    if (args.name !== undefined) patch.name = cleanName(args.name);
    if (args.timezone !== undefined) patch.timezone = args.timezone.slice(0, 64);
    // An `undefined` value in a patch removes the field.
    if (args.city !== undefined) patch.city = cleanCity(args.city);
    if (args.birthday !== undefined) {
      patch.birthday = args.birthday === null ? undefined : checkBirthday(args.birthday, Date.now());
    }
    await ctx.db.patch(user._id, patch);
    return null;
  },
});

/** Step 1 of a photo change: a one-off upload URL for the image blob. */
export const generateAvatarUploadUrl = mutation({
  args: {},
  handler: async (ctx): Promise<string> => {
    await requireUser(ctx);
    return await ctx.storage.generateUploadUrl();
  },
});

/**
 * Step 2: make the uploaded blob the user's photo, deleting the old one.
 * A blob over 5 MB or not `image/*` is rejected (`invalid_photo`); the
 * hourly orphan sweep deletes it.
 */
export const setAvatar = mutation({
  args: { storageId: v.id("_storage"), userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    // The app names the account the photo was picked for. If a different
    // account's token sent this (sign-out/sign-in race), refuse before
    // touching anything.
    if (user._id !== args.userId) fail("not_authorized");
    if (user.photoId === args.storageId) return null;
    const meta = await ctx.db.system.get("_storage", args.storageId);
    if (!meta) fail("invalid_photo");
    // Never adopt a blob another profile owns: removing or replacing it
    // later would delete their photo. Nothing is deleted here.
    const owner = await ctx.db
      .query("users")
      .withIndex("by_photoId", (q) => q.eq("photoId", args.storageId))
      .first();
    if (owner) fail("invalid_photo");
    // Throwing rolls back any delete here too, so a rejected blob is left
    // for `sweepOrphanBlobs` to remove once it's an hour old.
    if (meta.size > MAX_PHOTO_BYTES || !(meta.contentType ?? "").startsWith("image/")) {
      fail("invalid_photo");
    }
    if (user.photoId) await deleteBlob(ctx, user.photoId);
    await ctx.db.patch(user._id, { photoId: args.storageId });
    return null;
  },
});

/**
 * Hourly cron: deletes uploaded blobs over an hour old that no profile
 * points at (rejected photos, uploads the app abandoned). Walks `_storage`
 * oldest first in pages, rescheduling itself until it reaches the cutoff.
 *
 * Keep-list: profile photos (`users.photoId`) are the only storage use
 * today. ANY future use of file storage must be added to `isKept` below,
 * or this sweep will delete those files.
 */
export const sweepOrphanBlobs = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())), cutoff: v.optional(v.number()) },
  handler: async (ctx, args): Promise<{ deleted: number }> => {
    const cutoff = args.cutoff ?? Date.now() - ORPHAN_BLOB_AGE_MS;
    const page = await ctx.db.system
      .query("_storage")
      .withIndex("by_creation_time", (q) => q.lt("_creationTime", cutoff))
      .paginate({ numItems: ORPHAN_SWEEP_BATCH, cursor: args.cursor ?? null });
    const isKept = async (id: Id<"_storage">) =>
      (await ctx.db
        .query("users")
        .withIndex("by_photoId", (q) => q.eq("photoId", id))
        .first()) !== null;
    let deleted = 0;
    for (const blob of page.page) {
      if (await isKept(blob._id)) continue;
      await ctx.storage.delete(blob._id);
      deleted++;
    }
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.users.sweepOrphanBlobs, {
        cursor: page.continueCursor,
        cutoff,
      });
    }
    if (deleted > 0) console.log(`Deleted ${deleted} orphan storage blobs`);
    return { deleted };
  },
});

/** Deletes the user's photo blob and clears it from the profile. */
export const removeAvatar = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    if (user._id !== args.userId) fail("not_authorized");
    if (user.photoId) {
      await deleteBlob(ctx, user.photoId);
      await ctx.db.patch(user._id, { photoId: undefined });
    }
    return null;
  },
});

/**
 * Deletes the account and everything the user shared, revoking their Apple
 * sign-in first so the stored Apple token is never lost before it's revoked.
 * - "revoked": Apple confirmed the revoke, then the data was deleted.
 * - "skipped": no Apple token was stored, so there was nothing to revoke.
 * - "queued": Apple couldn't be reached or refused, or the Apple env isn't
 *   set. The data is deleted anyway (deletion must not depend on Apple), and
 *   the token is kept in `appleRevocations` and retried until Apple
 *   confirms the revoke.
 */
export const deleteMyAccount = action({
  args: {},
  handler: async (ctx): Promise<{ appleRevoke: "revoked" | "skipped" | "queued" }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) fail("not_authenticated");
    const userId = identity.subject;
    const appleRefreshToken = await ctx.runQuery(internal.users.appleTokenFor, { userId });
    const result = await revokeAppleToken(appleRefreshToken);
    const { queued } = await ctx.runMutation(internal.users.deleteAccountData, {
      userId,
      ...(result === "revoked" && appleRefreshToken ? { revokedAppleToken: appleRefreshToken } : {}),
    });
    if (queued) return { appleRevoke: "queued" };
    return { appleRevoke: result === "revoked" ? "revoked" : "skipped" };
  },
});

/** The user's stored Apple refresh token; `not_authenticated` if they're gone. */
export const appleTokenFor = internalQuery({
  args: { userId: v.string() },
  handler: async (ctx, args): Promise<string | null> => {
    const userId = ctx.db.normalizeId("users", args.userId);
    const user = userId ? await ctx.db.get(userId) : null;
    if (!user) fail("not_authenticated");
    const row = await ctx.db
      .query("appleTokens")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .first();
    return row?.refreshToken ?? null;
  },
});

/**
 * Deletes every row of the user. If a stored Apple token wasn't the one just
 * revoked (the revoke failed or was skipped for missing env, or a new token
 * arrived meanwhile), it's queued in `appleRevocations` in the same
 * transaction, so it's never lost.
 */
export const deleteAccountData = internalMutation({
  args: { userId: v.string(), revokedAppleToken: v.optional(v.string()) },
  handler: async (ctx, args): Promise<{ queued: boolean }> => {
    const userId = ctx.db.normalizeId("users", args.userId);
    const user = userId ? await ctx.db.get(userId) : null;
    if (!user) fail("not_authenticated");
    const appleRefreshToken = await deleteUserData(ctx, user._id);
    if (!appleRefreshToken || appleRefreshToken === args.revokedAppleToken) return { queued: false };
    const now = Date.now();
    const delay = appleRevokeDelay(0);
    const id = await ctx.db.insert("appleRevocations", {
      refreshToken: appleRefreshToken,
      attempts: 0,
      nextAttemptAt: now + delay,
      createdAt: now,
    });
    await ctx.scheduler.runAfter(delay, internal.users.retryAppleRevoke, { id, attempt: 0 });
    return { queued: true };
  },
});

/**
 * One retry of a queued Apple revoke. `attempt` is the row's `attempts` when
 * this run was scheduled; a run whose attempt is stale (the recovery cron
 * doubled it and the other run already recorded) does nothing.
 */
export const retryAppleRevoke = internalAction({
  args: { id: v.id("appleRevocations"), attempt: v.number() },
  handler: async (ctx, args) => {
    const refreshToken = await ctx.runQuery(internal.users.pendingRevocation, args);
    if (refreshToken === null) return;
    const result = await revokeAppleToken(refreshToken);
    await ctx.runMutation(internal.users.recordRevokeAttempt, {
      ...args,
      revoked: result === "revoked", // "skipped" (env missing) is not a revoke
    });
  },
});

/** The queued token, or null if it's gone or `attempt` is stale. */
export const pendingRevocation = internalQuery({
  args: { id: v.id("appleRevocations"), attempt: v.number() },
  handler: async (ctx, args): Promise<string | null> => {
    const row = await ctx.db.get(args.id);
    return row && row.attempts === args.attempt ? row.refreshToken : null;
  },
});

/**
 * Drops the row only when Apple confirmed the revoke. Otherwise counts the
 * attempt and schedules the next one (backoff capped at daily, forever).
 * A stale attempt is ignored, so a doubled run never forks the retry chain.
 */
export const recordRevokeAttempt = internalMutation({
  args: { id: v.id("appleRevocations"), attempt: v.number(), revoked: v.boolean() },
  handler: async (ctx, args) => {
    const row = await ctx.db.get(args.id);
    if (!row) return;
    if (args.revoked) {
      await ctx.db.delete(row._id);
      return;
    }
    if (row.attempts !== args.attempt) return;
    const attempts = row.attempts + 1;
    const delay = appleRevokeDelay(attempts);
    if (attempts >= APPLE_REVOKE_RETRY_DELAYS_MS.length) {
      console.error(`Apple revoke still failing after ${attempts} retries; retrying daily until it succeeds`);
    }
    await ctx.db.patch(row._id, { attempts, nextAttemptAt: Date.now() + delay });
    await ctx.scheduler.runAfter(delay, internal.users.retryAppleRevoke, { id: row._id, attempt: attempts });
  },
});

/**
 * Hourly cron. Scheduled actions run at most once, so a retry can be lost
 * (platform failure, or the action died before recording its result). Any
 * row more than the grace period past its `nextAttemptAt` gets a fresh run.
 */
export const recoverAppleRevocations = internalMutation({
  args: {},
  handler: async (ctx): Promise<{ rescheduled: number }> => {
    const now = Date.now();
    const overdue = await ctx.db
      .query("appleRevocations")
      .withIndex("by_nextAttemptAt", (q) => q.lt("nextAttemptAt", now - APPLE_REVOKE_RECOVERY_GRACE_MS))
      .take(APPLE_REVOKE_RECOVERY_BATCH);
    for (const row of overdue) {
      await ctx.db.patch(row._id, { nextAttemptAt: now });
      await ctx.scheduler.runAfter(0, internal.users.retryAppleRevoke, { id: row._id, attempt: row.attempts });
    }
    if (overdue.length > 0) console.warn(`Rescheduled ${overdue.length} lost Apple revoke retries`);
    return { rescheduled: overdue.length };
  },
});
