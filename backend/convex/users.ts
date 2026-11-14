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
import { requireUser } from "./lib/access";
import { revokeAppleToken } from "./lib/apple";
import { deleteUserData } from "./lib/cleanup";
import { APPLE_REVOKE_RETRY_DELAYS_MS } from "./lib/constants";
import { fail } from "./lib/errors";
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
    };
  },
});

export const updateProfile = mutation({
  args: { name: v.optional(v.string()), timezone: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const patch: { name?: string; timezone?: string } = {};
    if (args.name !== undefined) patch.name = cleanName(args.name);
    if (args.timezone !== undefined) patch.timezone = args.timezone.slice(0, 64);
    await ctx.db.patch(user._id, patch);
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
