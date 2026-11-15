import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { internal } from "./_generated/api";
import { Doc } from "./_generated/dataModel";
import { getMembership, requireMember, requireUser } from "./lib/access";
import { memberProfile } from "./lib/profile";
import {
  FEED_MAX_EVENTS,
  FEED_RETENTION_MS,
  FEED_WINDOW_DAYS,
  REACTION_EMOJI,
  ReactionEmoji,
} from "./lib/constants";
import { fail } from "./lib/errors";
import { deleteEvent } from "./lib/feed";
import { pushReaction } from "./lib/push";
import { addDays, nepalDay } from "./lib/nepalDay";

/** The oldest Nepal day `feed` shows at `now`: today and the 2 days before. */
function oldestFeedDay(now: number) {
  return addDays(nepalDay(now), -(FEED_WINDOW_DAYS - 1));
}

/**
 * The family feed (contract F13): events from the last 3 Nepal days, newest
 * first, at most 100, each with reaction counts in the fixed emoji order and
 * the caller's own reaction.
 */
export const feed = query({
  args: { familyId: v.id("families") },
  handler: async (ctx, args) => {
    const { user } = await requireMember(ctx, args.familyId);
    const oldest = oldestFeedDay(Date.now());

    const events: Doc<"feedEvents">[] = [];
    for await (const e of ctx.db
      .query("feedEvents")
      .withIndex("by_family_created", (q) => q.eq("familyId", args.familyId))
      .order("desc")) {
      if (e.day < oldest) break;
      events.push(e);
      if (events.length >= FEED_MAX_EVENTS) break;
    }

    type Actor = {
      userId: Doc<"users">["_id"];
      name: string | null;
      avatarColor: string;
      photoUrl: string | null;
      city: string | null;
      timezone: string | null;
    };
    const actors = new Map<string, Actor | null>();
    const result = [];
    for (const e of events) {
      let actor = null;
      if (e.actorId) {
        if (!actors.has(e.actorId)) {
          const u = await ctx.db.get(e.actorId);
          actors.set(
            e.actorId,
            u
              ? { userId: u._id, name: u.name ?? null, avatarColor: u.avatarColor, ...(await memberProfile(ctx, u)) }
              : null,
          );
        }
        actor = actors.get(e.actorId) ?? null;
      }
      const counts = new Map<string, number>();
      let myReaction: ReactionEmoji | null = null;
      for await (const r of ctx.db.query("reactions").withIndex("by_event", (q) => q.eq("eventId", e._id))) {
        counts.set(r.emoji, (counts.get(r.emoji) ?? 0) + 1);
        if (r.userId === user._id) myReaction = r.emoji as ReactionEmoji;
      }
      result.push({
        id: e._id,
        type: e.type,
        actor,
        day: e.day,
        createdAt: e.createdAt,
        data: e.data,
        reactions: REACTION_EMOJI.filter((emoji) => counts.has(emoji)).map((emoji) => ({
          emoji,
          count: counts.get(emoji)!,
        })),
        myReaction,
      });
    }
    return result;
  },
});

/** ❤ without the VS16 selector is accepted and stored as ❤️. */
function normaliseEmoji(emoji: string): ReactionEmoji | null {
  const e = emoji === "❤" ? "❤️" : emoji;
  return (REACTION_EMOJI as readonly string[]).includes(e) ? (e as ReactionEmoji) : null;
}

/**
 * One reaction per user per event (contract F14). The same emoji again
 * removes it; a different one replaces it. Returns the caller's reaction
 * afterwards. An event that doesn't exist, is outside the feed window or is
 * in a family the caller isn't in gives `not_member`.
 */
export const react = mutation({
  args: { eventId: v.string(), emoji: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const emoji = normaliseEmoji(args.emoji);
    if (!emoji) fail("invalid_emoji");

    const eventId = ctx.db.normalizeId("feedEvents", args.eventId);
    const event = eventId ? await ctx.db.get(eventId) : null;
    const visible =
      event &&
      event.day >= oldestFeedDay(Date.now()) &&
      (await getMembership(ctx, event.familyId, user._id));
    if (!event || !visible) fail("not_member");

    const existing = await ctx.db
      .query("reactions")
      .withIndex("by_event_user", (q) => q.eq("eventId", event._id).eq("userId", user._id))
      .unique();
    if (existing?.emoji === emoji) {
      await ctx.db.delete(existing._id);
      return { myReaction: null };
    }
    if (existing) await ctx.db.patch(existing._id, { emoji });
    else await ctx.db.insert("reactions", { eventId: event._id, userId: user._id, emoji });

    await pushReaction(ctx, event, user, emoji, Date.now());
    return { myReaction: emoji };
  },
});

const PURGE_BATCH = 200;

/**
 * Daily: deletes feed events older than 7 days, with their reactions. Works
 * in batches and reschedules itself while more remain.
 */
export const purgeOld = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = Date.now() - FEED_RETENTION_MS;
    const old = await ctx.db
      .query("feedEvents")
      .withIndex("by_createdAt", (q) => q.lt("createdAt", cutoff))
      .take(PURGE_BATCH);
    for (const e of old) await deleteEvent(ctx, e._id);
    if (old.length === PURGE_BATCH) await ctx.scheduler.runAfter(0, internal.feed.purgeOld, {});
    return { deleted: old.length };
  },
});
