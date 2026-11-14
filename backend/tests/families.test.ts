import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { expectCode, makeUser, newTest, rowsFor, T, User } from "./helpers";

let t: T;
beforeEach(() => {
  t = newTest();
});
afterEach(() => vi.useRealTimers());

async function familyWith(n: number) {
  const organiser = await makeUser(t, "Organiser");
  const family = await organiser.as.mutation(api.families.createFamily, { name: "Sharma family" });
  const members: User[] = [organiser];
  for (let i = 1; i < n; i++) {
    const m = await makeUser(t, `Member ${i}`);
    await m.as.mutation(api.families.joinFamily, { code: family.inviteCode });
    members.push(m);
  }
  return { family, familyId: family.familyId as Id<"families">, members, organiser };
}

describe("createFamily", () => {
  test("caller becomes organiser with the default goal and a valid code", async () => {
    const u = await makeUser(t);
    const f = await u.as.mutation(api.families.createFamily, { name: "  Thapa   Family " });
    expect(f).toMatchObject({ name: "Thapa Family", dailyGoal: 50000, organiserId: u.id, memberCount: 1 });
    expect(f.inviteCode).toMatch(/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/);
  });

  test("validates name and goal", async () => {
    const u = await makeUser(t);
    await expectCode(u.as.mutation(api.families.createFamily, { name: "" }), "invalid_name");
    await expectCode(u.as.mutation(api.families.createFamily, { name: "x".repeat(41) }), "invalid_name");
    await expectCode(u.as.mutation(api.families.createFamily, { name: "A", dailyGoal: 999 }), "invalid_goal");
    await expectCode(u.as.mutation(api.families.createFamily, { name: "A", dailyGoal: 1_000_001 }), "invalid_goal");
    await expectCode(u.as.mutation(api.families.createFamily, { name: "A", dailyGoal: 1500.5 }), "invalid_goal");
    const f = await u.as.mutation(api.families.createFamily, { name: "x".repeat(40), dailyGoal: 1000 });
    expect(f.dailyGoal).toBe(1000);
  });

  test("needs sign-in", async () => {
    await expectCode(t.mutation(api.families.createFamily, { name: "A" }), "not_authenticated");
    await expectCode(t.withIdentity({ subject: "garbage" }).query(api.families.myFamilies, {}), "not_authenticated");
  });
});

describe("joining", () => {
  test("code is case, space and dash insensitive, and joining twice is a no-op", async () => {
    const { family, familyId } = await familyWith(1);
    const u = await makeUser(t);
    const messy = ` ${family.inviteCode.slice(0, 3).toLowerCase()}-${family.inviteCode.slice(3)} `;
    const preview = await u.as.query(api.families.previewInvite, { code: messy });
    expect(preview).toMatchObject({ name: "Sharma family", memberCount: 1, isFull: false, alreadyMember: false });
    expect((await u.as.mutation(api.families.joinFamily, { code: messy })).memberCount).toBe(2);
    expect((await u.as.mutation(api.families.joinFamily, { code: family.inviteCode })).memberCount).toBe(2);
    const memberships = await t.run((ctx) =>
      ctx.db.query("memberships").withIndex("by_family_user", (q) => q.eq("familyId", familyId).eq("userId", u.id)).collect(),
    );
    expect(memberships).toHaveLength(1);
  });

  test("wrong code", async () => {
    await familyWith(1);
    const u = await makeUser(t);
    for (const code of ["ZZZZZZ", "abc", "OOOOOO", ""]) {
      await expectCode(u.as.mutation(api.families.joinFamily, { code }), "invalid_code");
    }
    await expectCode(u.as.query(api.families.previewInvite, { code: "ZZZZZZ" }), "invalid_code");
  });

  test("a family is full at 8", async () => {
    const { family } = await familyWith(8);
    const ninth = await makeUser(t);
    expect((await ninth.as.query(api.families.previewInvite, { code: family.inviteCode })).isFull).toBe(true);
    await expectCode(ninth.as.mutation(api.families.joinFamily, { code: family.inviteCode }), "family_full");
  });

  test("a person can be in several families, listed in join order", async () => {
    const a = await familyWith(1);
    const b = await familyWith(2);
    const u = b.members[1]!;
    await u.as.mutation(api.families.joinFamily, { code: a.family.inviteCode });
    const own = await u.as.mutation(api.families.createFamily, { name: "My own" });
    const mine = await u.as.query(api.families.myFamilies, {});
    expect(mine.map((f) => f.familyId)).toEqual([b.familyId, a.familyId, own.familyId]);
    expect(mine.map((f) => f.isOrganiser)).toEqual([false, false, true]);
  });
});

describe("organiser-only actions", () => {
  test("members get not_organiser", async () => {
    const { familyId, members } = await familyWith(3);
    const member = members[1]!;
    await expectCode(member.as.mutation(api.families.updateFamily, { familyId, dailyGoal: 2000 }), "not_organiser");
    await expectCode(member.as.mutation(api.families.regenerateInviteCode, { familyId }), "not_organiser");
    await expectCode(member.as.mutation(api.families.removeMember, { familyId, userId: members[2]!.id }), "not_organiser");
  });

  test("organiser updates name and goal, validated", async () => {
    const { familyId, organiser } = await familyWith(1);
    const f = await organiser.as.mutation(api.families.updateFamily, { familyId, name: "Thapas", dailyGoal: 30000 });
    expect(f).toMatchObject({ name: "Thapas", dailyGoal: 30000 });
    await expectCode(organiser.as.mutation(api.families.updateFamily, { familyId, dailyGoal: 10 }), "invalid_goal");
    await expectCode(organiser.as.mutation(api.families.updateFamily, { familyId, name: "" }), "invalid_name");
  });

  test("regenerating the code kills the old one", async () => {
    const { family, familyId, organiser } = await familyWith(1);
    const { inviteCode } = await organiser.as.mutation(api.families.regenerateInviteCode, { familyId });
    expect(inviteCode).not.toBe(family.inviteCode);
    const u = await makeUser(t);
    await expectCode(u.as.mutation(api.families.joinFamily, { code: family.inviteCode }), "invalid_code");
    expect((await u.as.mutation(api.families.joinFamily, { code: inviteCode })).memberCount).toBe(2);
  });

  test("removing a member, not yourself", async () => {
    const { familyId, organiser, members } = await familyWith(3);
    const removed = members[1]!;
    await expectCode(organiser.as.mutation(api.families.removeMember, { familyId, userId: organiser.id }), "cannot_remove_self");
    await organiser.as.mutation(api.families.removeMember, { familyId, userId: removed.id });
    await expectCode(organiser.as.mutation(api.families.removeMember, { familyId, userId: removed.id }), "not_member");
    await expectCode(removed.as.query(api.home.familyToday, { familyId }), "not_member");
    expect(await removed.as.query(api.families.myFamilies, {})).toEqual([]);
  });
});

describe("leaving", () => {
  test("organiser leaving hands over to the earliest-joined member", async () => {
    const { familyId, organiser, members } = await familyWith(3);
    await organiser.as.mutation(api.families.leaveFamily, { familyId });
    const today = await members[1]!.as.query(api.home.familyToday, { familyId });
    expect(today.family.organiserId).toBe(members[1]!.id);
    expect(today.members.map((m) => [m.userId, m.isOrganiser])).toEqual([
      [members[1]!.id, true],
      [members[2]!.id, false],
    ]);
    // The new organiser can now do organiser things.
    await members[1]!.as.mutation(api.families.updateFamily, { familyId, dailyGoal: 20000 });
  });

  test("a plain member leaving keeps the organiser", async () => {
    const { familyId, organiser, members } = await familyWith(2);
    await members[1]!.as.mutation(api.families.leaveFamily, { familyId });
    const today = await organiser.as.query(api.home.familyToday, { familyId });
    expect(today.members.map((m) => m.userId)).toEqual([organiser.id]);
  });

  test("the last member leaving deletes the family and its history", async () => {
    const { familyId, organiser } = await familyWith(1);
    await t.run((ctx) =>
      ctx.db.insert("familyDays", { familyId, day: "2026-11-01", goal: 50000, total: 1, hit: false, closedAt: 0 }),
    );
    await organiser.as.mutation(api.families.leaveFamily, { familyId });
    const left = await t.run(async (ctx) => ({
      family: await ctx.db.get(familyId),
      days: await ctx.db.query("familyDays").collect(),
      memberships: await ctx.db.query("memberships").collect(),
    }));
    expect(left).toEqual({ family: null, days: [], memberships: [] });
    expect(await rowsFor(t, organiser.id)).toEqual(["users"]);
  });
});

describe("account deletion", () => {
  test("removes every row and passes organiser on", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-11-14T06:00:00Z"));
    const { familyId, organiser, members } = await familyWith(3);
    const solo = await organiser.as.mutation(api.families.createFamily, { name: "Just me" });
    await organiser.as.mutation(api.steps.syncSteps, { days: [{ day: "2026-11-14", steps: 4000 }] });
    await t.run(async (ctx) => {
      const s = await ctx.db.insert("sessions", { userId: organiser.id, createdAt: 0 });
      await ctx.db.insert("refreshTokens", { sessionId: s, userId: organiser.id, tokenHash: "h", expiresAt: 1e15 });
      await ctx.db.insert("appleTokens", { userId: organiser.id, refreshToken: "r", updatedAt: 0 });
    });

    // No Apple env here, so the stored Apple token is queued (unlinked), not dropped.
    expect(await organiser.as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "queued" });
    expect(await rowsFor(t, organiser.id)).toEqual([]);
    const queued = await t.run((ctx) => ctx.db.query("appleRevocations").collect());
    expect(queued.map((r) => r.refreshToken)).toEqual(["r"]);
    const after = await t.run(async (ctx) => ({
      solo: await ctx.db.get(solo.familyId),
      shared: await ctx.db.get(familyId),
    }));
    expect(after.solo).toBeNull();
    expect(after.shared?.organiserId).toBe(members[1]!.id);
    const today = await members[1]!.as.query(api.home.familyToday, { familyId });
    expect(today.total).toBe(0);
    expect(today.members).toHaveLength(2);
  });
});

describe("non-members", () => {
  test("get not_member from every family function", async () => {
    const { familyId } = await familyWith(2);
    const outsider = await makeUser(t);
    await expectCode(outsider.as.query(api.home.familyToday, { familyId }), "not_member");
    await expectCode(outsider.as.query(api.home.familyWeek, { familyId }), "not_member");
    await expectCode(outsider.as.mutation(api.families.updateFamily, { familyId, dailyGoal: 2000 }), "not_member");
    await expectCode(outsider.as.mutation(api.families.regenerateInviteCode, { familyId }), "not_member");
    await expectCode(outsider.as.mutation(api.families.removeMember, { familyId, userId: outsider.id }), "not_member");
    await expectCode(outsider.as.mutation(api.families.leaveFamily, { familyId }), "not_member");
  });

  test("a deleted family reads as not_member", async () => {
    const { familyId, organiser } = await familyWith(1);
    await organiser.as.mutation(api.families.leaveFamily, { familyId });
    await expectCode(organiser.as.query(api.home.familyToday, { familyId }), "not_member");
  });
});
