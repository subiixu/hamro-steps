import { MutationCtx, QueryCtx } from "../_generated/server";
import { Doc, Id } from "../_generated/dataModel";
import { familyMembers } from "./access";

export async function stepsRow(ctx: QueryCtx, userId: Id<"users">, day: string) {
  return await ctx.db
    .query("dailySteps")
    .withIndex("by_user_day", (q) => q.eq("userId", userId).eq("day", day))
    .unique();
}

/** Sum of the current members' steps for `day`, straight from their rows. */
export async function liveTotal(
  ctx: QueryCtx,
  familyId: Id<"families">,
  day: string,
  members?: Doc<"memberships">[],
): Promise<number> {
  const list = members ?? (await familyMembers(ctx, familyId));
  let total = 0;
  for (const m of list) {
    const row = await stepsRow(ctx, m.userId, day);
    total += row?.steps ?? 0;
  }
  return total;
}

export async function snapshot(ctx: QueryCtx, familyId: Id<"families">, day: string) {
  return await ctx.db
    .query("familyDays")
    .withIndex("by_family_day", (q) => q.eq("familyId", familyId).eq("day", day))
    .unique();
}

/**
 * Sets a closed day's total to the sum of its contributions and recomputes
 * `hit` against the frozen goal. No-op when the day has no snapshot.
 * Returns whether the day is a hit afterwards.
 */
export async function recomputeSnapshot(
  ctx: MutationCtx,
  familyId: Id<"families">,
  day: string,
): Promise<boolean | null> {
  const snap = await snapshot(ctx, familyId, day);
  if (!snap) return null;
  let total = 0;
  for await (const c of ctx.db
    .query("dayContributions")
    .withIndex("by_family_day", (q) => q.eq("familyId", familyId).eq("day", day))) {
    total += c.steps;
  }
  const hit = total >= snap.goal;
  if (total !== snap.total || hit !== snap.hit) await ctx.db.patch(snap._id, { total, hit });
  return hit;
}
