import { MutationCtx, QueryCtx } from "../_generated/server";
import { Doc, Id } from "../_generated/dataModel";
import { internal } from "../_generated/api";
import { familyMembers } from "./access";
import {
  DEFAULT_NOTIFICATION_PREFS,
  REACTION_PUSH_COALESCE_MS,
  ReactionEmoji,
} from "./constants";

/**
 * Who gets which push (contract F9, F13–F16). Mutations only decide recipients
 * and copy here; delivery runs later in `pushNode.send`, never inline.
 */

export type NotificationPrefs = {
  walkStarted: boolean;
  goalHit: boolean;
  reactions: boolean;
  eveningNudge: boolean;
};
export type PrefKey = keyof NotificationPrefs;

/** `type` in the push payload, so the app can route a tap. */
export type PushType = "walk_started" | "family_100" | "reaction" | "evening_nudge";

export async function prefsRow(ctx: QueryCtx, userId: Id<"users">) {
  return await ctx.db
    .query("notificationPrefs")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .unique();
}

export async function getPrefs(ctx: QueryCtx, userId: Id<"users">): Promise<NotificationPrefs> {
  const row = await prefsRow(ctx, userId);
  return {
    walkStarted: row?.walkStarted ?? DEFAULT_NOTIFICATION_PREFS.walkStarted,
    goalHit: row?.goalHit ?? DEFAULT_NOTIFICATION_PREFS.goalHit,
    reactions: row?.reactions ?? DEFAULT_NOTIFICATION_PREFS.reactions,
    eveningNudge: row?.eveningNudge ?? DEFAULT_NOTIFICATION_PREFS.eveningNudge,
  };
}

/** The users in `userIds` (deduped, in order) who have `pref` on. */
async function optedIn(ctx: QueryCtx, userIds: Id<"users">[], pref: PrefKey) {
  const out: Id<"users">[] = [];
  for (const id of new Set(userIds)) {
    if ((await getPrefs(ctx, id))[pref]) out.push(id);
  }
  return out;
}

/** Schedules one delivery to every device of `userIds`. Nothing when empty. */
export async function enqueuePush(
  ctx: MutationCtx,
  p: {
    userIds: Id<"users">[];
    title: string;
    body: string;
    type: PushType;
    familyId: Id<"families">;
    eventId?: Id<"feedEvents">;
  },
) {
  if (p.userIds.length === 0) return;
  await ctx.scheduler.runAfter(0, internal.pushNode.send, {
    userIds: p.userIds,
    alert: { title: p.title, body: p.body },
    data: {
      type: p.type,
      familyId: p.familyId,
      ...(p.eventId ? { eventId: p.eventId } : {}),
    },
  });
}

function displayName(user: Doc<"users"> | null) {
  return user?.name?.trim() || "Someone in your family";
}

/**
 * "Aama started a walk" to every member of each of the walker's families,
 * except the walker. One push per person even when they share several
 * families with the walker; it routes to the first shared family (in the
 * walker's membership order) and that family's event.
 */
export async function pushWalkStarted(
  ctx: MutationCtx,
  walker: Doc<"users">,
  events: { familyId: Id<"families">; eventId: Id<"feedEvents"> | null }[],
) {
  const routes = new Map<Id<"users">, { familyId: Id<"families">; eventId: Id<"feedEvents"> | null }>();
  for (const e of events) {
    for (const m of await familyMembers(ctx, e.familyId)) {
      if (m.userId !== walker._id && !routes.has(m.userId)) routes.set(m.userId, e);
    }
  }
  const recipients = await optedIn(ctx, [...routes.keys()], "walkStarted");
  // One delivery per routed family, so each person gets one push.
  const byFamily = new Map<string, Id<"users">[]>();
  for (const id of recipients) {
    const key = routes.get(id)!.familyId;
    byFamily.set(key, [...(byFamily.get(key) ?? []), id]);
  }
  for (const e of events) {
    const userIds = byFamily.get(e.familyId);
    if (!userIds) continue;
    await enqueuePush(ctx, {
      userIds,
      title: `${displayName(walker)} started a walk`,
      body: "Want to join? Give them a call.",
      type: "walk_started",
      familyId: e.familyId,
      ...(e.eventId ? { eventId: e.eventId } : {}),
    });
  }
}

/** The family hit today's goal: every member who hasn't muted goal pushes. */
export async function pushGoalHit(
  ctx: MutationCtx,
  family: Doc<"families">,
  eventId: Id<"feedEvents">,
) {
  const members = await familyMembers(ctx, family._id);
  const userIds = await optedIn(ctx, members.map((m) => m.userId), "goalHit");
  await enqueuePush(ctx, {
    userIds,
    title: `${family.name} reached today's goal`,
    body: "Every step counted. Well walked, everyone.",
    type: "family_100",
    familyId: family._id,
    eventId,
  });
}

const REACTED_TO: Record<Doc<"feedEvents">["type"], string> = {
  member_5k: "your 5,000 steps",
  member_10k: "your 10,000 steps",
  walk_started: "your walk",
  family_50: "your family's progress",
  family_100: "your family's goal",
};

/**
 * "Aama reacted 👏 to your walk" to the event's actor, unless it's their own
 * reaction, they muted reactions, or the event already pushed a reaction in
 * the last 10 minutes. Call when a reaction is added or replaced.
 */
export async function pushReaction(
  ctx: MutationCtx,
  event: Doc<"feedEvents">,
  reactor: Doc<"users">,
  emoji: ReactionEmoji,
  now: number,
) {
  if (!event.actorId || event.actorId === reactor._id) return;
  if (event.lastReactionPushAt !== undefined && now - event.lastReactionPushAt < REACTION_PUSH_COALESCE_MS) {
    return;
  }
  if (!(await getPrefs(ctx, event.actorId)).reactions) return;
  await ctx.db.patch(event._id, { lastReactionPushAt: now });
  const family = await ctx.db.get(event.familyId);
  await enqueuePush(ctx, {
    userIds: [event.actorId],
    title: `${displayName(reactor)} reacted ${emoji} to ${REACTED_TO[event.type]}`,
    body: family ? `In ${family.name}.` : "In your family.",
    type: "reaction",
    familyId: event.familyId,
    eventId: event._id,
  });
}

/** The evening nudge's copy. Names nobody: only the family's progress. */
export function nudgeCopy(total: number, goal: number) {
  const percent = Math.floor((total / goal) * 100);
  return {
    title: "An evening walk?",
    body:
      total === 0
        ? "Your family hasn't logged steps yet today. A short evening walk would be a lovely start."
        : `Your family is at ${percent}% today. A short evening walk would help everyone get there.`,
  };
}

/**
 * The evening nudge for one person, about one of their families under its
 * goal. The caller picks the family and checks the pref.
 */
export async function pushEveningNudge(
  ctx: MutationCtx,
  userId: Id<"users">,
  family: Doc<"families">,
  total: number,
) {
  const { title, body } = nudgeCopy(total, family.dailyGoal);
  await enqueuePush(ctx, { userIds: [userId], title, body, type: "evening_nudge", familyId: family._id });
}

/** On account deletion: their devices and prefs. */
export async function deleteUserPush(ctx: MutationCtx, userId: Id<"users">) {
  for await (const row of ctx.db.query("devices").withIndex("by_user", (q) => q.eq("userId", userId))) {
    await ctx.db.delete(row._id);
  }
  const prefs = await prefsRow(ctx, userId);
  if (prefs) await ctx.db.delete(prefs._id);
}
