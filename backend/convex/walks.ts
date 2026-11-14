import { v } from "convex/values";
import { internalMutation, mutation } from "./_generated/server";
import { internal } from "./_generated/api";
import { requireUser } from "./lib/access";
import { openWalk } from "./lib/activity";
import { MAX_WALKS_PER_DAY, WALK_DURATION_MS } from "./lib/constants";
import { fail } from "./lib/errors";
import { nepalDay } from "./lib/nepalDay";
import { postEvent } from "./lib/feed";

/**
 * Starts a 2-hour walk (contract F9). At most one open walk per user and 3
 * starts per Nepal day (counted by the day the walk started).
 */
export const startWalk = mutation({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    const now = Date.now();

    const unended = await ctx.db
      .query("walks")
      .withIndex("by_user_open", (q) => q.eq("userId", user._id).eq("endedAt", undefined))
      .collect();
    for (const w of unended) {
      if (w.endsAt > now) fail("already_walking");
      // Past endsAt but its autoStop hasn't run yet: close it now.
      await ctx.db.patch(w._id, { endedAt: w.endsAt });
    }

    const day = nepalDay(now);
    const today = await ctx.db
      .query("walks")
      .withIndex("by_user_day", (q) => q.eq("userId", user._id).eq("nepalDay", day))
      .take(MAX_WALKS_PER_DAY);
    if (today.length >= MAX_WALKS_PER_DAY) fail("walk_limit_reached");

    const endsAt = now + WALK_DURATION_MS;
    const walkId = await ctx.db.insert("walks", {
      userId: user._id,
      startedAt: now,
      endsAt,
      nepalDay: day,
    });
    await ctx.scheduler.runAt(endsAt, internal.walks.autoStop, { walkId });

    // A `walk_started` event in each of their families. Like every feed type
    // it's at most once per (family, actor, day), so only the day's first walk posts.
    const memberships = await ctx.db
      .query("memberships")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    for (const m of memberships) {
      await postEvent(ctx, {
        familyId: m.familyId,
        type: "walk_started",
        actorId: user._id,
        day,
        now,
        data: { walkId },
      });
    }
    // 2c: push — to every other member who hasn't muted walks (contract F9).

    return { walkId, startedAt: now, endsAt };
  },
});

/** Ends the user's open walk. A no-op when they aren't walking (contract F10). */
export const stopWalk = mutation({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    const now = Date.now();
    const walk = await openWalk(ctx, user._id, now);
    if (walk) await ctx.db.patch(walk._id, { endedAt: now });
    return null;
  },
});

/**
 * Scheduled at `endsAt` by `startWalk` (contract F11). Idempotent: does nothing
 * when the walk was already stopped or deleted with the account.
 */
export const autoStop = internalMutation({
  args: { walkId: v.id("walks") },
  handler: async (ctx, args) => {
    const walk = await ctx.db.get(args.walkId);
    if (!walk || walk.endedAt !== undefined) return null;
    await ctx.db.patch(walk._id, { endedAt: Math.min(walk.endsAt, Date.now()) });
    return null;
  },
});
