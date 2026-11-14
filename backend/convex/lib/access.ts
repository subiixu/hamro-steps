import { QueryCtx } from "../_generated/server";
import { Doc, Id } from "../_generated/dataModel";
import { fail } from "./errors";

/** The signed-in user, or `not_authenticated`. */
export async function requireUser(ctx: QueryCtx): Promise<Doc<"users">> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) fail("not_authenticated");
  const userId = ctx.db.normalizeId("users", identity.subject);
  const user = userId ? await ctx.db.get(userId) : null;
  if (!user) fail("not_authenticated");
  return user;
}

export async function getMembership(
  ctx: QueryCtx,
  familyId: Id<"families">,
  userId: Id<"users">,
) {
  return await ctx.db
    .query("memberships")
    .withIndex("by_family_user", (q) => q.eq("familyId", familyId).eq("userId", userId))
    .unique();
}

/**
 * The signed-in user plus the family and their membership, or `not_member`.
 * A family that doesn't exist is also `not_member`, so ids leak nothing.
 */
export async function requireMember(ctx: QueryCtx, familyId: Id<"families">) {
  const user = await requireUser(ctx);
  const family = await ctx.db.get(familyId);
  const membership = family ? await getMembership(ctx, familyId, user._id) : null;
  if (!family || !membership) fail("not_member");
  return { user, family, membership };
}

export async function requireOrganiser(ctx: QueryCtx, familyId: Id<"families">) {
  const result = await requireMember(ctx, familyId);
  if (result.family.organiserId !== result.user._id) fail("not_organiser");
  return result;
}

/** Memberships of a family in fixed order. */
export async function familyMembers(ctx: QueryCtx, familyId: Id<"families">) {
  return await ctx.db
    .query("memberships")
    .withIndex("by_family_position", (q) => q.eq("familyId", familyId))
    .collect();
}
