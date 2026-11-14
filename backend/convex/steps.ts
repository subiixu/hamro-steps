import { v } from "convex/values";
import { mutation, MutationCtx } from "./_generated/server";
import { Id } from "./_generated/dataModel";
import { requireUser } from "./lib/access";
import { fail } from "./lib/errors";
import { MAX_DAILY_STEPS } from "./lib/constants";
import { isValidDay, nepalDay, oldestSyncableDay } from "./lib/nepalDay";
import { recomputeSnapshot, stepsRow } from "./lib/totals";

/**
 * The app sends Nepal-day step totals (today plus up to the previous 6).
 * Each value replaces what was stored. Days already closed by the midnight
 * cron update the user's contribution and that family's snapshot total
 * (goal stays frozen), so a late sync can turn a closed day into a hit.
 */
export const syncSteps = mutation({
  args: { days: v.array(v.object({ day: v.string(), steps: v.number() })) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const now = Date.now();
    const today = nepalDay(now);
    const oldest = oldestSyncableDay(now);

    // Validate everything before writing anything. Later entries win.
    const byDay = new Map<string, number>();
    for (const { day, steps } of args.days) {
      if (!isValidDay(day) || day > today || day < oldest) fail("invalid_day");
      if (!Number.isInteger(steps) || steps < 0 || steps > MAX_DAILY_STEPS) {
        fail("invalid_steps");
      }
      byDay.set(day, steps);
    }

    for (const [day, steps] of byDay) {
      const row = await stepsRow(ctx, user._id, day);
      if (row) {
        await ctx.db.patch(row._id, { steps, updatedAt: now });
      } else {
        await ctx.db.insert("dailySteps", { userId: user._id, day, steps, updatedAt: now });
      }
      if (day < today) await applyLateSync(ctx, user._id, day, steps);
    }
    await ctx.db.patch(user._id, { lastSyncedAt: now });
    return { lastSyncedAt: now, today };
  },
});

/**
 * Updates the user's contribution to each family day that counted them at
 * the close, and recomputes that day's total and hit. Families they joined
 * after the close never counted them for that day, so have no row.
 */
async function applyLateSync(ctx: MutationCtx, userId: Id<"users">, day: string, steps: number) {
  const contributions = await ctx.db
    .query("dayContributions")
    .withIndex("by_user_day", (q) => q.eq("userId", userId).eq("day", day))
    .collect();
  for (const c of contributions) {
    if (c.steps === steps) continue;
    await ctx.db.patch(c._id, { steps });
    await recomputeSnapshot(ctx, c.familyId, day);
    // Phase 2: if `hit` just flipped to true, post the "family hit the goal" event.
  }
}
