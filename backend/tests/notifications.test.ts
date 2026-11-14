import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { makeUser, newTest, T, User } from "./helpers";

/**
 * Who gets which push. These tests read the queued `pushNode.send` jobs
 * rather than running them; delivery itself is covered in push.test.ts.
 */

const MIN = 60 * 1000;
const TODAY = "2026-11-14";
let t: T;
beforeEach(() => {
  t = newTest();
  vi.useFakeTimers({ toFake: ["Date", "setTimeout", "clearTimeout"] });
  vi.setSystemTime(new Date("2026-11-14T06:00:00Z")); // 11:45 Sat 14 Nov in Nepal
});
afterEach(() => vi.useRealTimers());

type Queued = {
  userIds: Id<"users">[];
  alert: { title: string; body: string };
  data: { type: string; familyId: Id<"families">; eventId?: Id<"feedEvents"> };
};
async function queuedPushes(): Promise<Queued[]> {
  return await t.run(async (ctx) => {
    const jobs = await ctx.db.system.query("_scheduled_functions").collect();
    return jobs.filter((j) => j.name.startsWith("pushNode")).map((j) => j.args[0] as Queued);
  });
}
/** Runs queued jobs that are due (convex-test puts runAfter(0) 1 ms out). */
async function runDueJobs() {
  await t.finishAllScheduledFunctions(() => vi.advanceTimersByTime(1));
}
/** Moves only the clock: queued jobs stay queued, so they can be inspected. */
function jump(ms: number) {
  vi.setSystemTime(Date.now() + ms);
}
const recipients = (pushes: Queued[]) => pushes.flatMap((p) => p.userIds).sort();
const ids = (...users: User[]) => users.map((u) => u.id).sort();

async function familyOf(goal: number, ...users: User[]) {
  const f = await users[0]!.as.mutation(api.families.createFamily, { name: "Sharma Family", dailyGoal: goal });
  for (const u of users.slice(1)) await u.as.mutation(api.families.joinFamily, { code: f.inviteCode });
  return f.familyId as Id<"families">;
}
const setPrefs = (u: User, prefs: Record<string, boolean>) =>
  u.as.mutation(api.notifications.setNotificationPrefs, prefs);
const sync = (u: User, steps: number) =>
  u.as.mutation(api.steps.syncSteps, { days: [{ day: TODAY, steps }] });

describe("notification prefs", () => {
  test("defaults: walks, goals and reactions on, evening nudge off", async () => {
    const a = await makeUser(t);
    expect(await a.as.query(api.notifications.notificationPrefs, {})).toEqual({
      walkStarted: true,
      goalHit: true,
      reactions: true,
      eveningNudge: false,
    });
  });

  test("partial updates change only what's sent", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    expect(await setPrefs(a, { eveningNudge: true })).toEqual({
      walkStarted: true,
      goalHit: true,
      reactions: true,
      eveningNudge: true,
    });
    await setPrefs(a, { reactions: false });
    await setPrefs(a, {});
    expect(await a.as.query(api.notifications.notificationPrefs, {})).toEqual({
      walkStarted: true,
      goalHit: true,
      reactions: false,
      eveningNudge: true,
    });
    // Someone else's prefs are untouched.
    expect((await b.as.query(api.notifications.notificationPrefs, {})).reactions).toBe(true);
    expect(await t.run((ctx) => ctx.db.query("notificationPrefs").collect())).toHaveLength(1);
  });
});

describe("walk started push", () => {
  test("everyone in the walker's families once, minus the walker and anyone muted", async () => {
    const [walker, b, c, d, muted] = await Promise.all(
      ["Aama", "B", "C", "D", "Muted"].map((n) => makeUser(t, n)),
    );
    const f1 = await familyOf(50_000, walker!, b!, c!);
    const f2 = await familyOf(50_000, walker!, b!, d!, muted!);
    await setPrefs(muted!, { walkStarted: false });

    await walker!.as.mutation(api.walks.startWalk, {});
    const pushes = await queuedPushes();
    // b shares both families but gets one push.
    expect(recipients(pushes)).toEqual(ids(b!, c!, d!));
    for (const p of pushes) {
      expect(p.alert).toEqual({ title: "Aama started a walk", body: "Want to join? Give them a call." });
      expect(p.data.type).toBe("walk_started");
      const event = await t.run((ctx) => ctx.db.get(p.data.eventId!));
      expect(event).toMatchObject({ type: "walk_started", familyId: p.data.familyId });
    }
    // b routes to the first shared family.
    expect(pushes.find((p) => p.userIds.includes(b!.id))!.data.familyId).toBe(f1);
    expect(pushes.find((p) => p.userIds.includes(d!.id))!.data.familyId).toBe(f2);
  });

  test("a push and an event per walk: 3 walks give 3 of each", async () => {
    const a = await makeUser(t, "Aama");
    const b = await makeUser(t);
    await familyOf(50_000, a, b);
    for (let i = 0; i < 3; i++) {
      await a.as.mutation(api.walks.startWalk, {});
      await a.as.mutation(api.walks.stopWalk, {});
    }
    expect(await queuedPushes()).toHaveLength(3);
    const events = await t.run((ctx) => ctx.db.query("feedEvents").collect());
    expect(events.filter((e) => e.type === "walk_started")).toHaveLength(3);
    expect(new Set(events.map((e) => e.data.walkId)).size).toBe(3);
  });

  test("no push when the walker is alone, and a nameless walker reads warmly", async () => {
    const solo = await makeUser(t);
    await familyOf(50_000, solo);
    await solo.as.mutation(api.walks.startWalk, {});
    expect(await queuedPushes()).toHaveLength(0);

    const nameless = await makeUser(t, null);
    const b = await makeUser(t);
    await familyOf(50_000, nameless, b);
    await nameless.as.mutation(api.walks.startWalk, {});
    expect((await queuedPushes())[0]!.alert.title).toBe("Someone in your family started a walk");
  });
});

describe("goal hit push", () => {
  test("family_100 pushes every member who hasn't muted it, once", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    const muted = await makeUser(t);
    const f = await familyOf(10_000, a, b, muted);
    await setPrefs(muted, { goalHit: false });

    await sync(a, 6_000); // family_50: no push
    expect(await queuedPushes()).toHaveLength(0);
    await sync(b, 4_000); // 10,000: family_100
    const pushes = await queuedPushes();
    expect(pushes).toHaveLength(1);
    expect(recipients(pushes)).toEqual(ids(a, b));
    const event = await t.run((ctx) => ctx.db.get(pushes[0]!.data.eventId!));
    expect(event).toMatchObject({ type: "family_100", familyId: f });
    expect(pushes[0]!.data).toMatchObject({ type: "family_100", familyId: f });
    expect(pushes[0]!.alert.title).toBe("Sharma Family reached today's goal");

    await sync(a, 9_000); // already hit today
    expect(await queuedPushes()).toHaveLength(1);
  });
});

describe("reaction push", () => {
  async function setup() {
    const a = await makeUser(t, "Aama");
    const b = await makeUser(t, "Buwa");
    const c = await makeUser(t, "Didi");
    const f = await familyOf(50_000, a, b, c);
    await sync(a, 5_000);
    const event = (await t.run((ctx) => ctx.db.query("feedEvents").collect())).find(
      (e) => e.type === "member_5k",
    )!;
    return { a, b, c, f, eventId: event._id };
  }
  const react = (u: User, eventId: string, emoji: string) =>
    u.as.mutation(api.feed.react, { eventId, emoji });

  test("goes to the event's actor with the reactor's name and emoji", async () => {
    const { a, b, f, eventId } = await setup();
    await react(b, eventId, "👏");
    const pushes = await queuedPushes();
    expect(pushes).toHaveLength(1);
    expect(pushes[0]).toEqual({
      userIds: [a.id],
      alert: { title: "Buwa reacted 👏 to your 5,000 steps", body: "In Sharma Family." },
      data: { type: "reaction", familyId: f, eventId },
    });
  });

  test("not for your own reaction, nor when the actor muted reactions", async () => {
    const { a, b, eventId } = await setup();
    await react(a, eventId, "🔥");
    expect(await queuedPushes()).toHaveLength(0);
    await setPrefs(a, { reactions: false });
    await react(b, eventId, "🔥");
    expect(await queuedPushes()).toHaveLength(0);
  });

  test("coalesced: at most one per event per 10 minutes", async () => {
    const { b, c, a, eventId } = await setup();
    await react(b, eventId, "👏");
    await react(c, eventId, "❤️"); // within 10 min
    await react(b, eventId, "🙌"); // replace, still within
    expect(await queuedPushes()).toHaveLength(1);
    const pushedAt = (await t.run((ctx) => ctx.db.get(eventId)))!.lastReactionPushAt!;
    vi.setSystemTime(pushedAt + 10 * MIN - 1);
    await react(c, eventId, "🔥");
    expect(await queuedPushes()).toHaveLength(1);
    vi.setSystemTime(pushedAt + 10 * MIN);
    await react(c, eventId, "😄");
    const pushes = await queuedPushes();
    expect(pushes).toHaveLength(2);
    expect(pushes[1]!.alert.title).toBe("Didi reacted 😄 to your 5,000 steps");
    expect(pushes[1]!.userIds).toEqual([a.id]);

    // Another event has its own window.
    await a.as.mutation(api.walks.startWalk, {});
    const walkEvent = (await t.run((ctx) => ctx.db.query("feedEvents").collect())).find(
      (e) => e.type === "walk_started",
    )!;
    const before = (await queuedPushes()).length;
    await react(b, walkEvent._id, "👏");
    const after = await queuedPushes();
    expect(after).toHaveLength(before + 1);
    expect(after.at(-1)!.alert.title).toBe("Buwa reacted 👏 to your walk");
  });

  test("removing a reaction and reacting to a family event push nothing", async () => {
    const { a, b, eventId } = await setup();
    await react(b, eventId, "👏");
    jump(11 * MIN);
    await react(b, eventId, "👏"); // toggles off
    expect(await queuedPushes()).toHaveLength(1);

    await sync(b, 20_000); // 25,000 of 50,000: family_50 (no actor)
    const fam = (await t.run((ctx) => ctx.db.query("feedEvents").collect())).find(
      (e) => e.type === "family_50",
    )!;
    await react(a, fam._id, "🔥");
    expect(await queuedPushes()).toHaveLength(1);
  });
});

describe("evening nudge", () => {
  const nudge = () => t.mutation(internal.notifications.eveningNudge, {});

  test("only under-goal families, only opted-in members, no names", async () => {
    vi.setSystemTime(new Date("2026-11-14T13:15:00Z")); // 19:00 Nepal
    const [a, b, c, d, e] = await Promise.all(
      ["Aama", "Buwa", "Didi", "Dai", "Bahini"].map((n) => makeUser(t, n)),
    );
    const under = await familyOf(10_000, a!, b!);
    await familyOf(10_000, c!, d!); // reaches its goal
    await familyOf(10_000, e!); // under, but nobody opted in
    for (const u of [a!, c!, d!]) await setPrefs(u, { eveningNudge: true });
    await sync(a!, 2_000);
    await sync(b!, 4_200);
    await sync(c!, 10_000);
    const before = (await queuedPushes()).length; // goal-hit push for c/d

    expect(await nudge()).toEqual({ nudged: 1 });
    const pushes = (await queuedPushes()).slice(before);
    expect(pushes).toHaveLength(1);
    expect(pushes[0]).toEqual({
      userIds: [a!.id],
      alert: {
        title: "An evening walk?",
        body: "Your family is at 62% today. A short evening walk would help everyone get there.",
      },
      data: { type: "evening_nudge", familyId: under },
    });
    for (const name of ["Aama", "Buwa", "Didi", "Dai", "Bahini"]) {
      expect(JSON.stringify(pushes[0]!.alert)).not.toContain(name);
    }
  });

  test("a family with no steps yet gets a gentle start, and percent never rounds up", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    await familyOf(10_000, a);
    await familyOf(10_000, b);
    await setPrefs(a, { eveningNudge: true });
    await setPrefs(b, { eveningNudge: true });
    await sync(b, 9_999);
    const before = (await queuedPushes()).length;
    await nudge();
    const bodies = (await queuedPushes()).slice(before).map((p) => p.alert.body);
    expect(bodies).toContain(
      "Your family hasn't logged steps yet today. A short evening walk would be a lovely start.",
    );
    expect(bodies).toContain(
      "Your family is at 99% today. A short evening walk would help everyone get there.",
    );
  });

  test("a person in several under-goal families gets one nudge, about the furthest from goal", async () => {
    const [a, b, c] = await Promise.all(["Aama", "Buwa", "Didi"].map((n) => makeUser(t, n)));
    const near = await familyOf(10_000, a!, b!); // 8,000 of 10,000: 80%
    const far = await familyOf(20_000, c!, a!); // 7,000 of 20,000: 35%
    for (const u of [a!, b!, c!]) await setPrefs(u, { eveningNudge: true });
    await sync(a!, 5_000);
    await sync(b!, 3_000);
    await sync(c!, 2_000);
    const before = (await queuedPushes()).length;

    expect(await nudge()).toEqual({ nudged: 3 });
    const pushes = (await queuedPushes()).slice(before);
    expect(recipients(pushes)).toEqual(ids(a!, b!, c!)); // each person once
    const familyFor = (u: User) => pushes.find((p) => p.userIds.includes(u.id))!.data.familyId;
    expect(familyFor(a!)).toBe(far);
    expect(familyFor(b!)).toBe(near);
    expect(familyFor(c!)).toBe(far);
    expect(pushes.find((p) => p.userIds.includes(a!.id))!.alert.body).toContain("35%");
  });

  test("ties on share of goal go to the family with more steps left", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    await familyOf(10_000, a);
    const bigger = await familyOf(20_000, a, b);
    await setPrefs(a, { eveningNudge: true });
    await sync(a, 2_500); // 25% of 10,000; with b, 5,000 = 25% of 20,000
    await sync(b, 2_500);
    const before = (await queuedPushes()).length;
    await nudge();
    const pushes = (await queuedPushes()).slice(before);
    expect(pushes).toHaveLength(1);
    expect(pushes[0]!.data.familyId).toBe(bigger);
  });

  test("one nudge per person even with more families than a page", async () => {
    const a = await makeUser(t);
    await setPrefs(a, { eveningNudge: true });
    await sync(a, 5_000);
    const families = await t.run(async (ctx) => {
      const out: Id<"families">[] = [];
      for (let i = 0; i < 130; i++) {
        const familyId = await ctx.db.insert("families", {
          name: `F${i}`,
          dailyGoal: 10_000 + i * 100,
          organiserId: a.id,
          inviteCode: `C${i}`,
          nextPosition: 1,
          createdAt: Date.now(),
        } as never);
        await ctx.db.insert("memberships", { familyId, userId: a.id, position: 0, joinedAt: Date.now() } as never);
        out.push(familyId);
      }
      return out;
    });
    expect(await nudge()).toEqual({ nudged: 1 });
    await runDueJobs();
    const pushes = (await queuedPushes()).filter((p) => p.data.type === "evening_nudge");
    expect(pushes).toHaveLength(1);
    expect(pushes[0]!.data.familyId).toBe(families[129]); // biggest goal, lowest share
  });

  test("pages through many people, each nudged once across pages, once per Nepal day", async () => {
    const people: User[] = [];
    for (let i = 0; i < 130; i++) people.push(await makeUser(t));
    // Two shared families, so members sit on both pages.
    const famA = await t.run(async (ctx) => {
      const mk = async (name: string, goal: number) =>
        await ctx.db.insert("families", {
          name,
          dailyGoal: goal,
          organiserId: people[0]!.id,
          inviteCode: name,
          nextPosition: 0,
          createdAt: Date.now(),
        } as never);
      const famA = await mk("A", 1_000_000);
      const famB = await mk("B", 2_000_000);
      for (const [i, u] of people.entries()) {
        await ctx.db.insert("memberships", { familyId: famA, userId: u.id, position: i, joinedAt: Date.now() } as never);
        if (i % 2 === 0) {
          await ctx.db.insert("memberships", { familyId: famB, userId: u.id, position: i, joinedAt: Date.now() } as never);
        }
      }
      return famA;
    });
    for (const u of people) await setPrefs(u, { eveningNudge: true });
    const nudges = async () => (await queuedPushes()).filter((p) => p.data.type === "evening_nudge");

    expect(await nudge()).toEqual({ nudged: 100 });
    await runDueJobs(); // the second page
    const first = await nudges();
    expect(recipients(first)).toEqual(ids(...people));
    // Odd people are only in A; even people are nudged about B (0% both, B has more left).
    expect(first.filter((p) => p.data.familyId === famA)).toHaveLength(65);

    // A second run the same Nepal day sends nothing.
    expect(await nudge()).toEqual({ nudged: 0 });
    await runDueJobs();
    expect(await nudges()).toHaveLength(130);

    // The next evening they're nudged again.
    vi.setSystemTime(new Date("2026-11-15T13:15:00Z"));
    expect(await nudge()).toEqual({ nudged: 100 });
  });
});

describe("account deletion", () => {
  test("removes the user's devices and prefs, nobody else's", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    await a.as.mutation(api.notifications.registerDevice, { apnsToken: "aa".repeat(32), environment: "production" });
    await b.as.mutation(api.notifications.registerDevice, { apnsToken: "bb".repeat(32), environment: "sandbox" });
    await setPrefs(a, { eveningNudge: true });
    await setPrefs(b, { eveningNudge: true });
    await t.mutation(internal.users.deleteAccountData, { userId: a.id });
    const devices = await t.run((ctx) => ctx.db.query("devices").collect());
    const prefs = await t.run((ctx) => ctx.db.query("notificationPrefs").collect());
    expect(devices.map((d) => d.userId)).toEqual([b.id]);
    expect(prefs.map((p) => p.userId)).toEqual([b.id]);
  });
});
