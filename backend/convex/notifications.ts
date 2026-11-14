import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { internal } from "./_generated/api";
import { requireUser } from "./lib/access";
import { Doc, Id } from "./_generated/dataModel";
import { MAX_DEVICES_PER_USER } from "./lib/constants";
import { fail } from "./lib/errors";
import { nepalDay } from "./lib/nepalDay";
import { getPrefs, prefsRow, pushEveningNudge } from "./lib/push";
import { liveTotal } from "./lib/totals";

/** APNs tokens are hex; today 64 chars, but Apple says not to assume a length. */
const TOKEN_PATTERN = /^[0-9a-f]{16,400}$/;

function normaliseToken(raw: string) {
  const token = raw.trim().toLowerCase();
  if (!TOKEN_PATTERN.test(token) || token.length % 2 !== 0) fail("invalid_device_token");
  return token;
}

/**
 * Registers this phone's APNs token for the caller (contract F15). A token
 * another user had (same phone, different account) moves to the caller.
 * Keeps at most MAX_DEVICES_PER_USER per user, retiring the least recent.
 */
export const registerDevice = mutation({
  args: {
    apnsToken: v.string(),
    environment: v.union(v.literal("sandbox"), v.literal("production")),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const apnsToken = normaliseToken(args.apnsToken);
    const now = Date.now();
    const existing = await ctx.db
      .query("devices")
      .withIndex("by_token", (q) => q.eq("apnsToken", apnsToken))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, { userId: user._id, environment: args.environment, updatedAt: now });
    } else {
      await ctx.db.insert("devices", { apnsToken, userId: user._id, environment: args.environment, updatedAt: now });
    }
    // Keep this phone plus the most recent others, up to MAX_DEVICES_PER_USER.
    const others = (
      await ctx.db
        .query("devices")
        .withIndex("by_user_updated", (q) => q.eq("userId", user._id))
        .order("desc")
        .collect()
    ).filter((d) => d.apnsToken !== apnsToken);
    for (const stale of others.slice(MAX_DEVICES_PER_USER - 1)) await ctx.db.delete(stale._id);
    return null;
  },
});

/**
 * Stops pushes to this phone for the caller, e.g. on sign-out. A no-op when
 * the token isn't registered to them.
 */
export const unregisterDevice = mutation({
  args: { apnsToken: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const apnsToken = args.apnsToken.trim().toLowerCase();
    const existing = await ctx.db
      .query("devices")
      .withIndex("by_token", (q) => q.eq("apnsToken", apnsToken))
      .unique();
    if (existing && existing.userId === user._id) await ctx.db.delete(existing._id);
    return null;
  },
});

/** The caller's notification prefs; defaults until they change one. */
export const notificationPrefs = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    return await getPrefs(ctx, user._id);
  },
});

/** Sets any of the prefs; the rest keep their value. Returns all four. */
export const setNotificationPrefs = mutation({
  args: {
    walkStarted: v.optional(v.boolean()),
    goalHit: v.optional(v.boolean()),
    reactions: v.optional(v.boolean()),
    eveningNudge: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const prefs = { ...(await getPrefs(ctx, user._id)) };
    for (const key of ["walkStarted", "goalHit", "reactions", "eveningNudge"] as const) {
      const value = args[key];
      if (value !== undefined) prefs[key] = value;
    }
    const row = await prefsRow(ctx, user._id);
    if (row) await ctx.db.patch(row._id, prefs);
    else await ctx.db.insert("notificationPrefs", { userId: user._id, ...prefs });
    return prefs;
  },
});

const NUDGE_BATCH = 25;

/**
 * Daily at 19:00 Nepal (contract F16). Each person who opted in, and has a
 * family still under today's goal, gets one nudge about the family furthest
 * from its goal (lowest share of the goal; ties go to more steps left).
 *
 * Pages through opted-in people rather than families, so a person in
 * families on different pages is still nudged once. `lastNudgeDay` makes a
 * rerun on the same Nepal day a no-op. Relies on `eveningNudge` defaulting
 * to false: anyone without a prefs row hasn't opted in.
 */
export const eveningNudge = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())), day: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const day = args.day ?? nepalDay(Date.now());
    const page = await ctx.db
      .query("notificationPrefs")
      .withIndex("by_evening_nudge", (q) => q.eq("eveningNudge", true))
      .paginate({ numItems: NUDGE_BATCH, cursor: args.cursor ?? null });
    // Family totals don't change within this mutation; share them across the page.
    const progress = new Map<Id<"families">, Progress | null>();
    let nudged = 0;
    for (const prefs of page.page) {
      if (prefs.lastNudgeDay === day) continue;
      const memberships = await ctx.db
        .query("memberships")
        .withIndex("by_user", (q) => q.eq("userId", prefs.userId))
        .collect();
      let pick: Progress | null = null;
      for (const m of memberships) {
        if (!progress.has(m.familyId)) {
          const family = await ctx.db.get(m.familyId);
          progress.set(
            m.familyId,
            family ? { family, total: await liveTotal(ctx, family._id, day) } : null,
          );
        }
        const p = progress.get(m.familyId);
        if (!p || p.total >= p.family.dailyGoal) continue;
        if (!pick || furtherFromGoal(p, pick)) pick = p;
      }
      if (!pick) continue;
      await pushEveningNudge(ctx, prefs.userId, pick.family, pick.total);
      await ctx.db.patch(prefs._id, { lastNudgeDay: day });
      nudged++;
    }
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.notifications.eveningNudge, {
        cursor: page.continueCursor,
        day,
      });
    }
    return { nudged };
  },
});

type Progress = { family: Doc<"families">; total: number };

function furtherFromGoal(a: Progress, b: Progress) {
  const shareA = a.total / a.family.dailyGoal;
  const shareB = b.total / b.family.dailyGoal;
  if (shareA !== shareB) return shareA < shareB;
  return a.family.dailyGoal - a.total > b.family.dailyGoal - b.total;
}
