import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { addDays, nepalDay } from "./lib/nepalDay";
import { familyMembers } from "./lib/access";
import { snapshot, stepsRow } from "./lib/totals";

/**
 * Runs at Nepal midnight (crons.ts). Snapshots each family's total and goal
 * for the day that just ended, so a later goal change can't rewrite it, plus
 * one `dayContributions` row per member at the close.
 * Idempotent: an existing snapshot is left alone.
 *
 * Collects all families in one transaction, which is fine for the pilot;
 * past a few thousand families, page through them instead.
 */
export const closeDay = internalMutation({
  args: { day: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const now = Date.now();
    // At 18:15 UTC the new Nepal day has just begun; close the one before it.
    const day = args.day ?? addDays(nepalDay(now), -1);
    let closed = 0;
    for await (const family of ctx.db.query("families")) {
      if (await snapshot(ctx, family._id, day)) continue;
      // Record who counted, so a late sync or a member leaving can adjust it.
      let total = 0;
      for (const m of await familyMembers(ctx, family._id)) {
        const steps = (await stepsRow(ctx, m.userId, day))?.steps ?? 0;
        total += steps;
        await ctx.db.insert("dayContributions", { familyId: family._id, day, userId: m.userId, steps });
      }
      await ctx.db.insert("familyDays", {
        familyId: family._id,
        day,
        goal: family.dailyGoal,
        total,
        hit: total >= family.dailyGoal,
        closedAt: now,
      });
      closed++;
    }
    return { day, closed };
  },
});
