import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import crons from "../convex/crons";
import { expectCode, makeUser, newTest, setNow, T, User } from "./helpers";

let t: T;
beforeEach(() => {
  t = newTest();
  setNow("2026-11-14T06:00:00Z"); // Saturday 14 Nov in Nepal (11:45)
});
afterEach(() => vi.useRealTimers());

async function family(n: number, dailyGoal = 10000) {
  const organiser = await makeUser(t, "Organiser");
  const f = await organiser.as.mutation(api.families.createFamily, { name: "Family", dailyGoal });
  const members: User[] = [organiser];
  for (let i = 1; i < n; i++) {
    const m = await makeUser(t, i === n - 1 ? null : `Member ${i}`);
    await m.as.mutation(api.families.joinFamily, { code: f.inviteCode });
    members.push(m);
  }
  return { familyId: f.familyId as Id<"families">, inviteCode: f.inviteCode, members, organiser };
}

const sync = (u: User, days: { day: string; steps: number }[]) =>
  u.as.mutation(api.steps.syncSteps, { days });

async function rows(userId: Id<"users">) {
  return await t.run((ctx) =>
    ctx.db.query("dailySteps").withIndex("by_user_day", (q) => q.eq("userId", userId)).collect(),
  );
}

describe("syncSteps", () => {
  test("accepts today plus the previous 6 days, nothing else", async () => {
    const u = await makeUser(t);
    await expectCode(sync(u, [{ day: "2026-11-15", steps: 1 }]), "invalid_day");
    await expectCode(sync(u, [{ day: "2026-11-07", steps: 1 }]), "invalid_day");
    await expectCode(sync(u, [{ day: "14/11/2026", steps: 1 }]), "invalid_day");
    await expectCode(sync(u, [{ day: "2026-02-30", steps: 1 }]), "invalid_day");
    await sync(u, [
      { day: "2026-11-08", steps: 100 },
      { day: "2026-11-14", steps: 200 },
    ]);
    expect((await rows(u.id)).map((r) => [r.day, r.steps])).toEqual([
      ["2026-11-08", 100],
      ["2026-11-14", 200],
    ]);
  });

  test("rejects steps outside 0–200,000 and writes nothing from a bad batch", async () => {
    const u = await makeUser(t);
    for (const steps of [-1, 200_001, 12.5, Number.NaN]) {
      await expectCode(sync(u, [{ day: "2026-11-13", steps: 5 }, { day: "2026-11-14", steps }]), "invalid_steps");
    }
    expect(await rows(u.id)).toEqual([]);
    await sync(u, [{ day: "2026-11-14", steps: 0 }, { day: "2026-11-13", steps: 200_000 }]);
    expect((await rows(u.id)).length).toBe(2);
  });

  test("replaces the stored value and sets lastSyncedAt", async () => {
    const u = await makeUser(t);
    await sync(u, [{ day: "2026-11-14", steps: 5000 }]);
    vi.setSystemTime(new Date("2026-11-14T07:00:00Z"));
    const res = await sync(u, [{ day: "2026-11-14", steps: 4800 }]);
    const at = Date.parse("2026-11-14T07:00:00Z");
    expect(res.today).toBe("2026-11-14");
    expect(res.lastSyncedAt - at).toBeLessThan(1000);
    expect((await rows(u.id)).map((r) => r.steps)).toEqual([4800]);
    expect((await u.as.query(api.users.me, {})).lastSyncedAt).toBe(res.lastSyncedAt);
  });

  test("today changes at Nepal midnight (18:15 UTC)", async () => {
    const u = await makeUser(t);
    vi.setSystemTime(new Date("2026-11-14T18:14:59Z"));
    await expectCode(sync(u, [{ day: "2026-11-15", steps: 10 }]), "invalid_day");
    vi.setSystemTime(new Date("2026-11-14T18:15:00Z"));
    await sync(u, [{ day: "2026-11-15", steps: 10 }]);
    await expectCode(sync(u, [{ day: "2026-11-08", steps: 10 }]), "invalid_day");
  });

  test("needs sign-in", async () => {
    await expectCode(t.mutation(api.steps.syncSteps, { days: [] }), "not_authenticated");
  });
});

describe("familyToday", () => {
  test("fixed order, null for unsynced members, uncapped percent", async () => {
    const { familyId, members, organiser } = await family(4, 10000);
    // The last member syncs the most; order must not change.
    await sync(members[3]!, [{ day: "2026-11-14", steps: 9000 }]);
    await sync(members[1]!, [{ day: "2026-11-14", steps: 0 }]);
    await sync(organiser, [{ day: "2026-11-13", steps: 7000 }]); // yesterday only

    const today = await members[2]!.as.query(api.home.familyToday, { familyId });
    expect(today).toMatchObject({ day: "2026-11-14", goal: 10000, total: 9000, percent: 90 });
    expect(today.members.map((m) => [m.position, m.steps, m.isOrganiser])).toEqual([
      [0, null, true],
      [1, 0, false],
      [2, null, false],
      [3, 9000, false],
    ]);
    expect(today.members[0]!.lastSyncedAt! - Date.parse("2026-11-14T06:00:00Z")).toBeLessThan(1000);
    expect(today.members[2]!.lastSyncedAt).toBeNull();
    expect(today.members[3]!.name).toBeNull();
    expect(today.members.every((m) => m.status === null)).toBe(true);

    await sync(organiser, [{ day: "2026-11-14", steps: 6000 }]);
    const over = await organiser.as.query(api.home.familyToday, { familyId });
    expect([over.total, over.percent]).toEqual([15000, 150]);
  });

  test("a member's steps count in every family they're in", async () => {
    const a = await family(1);
    const b = await family(1);
    const u = await makeUser(t);
    await u.as.mutation(api.families.joinFamily, { code: a.inviteCode });
    await u.as.mutation(api.families.joinFamily, { code: b.inviteCode });
    await sync(u, [{ day: "2026-11-14", steps: 3000 }]);
    expect((await u.as.query(api.home.familyToday, { familyId: a.familyId })).total).toBe(3000);
    expect((await u.as.query(api.home.familyToday, { familyId: b.familyId })).total).toBe(3000);
  });
});

describe("closing days and familyWeek", () => {
  test("the cron runs daily at 18:15 UTC", () => {
    const job = (crons as unknown as { crons: Record<string, { name: string; schedule: unknown }> }).crons["close Nepal day"];
    expect(job?.name).toBe("days:closeDay");
    expect(job?.schedule).toEqual({ type: "daily", hourUTC: 18, minuteUTC: 15 });
  });

  test("snapshots keep their goal through a mid-week goal change", async () => {
    setNow("2026-11-09T03:00:00Z"); // Monday in Nepal
    const { familyId, members, organiser } = await family(2, 10000);
    const [a, b] = [organiser, members[1]!];
    await sync(a, [{ day: "2026-11-09", steps: 6000 }]);
    await sync(b, [{ day: "2026-11-09", steps: 5000 }]);

    vi.setSystemTime(new Date("2026-11-09T18:15:00Z")); // Nepal midnight → Tuesday
    expect(await t.mutation(internal.days.closeDay, {})).toEqual({ day: "2026-11-09", closed: 1 });
    expect(await t.mutation(internal.days.closeDay, {})).toEqual({ day: "2026-11-09", closed: 0 });

    vi.setSystemTime(new Date("2026-11-10T06:00:00Z"));
    await sync(a, [{ day: "2026-11-10", steps: 4000 }]);
    await sync(b, [{ day: "2026-11-10", steps: 4000 }]);
    vi.setSystemTime(new Date("2026-11-10T18:15:00Z"));
    await t.mutation(internal.days.closeDay, {}); // Tuesday: 8,000 of 10,000

    vi.setSystemTime(new Date("2026-11-11T06:00:00Z")); // Wednesday
    await organiser.as.mutation(api.families.updateFamily, { familyId, dailyGoal: 7000 });
    await sync(a, [{ day: "2026-11-11", steps: 7500 }]);

    const week = await b.as.query(api.home.familyWeek, { familyId });
    expect(week.today).toBe("2026-11-11");
    expect(week.weekStart).toBe("2026-11-09");
    expect(week.days.map((d) => [d.day, d.total, d.goal, d.hit, d.isFuture])).toEqual([
      ["2026-11-09", 11000, 10000, true, false],
      ["2026-11-10", 8000, 10000, false, false], // would be a hit at the new 7,000 goal
      ["2026-11-11", 7500, 7000, true, false],
      ["2026-11-12", 0, 7000, false, true],
      ["2026-11-13", 0, 7000, false, true],
      ["2026-11-14", 0, 7000, false, true],
      ["2026-11-15", 0, 7000, false, true],
    ]);
  });

  test("a closed day with no snapshot falls back to live totals", async () => {
    setNow("2026-11-10T06:00:00Z"); // Tuesday
    const { familyId, organiser } = await family(1, 5000);
    await sync(organiser, [{ day: "2026-11-09", steps: 6000 }]); // before the family existed
    const week = await organiser.as.query(api.home.familyWeek, { familyId });
    expect(week.days[0]).toEqual({ day: "2026-11-09", total: 6000, goal: 5000, hit: true, isFuture: false, isBeforeFamily: true });
    expect(week.days[1]).toMatchObject({ day: "2026-11-10", total: 0, isBeforeFamily: false });
  });

  test("a late sync updates a closed day's total and can flip it to a hit", async () => {
    setNow("2026-11-12T06:00:00Z");
    const { familyId, inviteCode, members, organiser } = await family(2, 10000);
    await sync(organiser, [{ day: "2026-11-12", steps: 6000 }]);
    await sync(members[1]!, [{ day: "2026-11-12", steps: 1000 }]);
    vi.setSystemTime(new Date("2026-11-12T18:15:00Z"));
    await t.mutation(internal.days.closeDay, {});

    // Next morning, before anyone joins, the parent's phone catches up on yesterday.
    vi.setSystemTime(new Date("2026-11-13T02:00:00Z"));
    const late = await makeUser(t, "Joined today");
    await late.as.mutation(api.families.joinFamily, { code: inviteCode });
    await sync(members[1]!, [{ day: "2026-11-12", steps: 4500 }, { day: "2026-11-13", steps: 100 }]);
    // Someone who joined after the close doesn't change that day.
    await sync(late, [{ day: "2026-11-12", steps: 9000 }]);

    const snap = await t.run((ctx) =>
      ctx.db.query("familyDays").withIndex("by_family_day", (q) => q.eq("familyId", familyId).eq("day", "2026-11-12")).unique(),
    );
    expect(snap).toMatchObject({ goal: 10000, total: 10500, hit: true });
    const week = await organiser.as.query(api.home.familyWeek, { familyId });
    expect(week.days.find((d) => d.day === "2026-11-12")).toMatchObject({ total: 10500, hit: true });
    expect(week.days.find((d) => d.day === "2026-11-13")).toMatchObject({ total: 100, isFuture: false });

    // Lowering a closed day's value lowers the total too.
    await sync(members[1]!, [{ day: "2026-11-12", steps: 2000 }]);
    const lowered = await t.run((ctx) => ctx.db.get(snap!._id));
    expect(lowered).toMatchObject({ total: 8000, hit: false });
  });

  test("closeDay snapshots every family", async () => {
    const one = await family(1, 1000);
    const two = await family(1, 1000);
    await sync(one.organiser, [{ day: "2026-11-14", steps: 1500 }]);
    vi.setSystemTime(new Date("2026-11-14T18:15:00Z"));
    expect(await t.mutation(internal.days.closeDay, {})).toEqual({ day: "2026-11-14", closed: 2 });
    const snaps = await t.run((ctx) => ctx.db.query("familyDays").collect());
    const byFamily = Object.fromEntries(snaps.map((s) => [s.familyId, [s.total, s.hit]]));
    expect(byFamily[one.familyId]).toEqual([1500, true]);
    expect(byFamily[two.familyId]).toEqual([0, false]);
  });
});

describe("closed days when a member goes", () => {
  const DAY = "2026-11-12";
  const snapOf = (familyId: Id<"families">) =>
    t.run((ctx) =>
      ctx.db.query("familyDays").withIndex("by_family_day", (q) => q.eq("familyId", familyId).eq("day", DAY)).unique(),
    );
  const contributionsOf = (userId: Id<"users">) =>
    t.run((ctx) => ctx.db.query("dayContributions").withIndex("by_user_day", (q) => q.eq("userId", userId)).collect());

  /** Family of 3 with goal 10,000: organiser 6,000, B 5,000, C unsynced; B also in a second family. Day closed. */
  async function closedDay() {
    setNow("2026-11-12T06:00:00Z");
    const f = await family(3, 10000);
    const [a, b, c] = f.members as [User, User, User];
    const other = await makeUser(t, "Other organiser");
    const second = await other.as.mutation(api.families.createFamily, { name: "Second", dailyGoal: 4000 });
    await b.as.mutation(api.families.joinFamily, { code: second.inviteCode });
    await sync(a, [{ day: DAY, steps: 6000 }]);
    await sync(b, [{ day: DAY, steps: 5000 }]);
    vi.setSystemTime(new Date("2026-11-12T18:15:00Z"));
    await t.mutation(internal.days.closeDay, {});
    vi.setSystemTime(new Date("2026-11-13T06:00:00Z"));
    return { ...f, a, b, c, secondId: second.familyId as Id<"families"> };
  }

  test("the close records every member's contribution, 0 for the unsynced", async () => {
    const { familyId, a, b, c } = await closedDay();
    expect(await snapOf(familyId)).toMatchObject({ total: 11000, goal: 10000, hit: true });
    const rows = await t.run((ctx) =>
      ctx.db.query("dayContributions").withIndex("by_family_day", (q) => q.eq("familyId", familyId).eq("day", DAY)).collect(),
    );
    expect(Object.fromEntries(rows.map((r) => [r.userId, r.steps]))).toEqual({ [a.id]: 6000, [b.id]: 5000, [c.id]: 0 });
    // The unsynced member's late sync still counts.
    await sync(c, [{ day: DAY, steps: 3000 }]);
    expect(await snapOf(familyId)).toMatchObject({ total: 14000, hit: true });
  });

  test("leaving strips the member's steps from closed days there only; the goal stays frozen", async () => {
    const { familyId, organiser, b, secondId } = await closedDay();
    await organiser.as.mutation(api.families.updateFamily, { familyId, dailyGoal: 5000 });
    await b.as.mutation(api.families.leaveFamily, { familyId });

    // 6,000 would be a hit at the new 5,000 goal, but the day keeps its 10,000 goal.
    expect(await snapOf(familyId)).toMatchObject({ total: 6000, goal: 10000, hit: false });
    const week = await organiser.as.query(api.home.familyWeek, { familyId });
    expect(week.days.find((d) => d.day === DAY)).toMatchObject({ total: 6000, goal: 10000, hit: false });
    // Still counted in the family they stayed in.
    expect(await snapOf(secondId)).toMatchObject({ total: 5000, goal: 4000, hit: true });
    expect((await contributionsOf(b.id)).map((r) => r.familyId)).toEqual([secondId]);

    // A late sync afterwards doesn't touch the family they left.
    await sync(b, [{ day: DAY, steps: 9000 }]);
    expect(await snapOf(familyId)).toMatchObject({ total: 6000, hit: false });
    expect(await snapOf(secondId)).toMatchObject({ total: 9000, hit: true });
  });

  test("being removed strips them the same way", async () => {
    const { familyId, organiser, b, secondId } = await closedDay();
    await organiser.as.mutation(api.families.removeMember, { familyId, userId: b.id });
    expect(await snapOf(familyId)).toMatchObject({ total: 6000, goal: 10000, hit: false });
    expect(await snapOf(secondId)).toMatchObject({ total: 5000, hit: true });
  });

  test("deleting the account strips them from every family's closed days", async () => {
    const { familyId, b, secondId } = await closedDay();
    expect(await b.as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "skipped" });
    expect(await snapOf(familyId)).toMatchObject({ total: 6000, hit: false });
    expect(await snapOf(secondId)).toMatchObject({ total: 0, goal: 4000, hit: false });
    expect(await contributionsOf(b.id)).toEqual([]);
  });

  test("deleting the sole contributor's account leaves no trace of their steps", async () => {
    setNow("2026-11-12T06:00:00Z");
    const { familyId, organiser, members } = await family(2, 10000);
    await sync(organiser, [{ day: DAY, steps: 12000 }]);
    vi.setSystemTime(new Date("2026-11-12T18:15:00Z"));
    await t.mutation(internal.days.closeDay, {});
    vi.setSystemTime(new Date("2026-11-13T06:00:00Z"));

    await organiser.as.action(api.users.deleteMyAccount, {});
    const week = await members[1]!.as.query(api.home.familyWeek, { familyId });
    expect(week.days.find((d) => d.day === DAY)).toMatchObject({ total: 0, goal: 10000, hit: false });
  });

  test("the last member going deletes the family's contributions with it", async () => {
    const { familyId, a, b, c } = await closedDay();
    for (const m of [b, c, a]) await m.as.mutation(api.families.leaveFamily, { familyId });
    const rows = await t.run((ctx) =>
      ctx.db.query("dayContributions").withIndex("by_family_day", (q) => q.eq("familyId", familyId)).collect(),
    );
    expect(rows).toEqual([]);
    expect(await snapOf(familyId)).toBeNull();
  });
});
