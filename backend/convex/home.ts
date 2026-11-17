import { v } from "convex/values";
import { query } from "./_generated/server";
import { familyMembers, requireMember } from "./lib/access";
import { activeStatus, openWalk } from "./lib/activity";
import { MAX_MEMBERS } from "./lib/constants";
import { memberProfile } from "./lib/profile";
import { addDays, nepalDay, nepalDayStart, weekDays } from "./lib/nepalDay";
import { fail } from "./lib/errors";
import { familyDayProgress, stepsRow } from "./lib/totals";

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
        ...(await memberProfile(ctx, user)),
        birthday: user.birthday ?? null,
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
      const progress = await familyDayProgress(ctx, family, day, today, members);
      days.push({ day, ...progress, isFuture, isBeforeFamily });
    }
    return { today, weekStart: days[0]!.day, startsAt: nepalDayStart(days[0]!.day), days };
  },
});

/** Ranges the History screen offers, in days. */
const HISTORY_RANGES = [7, 30, 90];

/**
 * Daily family totals vs goal for 2 × `days` Nepal days ending today,
 * oldest first: the client shows the last `days` and compares them with the
 * `days` before. Same per-day rules as `familyWeek`. Days before the family
 * existed are flagged and not totalled.
 */
export const familyHistory = query({
  args: { familyId: v.id("families"), days: v.number() },
  handler: async (ctx, args) => {
    const { family } = await requireMember(ctx, args.familyId);
    if (!HISTORY_RANGES.includes(args.days)) fail("invalid_day", "days must be 7, 30 or 90");
    const today = nepalDay(Date.now());
    const createdDay = nepalDay(family.createdAt);
    const members = await familyMembers(ctx, family._id);
    const count = args.days * 2;
    const days = [];
    for (let i = count - 1; i >= 0; i--) {
      const day = addDays(today, -i);
      if (day < createdDay) {
        days.push({ day, total: 0, goal: family.dailyGoal, hit: false, isBeforeFamily: true });
        continue;
      }
      const progress = await familyDayProgress(ctx, family, day, today, members);
      days.push({ day, ...progress, isBeforeFamily: false });
    }
    return { today, days };
  },
});
