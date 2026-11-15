import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { expectCode, makeUser, newTest, T, User } from "./helpers";

const H = 60 * 60 * 1000;
const D = 24 * H;
const TODAY = "2026-11-14";
let t: T;
beforeEach(() => {
  t = newTest();
  vi.useFakeTimers({ toFake: ["Date", "setTimeout", "clearTimeout"] });
  vi.setSystemTime(new Date("2026-11-14T06:00:00Z")); // 11:45 Sat 14 Nov in Nepal
});
afterEach(() => vi.useRealTimers());

const sync = (u: User, steps: number, day = TODAY) =>
  u.as.mutation(api.steps.syncSteps, { days: [{ day, steps }] });
const feedOf = (u: User, familyId: Id<"families">) => u.as.query(api.feed.feed, { familyId });
const react = (u: User, eventId: string, emoji: string) =>
  u.as.mutation(api.feed.react, { eventId, emoji });
const allEvents = () => t.run((ctx) => ctx.db.query("feedEvents").collect());
const allReactions = () => t.run((ctx) => ctx.db.query("reactions").collect());

async function familyOf(goal: number, ...users: User[]) {
  const f = await users[0]!.as.mutation(api.families.createFamily, { name: "Family", dailyGoal: goal });
  for (const u of users.slice(1)) await u.as.mutation(api.families.joinFamily, { code: f.inviteCode });
  return f.familyId as Id<"families">;
}
async function insertEvent(familyId: Id<"families">, actorId: Id<"users"> | undefined, day: string, createdAt: number) {
  return await t.run((ctx) =>
    ctx.db.insert("feedEvents", {
      familyId,
      type: "member_5k",
      ...(actorId ? { actorId } : {}),
      day,
      createdAt,
      data: {},
    }),
  );
}

describe("step events", () => {
  test("member_5k and member_10k once each, in every family of the member", async () => {
    const a = await makeUser(t, "Asha");
    const b = await makeUser(t);
    const f1 = await familyOf(1_000_000, a, b);
    const f2 = await familyOf(1_000_000, a);
    await sync(a, 4_999);
    expect(await allEvents()).toHaveLength(0);
    await sync(a, 5_000);
    await sync(a, 12_000);
    // Down and back up across the same thresholds: no duplicates.
    await sync(a, 3_000);
    await sync(a, 11_000);
    for (const f of [f1, f2]) {
      const feed = await feedOf(a, f);
      expect(feed.map((e) => e.type).sort()).toEqual(["member_10k", "member_5k"]);
      expect(feed[0]!.actor).toEqual({
        userId: a.id,
        name: "Asha",
        avatarColor: "#E4572E",
        photoUrl: null,
        city: null,
        timezone: null,
      });
    }
    expect(await allEvents()).toHaveLength(4);
  });

  test("one sync crossing both thresholds posts both", async () => {
    const a = await makeUser(t);
    const f = await familyOf(1_000_000, a);
    await sync(a, 10_000);
    expect((await feedOf(a, f)).map((e) => e.type).sort()).toEqual(["member_10k", "member_5k"]);
  });

  test("family_50 and family_100 with a null actor, once each", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    const f = await familyOf(10_000, a, b);
    await sync(a, 4_000);
    expect(await allEvents()).toHaveLength(0);
    await sync(b, 1_000); // total 5,000 = 50%
    let feed = await feedOf(a, f);
    expect(feed.map((e) => e.type)).toEqual(["family_50"]);
    expect(feed[0]!.actor).toBeNull();
    await sync(b, 6_000); // total 10,000 = 100%, and b crosses 5k
    await sync(b, 0);
    await sync(b, 7_000); // crosses 100% again
    feed = await feedOf(a, f);
    expect(feed.filter((e) => e.type.startsWith("family_")).map((e) => e.type).sort()).toEqual([
      "family_100",
      "family_50",
    ]);
    expect(feed.find((e) => e.type === "family_100")!.actor).toBeNull();
  });

  test("late syncs for closed days create no events", async () => {
    const a = await makeUser(t);
    await familyOf(1_000, a);
    vi.setSystemTime(new Date("2026-11-14T18:15:00Z")); // Nepal midnight: 15 Nov
    await t.mutation(internal.days.closeDay, {});
    await sync(a, 20_000, TODAY);
    expect(await allEvents()).toHaveLength(0);
  });
});

describe("walk_started", () => {
  test("one per walk per family with data.walkId: 3 walks give 3 events each", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    const f1 = await familyOf(50_000, a, b);
    const f2 = await familyOf(50_000, a);
    const w = await a.as.mutation(api.walks.startWalk, {});
    for (const f of [f1, f2]) {
      const feed = await feedOf(a, f);
      expect(feed).toHaveLength(1);
      expect(feed[0]).toMatchObject({ type: "walk_started", data: { walkId: w.walkId }, day: TODAY });
    }
    const walkIds = [w.walkId];
    for (let i = 0; i < 2; i++) {
      await a.as.mutation(api.walks.stopWalk, {});
      walkIds.push((await a.as.mutation(api.walks.startWalk, {})).walkId);
    }
    for (const f of [f1, f2]) {
      const feed = await feedOf(a, f);
      expect(feed.map((e) => e.data.walkId).sort()).toEqual([...walkIds].sort());
    }
    expect(await allEvents()).toHaveLength(6);
  });
});

describe("feed", () => {
  test("last 3 Nepal days, newest first, at most 100", async () => {
    const a = await makeUser(t);
    const f = await familyOf(50_000, a);
    const now = Date.now();
    await insertEvent(f, a.id, "2026-11-11", now - 3 * D); // outside window
    const d2 = await insertEvent(f, a.id, "2026-11-12", now - 2 * D);
    const d1 = await insertEvent(f, a.id, "2026-11-13", now - D);
    const d0 = await insertEvent(f, undefined, TODAY, now);
    expect((await feedOf(a, f)).map((e) => e.id)).toEqual([d0, d1, d2]);

    for (let i = 0; i < 120; i++) await insertEvent(f, a.id, TODAY, now + 1 + i);
    const feed = await feedOf(a, f);
    expect(feed).toHaveLength(100);
    expect(feed[0]!.createdAt).toBe(now + 120);
    for (let i = 1; i < feed.length; i++) expect(feed[i - 1]!.createdAt).toBeGreaterThan(feed[i]!.createdAt);
  });

  test("not_member for outsiders", async () => {
    const a = await makeUser(t);
    const out = await makeUser(t);
    const f = await familyOf(50_000, a);
    await expectCode(feedOf(out, f), "not_member");
  });

  test("reaction counts in fixed emoji order and myReaction", async () => {
    const [a, b, c] = [await makeUser(t), await makeUser(t), await makeUser(t)];
    const f = await familyOf(50_000, a, b, c);
    const e = await insertEvent(f, a.id, TODAY, Date.now());
    await react(a, e, "😄");
    await react(b, e, "👏");
    await react(c, e, "😄");
    const [ev] = await feedOf(b, f);
    expect(ev!.reactions).toEqual([
      { emoji: "👏", count: 1 },
      { emoji: "😄", count: 2 },
    ]);
    expect(ev!.myReaction).toBe("👏");
    expect((await feedOf(a, f))[0]!.myReaction).toBe("😄");
  });
});

describe("react", () => {
  test("add, replace, remove", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    const f = await familyOf(50_000, a, b);
    const e = await insertEvent(f, a.id, TODAY, Date.now());
    expect(await react(b, e, "👏")).toEqual({ myReaction: "👏" });
    expect(await react(b, e, "🔥")).toEqual({ myReaction: "🔥" });
    expect(await allReactions()).toHaveLength(1);
    expect(await react(b, e, "🔥")).toEqual({ myReaction: null });
    expect(await allReactions()).toHaveLength(0);
  });

  test("❤ without VS16 is stored as ❤️ and toggles against it", async () => {
    const a = await makeUser(t);
    const f = await familyOf(50_000, a);
    const e = await insertEvent(f, a.id, TODAY, Date.now());
    expect(await react(a, e, "❤")).toEqual({ myReaction: "❤️" });
    expect((await allReactions())[0]!.emoji).toBe("❤️");
    expect(await react(a, e, "❤️")).toEqual({ myReaction: null });
  });

  test("invalid_emoji", async () => {
    const a = await makeUser(t);
    const f = await familyOf(50_000, a);
    const e = await insertEvent(f, a.id, TODAY, Date.now());
    for (const bad of ["👍", "", "👏👏", "x"]) await expectCode(react(a, e, bad), "invalid_emoji");
  });

  test("not_member: outsider, missing event, bad id, outside the feed window", async () => {
    const a = await makeUser(t);
    const out = await makeUser(t);
    const f = await familyOf(50_000, a);
    const e = await insertEvent(f, a.id, TODAY, Date.now());
    await expectCode(react(out, e, "👏"), "not_member");
    const old = await insertEvent(f, a.id, "2026-11-11", Date.now() - 3 * D);
    await expectCode(react(a, old, "👏"), "not_member");
    await t.run((ctx) => ctx.db.delete(e));
    await expectCode(react(a, e, "👏"), "not_member");
    await expectCode(react(a, "nonsense", "👏"), "not_member");
  });
});

describe("cleanup", () => {
  async function setup() {
    const [a, b, c] = [await makeUser(t), await makeUser(t), await makeUser(t)];
    const f = await familyOf(50_000, a, b, c);
    const g = await familyOf(50_000, b, c);
    const now = Date.now();
    const bInF = await insertEvent(f, b.id, TODAY, now);
    const aInF = await insertEvent(f, a.id, TODAY, now + 1);
    const bInG = await insertEvent(g, b.id, TODAY, now + 2);
    const cInG = await insertEvent(g, c.id, TODAY, now + 3);
    await react(a, bInF, "👏"); // others' reaction to b's event
    await react(b, aInF, "🔥"); // b's reaction in f
    await react(b, cInG, "😄"); // b's reaction in g
    await react(c, bInG, "🙌");
    return { a, b, c, f, g, bInF, aInF, bInG, cInG };
  }

  test("leaving deletes the member's events and reactions in that family only", async () => {
    const s = await setup();
    await s.b.as.mutation(api.families.leaveFamily, { familyId: s.f });
    const events = (await allEvents()).map((e) => e._id).sort();
    expect(events).toEqual([s.aInF, s.bInG, s.cInG].sort());
    const reactions = await allReactions();
    expect(reactions.map((r) => [r.userId, r.eventId])).toEqual(
      expect.arrayContaining([
        [s.b.id, s.cInG],
        [s.c.id, s.bInG],
      ]),
    );
    expect(reactions).toHaveLength(2);
  });

  test("removal by the organiser does the same", async () => {
    const s = await setup();
    await s.a.as.mutation(api.families.removeMember, { familyId: s.f, userId: s.b.id });
    expect((await allEvents()).some((e) => e._id === s.bInF)).toBe(false);
    expect((await allReactions()).some((r) => r.eventId === s.aInF)).toBe(false);
    expect(await allReactions()).toHaveLength(2);
  });

  test("account deletion deletes all their events and reactions", async () => {
    const s = await setup();
    await t.mutation(internal.users.deleteAccountData, { userId: s.b.id });
    expect((await allEvents()).map((e) => e._id).sort()).toEqual([s.aInF, s.cInG].sort());
    expect(await allReactions()).toHaveLength(0);
  });

  test("an emptied family loses its events and reactions", async () => {
    const a = await makeUser(t);
    const f = await familyOf(50_000, a);
    const e = await insertEvent(f, undefined, TODAY, Date.now());
    await react(a, e, "👏");
    await a.as.mutation(api.families.leaveFamily, { familyId: f });
    expect(await allEvents()).toHaveLength(0);
    expect(await allReactions()).toHaveLength(0);
  });
});

describe("purgeOld", () => {
  test("deletes events older than 7 days with their reactions", async () => {
    const a = await makeUser(t);
    const f = await familyOf(50_000, a);
    const now = Date.now();
    const old = await insertEvent(f, a.id, "2026-11-07", now - 7 * D - 1);
    const kept = await insertEvent(f, a.id, "2026-11-07", now - 7 * D + 1);
    await t.run((ctx) => ctx.db.insert("reactions", { eventId: old, userId: a.id, emoji: "👏" }));
    await t.run((ctx) => ctx.db.insert("reactions", { eventId: kept, userId: a.id, emoji: "👏" }));
    expect(await t.mutation(internal.feed.purgeOld, {})).toEqual({ deleted: 1 });
    expect((await allEvents()).map((e) => e._id)).toEqual([kept]);
    expect((await allReactions()).map((r) => r.eventId)).toEqual([kept]);
  });

  test("works through more than one batch", async () => {
    const a = await makeUser(t);
    const f = await familyOf(50_000, a);
    const now = Date.now();
    for (let i = 0; i < 250; i++) await insertEvent(f, a.id, "2026-11-01", now - 10 * D + i);
    await t.mutation(internal.feed.purgeOld, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await allEvents()).toHaveLength(0);
  });
});
