import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { addDays } from "../convex/lib/nepalDay";
import { expectCode, makeUser, newTest, setNow, T, User } from "./helpers";

let t: T;
beforeEach(() => {
  t = newTest();
  setNow("2026-11-09T03:00:00Z"); // Monday 9 Nov in Nepal (08:45)
});
afterEach(() => vi.useRealTimers());

async function family(n: number, dailyGoal = 10000) {
  const organiser = await makeUser(t, "Organiser");
  const f = await organiser.as.mutation(api.families.createFamily, { name: "Family", dailyGoal });
  const members: User[] = [organiser];
  for (let i = 1; i < n; i++) {
    const m = await makeUser(t, `Member ${i}`);
    await m.as.mutation(api.families.joinFamily, { code: f.inviteCode });
    members.push(m);
  }
  return { familyId: f.familyId as Id<"families">, members, organiser };
}

const sync = (u: User, days: { day: string; steps: number }[]) =>
  u.as.mutation(api.steps.syncSteps, { days });

describe("familyHistory", () => {
  test("returns 2N days oldest first ending today, for each range", async () => {
    const { familyId, organiser } = await family(1);
    for (const n of [7, 30, 90]) {
      const h = await organiser.as.query(api.home.familyHistory, { familyId, days: n });
      expect(h.today).toBe("2026-11-09");
      expect(h.days).toHaveLength(2 * n);
      expect(h.days[0]!.day).toBe(addDays("2026-11-09", -(2 * n - 1)));
      expect(h.days.at(-1)!.day).toBe("2026-11-09");
      for (let i = 1; i < h.days.length; i++) {
        expect(h.days[i]!.day).toBe(addDays(h.days[i - 1]!.day, 1));
      }
    }
  });

  test("closed days keep their frozen goal, today is live, days before the family are flagged", async () => {
    const { familyId, members, organiser } = await family(2, 10000);
    const [a, b] = [organiser, members[1]!];
    // Steps from before the family existed must not be totalled.
    await sync(a, [{ day: "2026-11-08", steps: 9999 }, { day: "2026-11-09", steps: 6000 }]);
    await sync(b, [{ day: "2026-11-09", steps: 5000 }]);

    vi.setSystemTime(new Date("2026-11-09T18:15:00Z")); // Nepal midnight → Tuesday
    await t.mutation(internal.days.closeDay, {});

    vi.setSystemTime(new Date("2026-11-10T18:15:00Z")); // Tuesday closes with no steps
    await t.mutation(internal.days.closeDay, {});

    vi.setSystemTime(new Date("2026-11-11T06:00:00Z")); // Wednesday
    await organiser.as.mutation(api.families.updateFamily, { familyId, dailyGoal: 7000 });
    await sync(a, [{ day: "2026-11-11", steps: 7500 }]);

    const h = await b.as.query(api.home.familyHistory, { familyId, days: 7 });
    expect(h.today).toBe("2026-11-11");
    expect(h.days).toHaveLength(14);
    expect(h.days.slice(-4)).toEqual([
      { day: "2026-11-08", total: 0, goal: 7000, hit: false, isBeforeFamily: true },
      { day: "2026-11-09", total: 11000, goal: 10000, hit: true, isBeforeFamily: false },
      { day: "2026-11-10", total: 0, goal: 10000, hit: false, isBeforeFamily: false },
      { day: "2026-11-11", total: 7500, goal: 7000, hit: true, isBeforeFamily: false },
    ]);
    expect(h.days.slice(0, -3).every((d) => d.isBeforeFamily && d.total === 0 && !d.hit)).toBe(true);

    // Same per-day numbers as familyWeek for the overlapping days.
    const week = await b.as.query(api.home.familyWeek, { familyId });
    for (const d of week.days.filter((w) => !w.isFuture && !w.isBeforeFamily)) {
      expect(h.days.find((x) => x.day === d.day)).toMatchObject({ total: d.total, goal: d.goal, hit: d.hit });
    }
  });

  test("a closed day with no snapshot falls back to the live total", async () => {
    const { familyId, organiser } = await family(1, 5000);
    await sync(organiser, [{ day: "2026-11-09", steps: 6000 }]);
    vi.setSystemTime(new Date("2026-11-10T06:00:00Z")); // Tuesday; Monday was never closed
    const h = await organiser.as.query(api.home.familyHistory, { familyId, days: 7 });
    expect(h.days.slice(-2)).toEqual([
      { day: "2026-11-09", total: 6000, goal: 5000, hit: true, isBeforeFamily: false },
      { day: "2026-11-10", total: 0, goal: 5000, hit: false, isBeforeFamily: false },
    ]);
  });

  test("rejects ranges other than 7, 30 or 90", async () => {
    const { familyId, organiser } = await family(1);
    for (const days of [5, 0, -7, 14, 7.5, 365]) {
      await expectCode(organiser.as.query(api.home.familyHistory, { familyId, days }), "invalid_day");
    }
  });

  test("outsiders get not_member", async () => {
    const { familyId } = await family(1);
    const outsider = await makeUser(t, "Outsider");
    await expectCode(outsider.as.query(api.home.familyHistory, { familyId, days: 7 }), "not_member");
  });
});
