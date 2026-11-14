import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { STATUS_PRESETS } from "../convex/lib/constants";
import { expectCode, makeUser, newTest, setNow, T, User } from "./helpers";

const H = 60 * 60 * 1000;
let t: T;
beforeEach(() => {
  t = newTest();
  setNow("2026-11-14T06:00:00Z");
});
afterEach(() => vi.useRealTimers());

type Args = { preset?: string; text?: string; expiresAt?: number };
const set = (u: User, args: Args) => u.as.mutation(api.status.setStatus, args);
const rowsOf = (userId: Id<"users">) =>
  t.run((ctx) => ctx.db.query("statuses").filter((q) => q.eq(q.field("userId"), userId)).collect());

describe("setStatus", () => {
  test("accepts every preset", async () => {
    const u = await makeUser(t);
    for (const preset of STATUS_PRESETS) {
      expect(await set(u, { preset })).toMatchObject({ preset, text: null });
    }
    expect(await rowsOf(u.id)).toHaveLength(1);
  });

  test("rejects an unknown preset", async () => {
    const u = await makeUser(t);
    await expectCode(set(u, { preset: "sleeping" }), "invalid_status");
    await expectCode(set(u, { preset: "At work" }), "invalid_status");
  });

  test("needs exactly one of preset and text", async () => {
    const u = await makeUser(t);
    await expectCode(set(u, {}), "invalid_status");
    await expectCode(set(u, { preset: "at_work", text: "hi" }), "invalid_status");
    await expectCode(set(u, { expiresAt: Date.now() + H }), "invalid_status");
    expect(await rowsOf(u.id)).toHaveLength(0);
  });

  test("text is trimmed and 1–30 UTF-16 units", async () => {
    const u = await makeUser(t);
    const thirty = "a".repeat(30);
    expect(await set(u, { text: `  ${thirty}  ` })).toMatchObject({ text: thirty, preset: null });
    await expectCode(set(u, { text: "a".repeat(31) }), "invalid_status");
    await expectCode(set(u, { text: "   " }), "invalid_status");
    await expectCode(set(u, { text: "" }), "invalid_status");
  });

  test("emoji count as UTF-16 code units", async () => {
    const u = await makeUser(t);
    expect("🏔️".length).toBe(3); // U+1F3D4 (2 units) + VS16 (1)
    const fifteenEmoji = "🚶".repeat(15); // 2 units each = 30
    expect(fifteenEmoji.length).toBe(30);
    expect(await set(u, { text: fifteenEmoji })).toMatchObject({ text: fifteenEmoji });
    await expectCode(set(u, { text: "🚶".repeat(15) + "a" }), "invalid_status");
    await expectCode(set(u, { text: "a".repeat(28) + "🏔️" }), "invalid_status"); // 31 units, 29 graphemes
  });

  test("expiresAt defaults to now + 24 h", async () => {
    const u = await makeUser(t);
    const s = await set(u, { preset: "resting" });
    expect(s.expiresAt).toBe(Date.now() + 24 * H);
    expect((await rowsOf(u.id))[0]!.expiresAt).toBe(Date.now() + 24 * H);
  });

  test("expiresAt must be in the future and at most 7 days out", async () => {
    const u = await makeUser(t);
    const now = Date.now();
    await expectCode(set(u, { preset: "at_home", expiresAt: now }), "invalid_expiry");
    await expectCode(set(u, { preset: "at_home", expiresAt: now - 1 }), "invalid_expiry");
    await expectCode(set(u, { preset: "at_home", expiresAt: now + 7 * 24 * H + 1 }), "invalid_expiry");
    expect(await set(u, { preset: "at_home", expiresAt: now + 1 })).toMatchObject({ expiresAt: now + 1 });
    expect(await set(u, { preset: "at_home", expiresAt: now + 7 * 24 * H })).toMatchObject({
      expiresAt: now + 7 * 24 * H,
    });
  });

  test("replaces the previous status, one row per user", async () => {
    const u = await makeUser(t);
    await set(u, { preset: "at_work" });
    await set(u, { text: "Dal bhat time" });
    const rows = await rowsOf(u.id);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ text: "Dal bhat time" });
    expect(rows[0]!.preset).toBeUndefined();
  });

  test("not_authenticated without a session", async () => {
    await expectCode(t.mutation(api.status.setStatus, { preset: "at_work" }), "not_authenticated");
  });
});

describe("clearStatus", () => {
  test("removes the status and is a no-op when none", async () => {
    const u = await makeUser(t);
    expect(await u.as.mutation(api.status.clearStatus, {})).toBeNull();
    await set(u, { preset: "commuting" });
    await u.as.mutation(api.status.clearStatus, {});
    expect(await rowsOf(u.id)).toHaveLength(0);
  });
});

describe("familyToday status", () => {
  test("shows a live status and hides an expired one", async () => {
    const a = await makeUser(t, "A");
    const b = await makeUser(t, "B");
    const f = await a.as.mutation(api.families.createFamily, { name: "Family" });
    await b.as.mutation(api.families.joinFamily, { code: f.inviteCode });
    const view = async () =>
      (await a.as.query(api.home.familyToday, { familyId: f.familyId })).members.find(
        (m) => m.userId === b.id,
      )!.status;

    expect(await view()).toBeNull();
    const expiresAt = Date.now() + 2 * H;
    await set(b, { preset: "on_a_hike", expiresAt });
    expect(await view()).toEqual({ preset: "on_a_hike", text: null, expiresAt });
    await set(b, { text: "Namaste", expiresAt });
    expect(await view()).toEqual({ preset: null, text: "Namaste", expiresAt });

    vi.setSystemTime(expiresAt - 1);
    expect(await view()).not.toBeNull();
    vi.setSystemTime(expiresAt);
    expect(await view()).toBeNull();
  });

  test("null after clearStatus", async () => {
    const a = await makeUser(t, "A");
    const f = await a.as.mutation(api.families.createFamily, { name: "Family" });
    await set(a, { preset: "at_work" });
    await a.as.mutation(api.status.clearStatus, {});
    const today = await a.as.query(api.home.familyToday, { familyId: f.familyId });
    expect(today.members[0]!.status).toBeNull();
  });
});

describe("account deletion", () => {
  test("removes the user's walks and status, and nobody else's", async () => {
    const u = await makeUser(t);
    const other = await makeUser(t);
    for (const x of [u, other]) {
      await x.as.mutation(api.walks.startWalk, {});
      await x.as.mutation(api.walks.stopWalk, {});
      await x.as.mutation(api.walks.startWalk, {});
      await set(x, { preset: "resting" });
    }
    await t.mutation(internal.users.deleteAccountData, { userId: u.id });
    const left = await t.run(async (ctx) => ({
      walks: await ctx.db.query("walks").collect(),
      statuses: await ctx.db.query("statuses").collect(),
    }));
    expect(left.walks.map((w) => w.userId)).toEqual([other.id, other.id]);
    expect(left.statuses.map((s) => s.userId)).toEqual([other.id]);
  });

  test("leaving a family keeps walks and status (they're per user)", async () => {
    const a = await makeUser(t, "A");
    const b = await makeUser(t, "B");
    const f = await a.as.mutation(api.families.createFamily, { name: "Family" });
    await b.as.mutation(api.families.joinFamily, { code: f.inviteCode });
    await b.as.mutation(api.walks.startWalk, {});
    await set(b, { preset: "resting" });
    await b.as.mutation(api.families.leaveFamily, { familyId: f.familyId });
    expect(await rowsOf(b.id)).toHaveLength(1);
  });
});
