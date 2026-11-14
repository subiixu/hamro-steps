import { v } from "convex/values";
import { query } from "./_generated/server";
import { familyMembers, requireMember } from "./lib/access";
import { activeStatus, openWalk } from "./lib/activity";
import { MAX_MEMBERS } from "./lib/constants";
import { nepalDay, nepalDayStart, weekDays } from "./lib/nepalDay";
import { liveTotal, snapshot, stepsRow } from "./lib/totals";

/**
 * Today's family progress, members in fixed order (never ranked).
 * `steps: null` means "not synced yet", never 0.
 */
export const familyToday = query({
  args: { familyId: v.id("families") },
  handler: async (ctx, args) => {
    const { family } = await requireMember(ctx, args.familyId);
    const now = Date.now();
    const day = nepalDay(now);
    const memberships = await familyMembers(ctx, family._id);
    let total = 0;
    const members = [];
    for (const m of memberships) {
      const user = await ctx.db.get(m.userId);
      if (!user) continue;
      const row = await stepsRow(ctx, m.userId, day);
      total += row?.steps ?? 0;
      const walk = await openWalk(ctx, m.userId, now);
      members.push({
        userId: user._id,
        name: user.name ?? null,
        avatarColor: user.avatarColor,
        position: m.position,
        isOrganiser: family.organiserId === user._id,
        steps: row ? row.steps : null,
        lastSyncedAt: user.lastSyncedAt ?? null,
        /** Open walk (not stopped, not past endsAt), else null. */
        walkingSince: walk ? walk.startedAt : null,
        walkEndsAt: walk ? walk.endsAt : null,
        /** Null when none or expired. */
        status: await activeStatus(ctx, m.userId, now),
      });
    }
    const goal = family.dailyGoal;
    return {
      family: {
        familyId: family._id,
        name: family.name,
        dailyGoal: family.dailyGoal,
        inviteCode: family.inviteCode,
        organiserId: family.organiserId,
        memberCount: members.length,
        isFull: members.length >= MAX_MEMBERS,
      },
      day,
      goal,
      total,
      /** Whole percent, not capped at 100. */
      percent: Math.floor((total * 100) / goal),
      members,
    };
  },
});

/**
 * Monday–Sunday of the current Nepal week. Closed days use their midnight
 * snapshot (frozen goal); today, and closed days with no snapshot, use live
 * totals against the current goal.
 */
export const familyWeek = query({
  args: { familyId: v.id("families") },
  handler: async (ctx, args) => {
    const { family } = await requireMember(ctx, args.familyId);
    const today = nepalDay(Date.now());
    const members = await familyMembers(ctx, family._id);
    const createdDay = nepalDay(family.createdAt);
    const days = [];
    for (const day of weekDays(today)) {
      const isFuture = day > today;
      const isBeforeFamily = day < createdDay;
      if (isFuture) {
        days.push({ day, total: 0, goal: family.dailyGoal, hit: false, isFuture, isBeforeFamily });
        continue;
      }
      const snap = day < today ? await snapshot(ctx, family._id, day) : null;
      if (snap) {
        days.push({ day, total: snap.total, goal: snap.goal, hit: snap.hit, isFuture, isBeforeFamily });
        continue;
      }
      const total = await liveTotal(ctx, family._id, day, members);
      const goal = family.dailyGoal;
      days.push({ day, total, goal, hit: total >= goal, isFuture, isBeforeFamily });
    }
    return { today, weekStart: days[0]!.day, startsAt: nepalDayStart(days[0]!.day), days };
  },
});
