import { MutationCtx } from "../_generated/server";
import { Doc, Id } from "../_generated/dataModel";
import { MEMBER_STEP_MILESTONES } from "./constants";
import { pushGoalHit } from "./push";
import { liveTotal } from "./totals";

export type FeedEventType = Doc<"feedEvents">["type"];

/**
 * Inserts a feed event. `member_*` and `family_*` are created at most once per
 * (family, day, type, actor); `walk_started` is created once per walk, so it
 * always inserts (contract F13). Returns the new event's id, or null when an
 * event with that key already existed.
 */
export async function postEvent(
  ctx: MutationCtx,
  e: {
    familyId: Id<"families">;
    type: FeedEventType;
    actorId: Id<"users"> | undefined;
    day: string;
    now: number;
    data?: Doc<"feedEvents">["data"];
  },
): Promise<Id<"feedEvents"> | null> {
  if (e.type !== "walk_started") {
    const existing = await ctx.db
      .query("feedEvents")
      .withIndex("by_family_day_type_actor", (q) =>
        q.eq("familyId", e.familyId).eq("day", e.day).eq("type", e.type).eq("actorId", e.actorId),
      )
      .first();
    if (existing) return null;
  }
  return await ctx.db.insert("feedEvents", {
    familyId: e.familyId,
    type: e.type,
    ...(e.actorId ? { actorId: e.actorId } : {}),
    day: e.day,
    createdAt: e.now,
    data: e.data ?? {},
  });
}

/**
 * Feed events for a user's today sync going from `before` to `after` steps:
 * member_5k / member_10k when they cross those, and family_50 / family_100 when
 * a family's live total crosses half or all of its goal. Call after the
 * dailySteps row holds `after`. Today only: late syncs never post events.
 */
export async function postTodayStepEvents(
  ctx: MutationCtx,
  userId: Id<"users">,
  today: string,
  before: number,
  after: number,
  now: number,
) {
  if (after <= before) return;
  const memberships = await ctx.db
    .query("memberships")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect();
  for (const m of memberships) {
    const family = await ctx.db.get(m.familyId);
    if (!family) continue;
    for (const { steps, type } of MEMBER_STEP_MILESTONES) {
      if (before < steps && after >= steps) {
        await postEvent(ctx, { familyId: family._id, type, actorId: userId, day: today, now });
      }
    }
    const totalAfter = await liveTotal(ctx, family._id, today);
    const totalBefore = totalAfter - (after - before);
    const goal = family.dailyGoal;
    if (totalBefore * 2 < goal && totalAfter * 2 >= goal) {
      await postEvent(ctx, { familyId: family._id, type: "family_50", actorId: undefined, day: today, now });
    }
    if (totalBefore < goal && totalAfter >= goal) {
      const id = await postEvent(ctx, {
        familyId: family._id,
        type: "family_100",
        actorId: undefined,
        day: today,
        now,
      });
      if (id) await pushGoalHit(ctx, family, id);
    }
  }
}

/** Deletes one event and every reaction to it. */
export async function deleteEvent(ctx: MutationCtx, eventId: Id<"feedEvents">) {
  for await (const r of ctx.db.query("reactions").withIndex("by_event", (q) => q.eq("eventId", eventId))) {
    await ctx.db.delete(r._id);
  }
  await ctx.db.delete(eventId);
}

/**
 * On leaving or removal: the member's events in that family (with everyone's
 * reactions to them) and the member's reactions to that family's events.
 */
export async function deleteMemberFeed(
  ctx: MutationCtx,
  userId: Id<"users">,
  familyId: Id<"families">,
) {
  const events = await ctx.db
    .query("feedEvents")
    .withIndex("by_actor_family", (q) => q.eq("actorId", userId).eq("familyId", familyId))
    .collect();
  for (const e of events) await deleteEvent(ctx, e._id);
  const reactions = await ctx.db
    .query("reactions")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect();
  for (const r of reactions) {
    const event = await ctx.db.get(r.eventId);
    if (!event || event.familyId === familyId) await ctx.db.delete(r._id);
  }
}

/** On account deletion: all of the user's events and reactions, anywhere. */
export async function deleteUserFeed(ctx: MutationCtx, userId: Id<"users">) {
  const events = await ctx.db
    .query("feedEvents")
    .withIndex("by_actor_family", (q) => q.eq("actorId", userId))
    .collect();
  for (const e of events) await deleteEvent(ctx, e._id);
  for await (const r of ctx.db.query("reactions").withIndex("by_user", (q) => q.eq("userId", userId))) {
    await ctx.db.delete(r._id);
  }
}

/** When an empty family is deleted: all its events and their reactions. */
export async function deleteFamilyFeed(ctx: MutationCtx, familyId: Id<"families">) {
  const events = await ctx.db
    .query("feedEvents")
    .withIndex("by_family_created", (q) => q.eq("familyId", familyId))
    .collect();
  for (const e of events) await deleteEvent(ctx, e._id);
}
