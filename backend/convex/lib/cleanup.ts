import { MutationCtx } from "../_generated/server";
import { Doc, Id } from "../_generated/dataModel";
import { familyMembers } from "./access";
import { recomputeSnapshot } from "./totals";
import { deleteFamilyFeed, deleteMemberFeed, deleteUserFeed } from "./feed";
import { deleteUserPush } from "./push";

/**
 * Removes one membership and everything that member shared in that family:
 * their contributions to its closed days (each day's total and hit are
 * recomputed; the goal stays frozen). Their dailySteps rows are per user, so
 * they simply stop counting toward this family's today.
 * Walks and status are per user, not per family, so nothing to do for them.
 * Their feed events in this family (with others' reactions to them) and their
 * reactions to this family's events are deleted too.
 *
 * If they were the organiser, the earliest-joined remaining member (lowest
 * position) takes over. If nobody is left, the family is deleted.
 */
export async function removeMembership(ctx: MutationCtx, membership: Doc<"memberships">) {
  const family = await ctx.db.get(membership.familyId);
  await ctx.db.delete(membership._id);
  if (!family) return;

  await deleteMemberFeed(ctx, membership.userId, family._id);
  const remaining = await familyMembers(ctx, family._id);
  const next = remaining[0];
  if (!next) {
    await deleteFamily(ctx, family._id);
    return;
  }
  const contributions = await ctx.db
    .query("dayContributions")
    .withIndex("by_user_family", (q) =>
      q.eq("userId", membership.userId).eq("familyId", family._id),
    )
    .collect();
  for (const c of contributions) {
    await ctx.db.delete(c._id);
    await recomputeSnapshot(ctx, family._id, c.day);
  }
  if (family.organiserId === membership.userId) {
    await ctx.db.patch(family._id, { organiserId: next.userId });
  }
}

/** Deletes a family and its rows. Only called once it has no members. */
async function deleteFamily(ctx: MutationCtx, familyId: Id<"families">) {
  const days = await ctx.db
    .query("familyDays")
    .withIndex("by_family_day", (q) => q.eq("familyId", familyId))
    .collect();
  for (const d of days) await ctx.db.delete(d._id);
  const contributions = await ctx.db
    .query("dayContributions")
    .withIndex("by_family_day", (q) => q.eq("familyId", familyId))
    .collect();
  for (const c of contributions) await ctx.db.delete(c._id);
  await deleteFamilyFeed(ctx, familyId);
  await ctx.db.delete(familyId);
}

/**
 * Deletes a user and every row they own: memberships (with organiser
 * hand-off, and their closed-day contributions), steps, sessions, refresh tokens, Apple token. Returns Apple's
 * refresh token, if one was stored, so the caller can revoke it.
 * Also their walks (a pending autoStop then finds nothing) and status.
 * Also every feed event they posted and every reaction they made.
 * Also their push devices and notification prefs, and their profile photo blob.
 */
export async function deleteUserData(
  ctx: MutationCtx,
  userId: Id<"users">,
): Promise<string | null> {
  const memberships = await ctx.db
    .query("memberships")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect();
  for (const m of memberships) await removeMembership(ctx, m);
  // removeMembership already took these out; this catches any stragglers.
  const stragglers = await ctx.db
    .query("dayContributions")
    .withIndex("by_user_day", (q) => q.eq("userId", userId))
    .collect();
  for (const row of stragglers) {
    await ctx.db.delete(row._id);
    await recomputeSnapshot(ctx, row.familyId, row.day);
  }

  await deleteUserFeed(ctx, userId);
  await deleteUserPush(ctx, userId);

  for await (const row of ctx.db
    .query("dailySteps")
    .withIndex("by_user_day", (q) => q.eq("userId", userId))) {
    await ctx.db.delete(row._id);
  }
  for await (const row of ctx.db
    .query("refreshTokens")
    .withIndex("by_user", (q) => q.eq("userId", userId))) {
    await ctx.db.delete(row._id);
  }
  for await (const row of ctx.db
    .query("sessions")
    .withIndex("by_user", (q) => q.eq("userId", userId))) {
    await ctx.db.delete(row._id);
  }
  for await (const row of ctx.db
    .query("walks")
    .withIndex("by_user_open", (q) => q.eq("userId", userId))) {
    await ctx.db.delete(row._id);
  }
  for await (const row of ctx.db
    .query("statuses")
    .withIndex("by_user", (q) => q.eq("userId", userId))) {
    await ctx.db.delete(row._id);
  }
  let appleRefreshToken: string | null = null;
  for await (const row of ctx.db
    .query("appleTokens")
    .withIndex("by_user", (q) => q.eq("userId", userId))) {
    appleRefreshToken = row.refreshToken;
    await ctx.db.delete(row._id);
  }
  const user = await ctx.db.get(userId);
  if (user?.photoId) await deleteBlob(ctx, user.photoId);
  await ctx.db.delete(userId);
  return appleRefreshToken;
}

/** Deletes a storage blob, tolerating one that's already gone. */
export async function deleteBlob(ctx: MutationCtx, id: Id<"_storage">) {
  if (await ctx.db.system.get("_storage", id)) await ctx.storage.delete(id);
}
