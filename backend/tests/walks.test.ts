import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { WALK_DURATION_MS } from "../convex/lib/constants";
import { expectCode, makeUser, newTest, T, User } from "./helpers";

const H = 60 * 60 * 1000;
let t: T;
beforeEach(() => {
  t = newTest();
  // Date and timers faked together so scheduled autoStops can be run.
  vi.useFakeTimers({ toFake: ["Date", "setTimeout", "clearTimeout"] });
  vi.setSystemTime(new Date("2026-11-14T06:00:00Z")); // 11:45 Sat 14 Nov in Nepal
});
afterEach(() => vi.useRealTimers());

const start = (u: User) => u.as.mutation(api.walks.startWalk, {});
const stop = (u: User) => u.as.mutation(api.walks.stopWalk, {});
const walksOf = (userId: Id<"users">) =>
  t.run((ctx) => ctx.db.query("walks").filter((q) => q.eq(q.field("userId"), userId)).collect());

async function familyOf(...users: User[]) {
  const f = await users[0]!.as.mutation(api.families.createFamily, { name: "Family" });
  for (const u of users.slice(1)) await u.as.mutation(api.families.joinFamily, { code: f.inviteCode });
  return f.familyId as Id<"families">;
}
async function memberView(viewer: User, familyId: Id<"families">, userId: Id<"users">) {
  const today = await viewer.as.query(api.home.familyToday, { familyId });
  return today.members.find((m) => m.userId === userId)!;
}

describe("startWalk", () => {
  test("returns a 2 h walk", async () => {
    const u = await makeUser(t);
    const now = Date.now();
    const w = await start(u);
    expect(w.startedAt).toBe(now);
    expect(w.endsAt).toBe(now + 2 * H);
    expect(WALK_DURATION_MS).toBe(2 * H);
  });

  test("already_walking while a walk is open", async () => {
    const u = await makeUser(t);
    await start(u);
    vi.setSystemTime(Date.now() + H);
    await expectCode(start(u), "already_walking");
    expect(await walksOf(u.id)).toHaveLength(1);
  });

  test("3 starts per Nepal day, counted again after Nepal midnight", async () => {
    const u = await makeUser(t);
    vi.setSystemTime(new Date("2026-11-14T12:00:00Z")); // 17:45 Nepal, 14 Nov
    for (let i = 0; i < 3; i++) {
      await start(u);
      await stop(u);
    }
    await expectCode(start(u), "walk_limit_reached");
    vi.setSystemTime(new Date("2026-11-14T18:14:59Z")); // 23:59:59 Nepal, still 14 Nov
    await expectCode(start(u), "walk_limit_reached");
    vi.setSystemTime(new Date("2026-11-14T18:15:00Z")); // Nepal midnight: 15 Nov
    const w = await start(u);
    const rows = await walksOf(u.id);
    expect(rows.find((r) => r._id === w.walkId)!.nepalDay).toBe("2026-11-15");
    expect(rows.filter((r) => r.nepalDay === "2026-11-14")).toHaveLength(3);
  });

  test("a walk counts toward the day it started, even when it crosses midnight", async () => {
    const u = await makeUser(t);
    vi.setSystemTime(new Date("2026-11-14T17:00:00Z")); // 22:45 Nepal, 14 Nov
    await start(u);
    vi.setSystemTime(new Date("2026-11-14T18:30:00Z")); // 00:15 Nepal, 15 Nov, still walking
    await expectCode(start(u), "already_walking");
    await stop(u);
    for (let i = 0; i < 3; i++) {
      await start(u);
      await stop(u);
    }
    await expectCode(start(u), "walk_limit_reached");
  });

  test("a walk past endsAt whose autoStop hasn't run doesn't block a new one", async () => {
    const u = await makeUser(t);
    const first = await start(u);
    vi.setSystemTime(first.endsAt + 1); // timers not advanced, so autoStop hasn't run
    await start(u);
    const rows = await walksOf(u.id);
    expect(rows.find((r) => r._id === first.walkId)!.endedAt).toBe(first.endsAt);
  });

  test("not_authenticated without a session", async () => {
    await expectCode(t.mutation(api.walks.startWalk, {}), "not_authenticated");
  });
});

describe("stopWalk", () => {
  test("ends the open walk", async () => {
    const u = await makeUser(t);
    await start(u);
    vi.setSystemTime(Date.now() + 30 * 60 * 1000);
    expect(await stop(u)).toBeNull();
    const [row] = await walksOf(u.id);
    expect(row!.endedAt).toBe(Date.now());
  });

  test("is a no-op when not walking", async () => {
    const u = await makeUser(t);
    expect(await stop(u)).toBeNull();
    await start(u);
    await stop(u);
    const before = await walksOf(u.id);
    vi.setSystemTime(Date.now() + 1000);
    expect(await stop(u)).toBeNull();
    expect(await walksOf(u.id)).toEqual(before);
  });
});

describe("autoStop", () => {
  test("ends an open walk at 2 h", async () => {
    const u = await makeUser(t);
    const w = await start(u);
    vi.advanceTimersByTime(2 * H - 1);
    await t.finishInProgressScheduledFunctions();
    expect((await walksOf(u.id))[0]!.endedAt).toBeUndefined();
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await walksOf(u.id))[0]!.endedAt).toBe(w.endsAt);
  });

  test("is idempotent and leaves a stopped walk alone", async () => {
    const u = await makeUser(t);
    const w = await start(u);
    vi.setSystemTime(Date.now() + H);
    await stop(u);
    const stoppedAt = Date.now();
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await walksOf(u.id))[0]!.endedAt).toBe(stoppedAt);
    await t.mutation(internal.walks.autoStop, { walkId: w.walkId });
    await t.mutation(internal.walks.autoStop, { walkId: w.walkId });
    expect((await walksOf(u.id))[0]!.endedAt).toBe(stoppedAt);
  });

  test("does nothing for a walk deleted with its account", async () => {
    const u = await makeUser(t);
    await start(u);
    await t.mutation(internal.users.deleteAccountData, { userId: u.id });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await walksOf(u.id)).toHaveLength(0);
  });
});

describe("familyToday walking", () => {
  test("shows walkingSince and walkEndsAt in every family, then null", async () => {
    const walker = await makeUser(t, "Walker");
    const a = await makeUser(t, "A");
    const b = await makeUser(t, "B");
    const famA = await familyOf(a, walker);
    const famB = await familyOf(b, walker);

    expect(await memberView(a, famA, walker.id)).toMatchObject({ walkingSince: null, walkEndsAt: null });
    const w = await start(walker);
    expect(await memberView(a, famA, walker.id)).toMatchObject({ walkingSince: w.startedAt, walkEndsAt: w.endsAt });
    expect(await memberView(b, famB, walker.id)).toMatchObject({ walkingSince: w.startedAt, walkEndsAt: w.endsAt });
    expect(await memberView(a, famA, a.id)).toMatchObject({ walkingSince: null, walkEndsAt: null });

    // Past endsAt but before autoStop runs: already not walking.
    vi.setSystemTime(w.endsAt);
    expect(await memberView(a, famA, walker.id)).toMatchObject({ walkingSince: null, walkEndsAt: null });
  });

  test("null after stopWalk", async () => {
    const walker = await makeUser(t, "Walker");
    const a = await makeUser(t, "A");
    const fam = await familyOf(a, walker);
    await start(walker);
    await stop(walker);
    expect(await memberView(a, fam, walker.id)).toMatchObject({ walkingSince: null, walkEndsAt: null });
  });
});
