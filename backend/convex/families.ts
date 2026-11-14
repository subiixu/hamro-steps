import { v } from "convex/values";
import { mutation, query, MutationCtx } from "./_generated/server";
import { Doc } from "./_generated/dataModel";
import {
  familyMembers,
  getMembership,
  requireMember,
  requireOrganiser,
  requireUser,
} from "./lib/access";
import { removeMembership } from "./lib/cleanup";
import { fail } from "./lib/errors";
import { checkGoal, cleanName } from "./lib/validate";
import { DEFAULT_GOAL, INVITE_ALPHABET, INVITE_LENGTH, MAX_MEMBERS } from "./lib/constants";

/** Uppercases and strips spaces/dashes; `null` if it can't be a code. */
function normaliseInviteCode(raw: string): string | null {
  const code = raw.toUpperCase().replace(/[\s-]/g, "");
  if (code.length !== INVITE_LENGTH) return null;
  for (const ch of code) if (!INVITE_ALPHABET.includes(ch)) return null;
  return code;
}

async function newInviteCode(ctx: MutationCtx): Promise<string> {
  for (;;) {
    let code = "";
    for (let i = 0; i < INVITE_LENGTH; i++) {
      code += INVITE_ALPHABET[Math.floor(Math.random() * INVITE_ALPHABET.length)];
    }
    const taken = await ctx.db
      .query("families")
      .withIndex("by_inviteCode", (q) => q.eq("inviteCode", code))
      .first();
    if (!taken) return code;
  }
}

function familyView(family: Doc<"families">, memberCount: number) {
  return {
    familyId: family._id,
    name: family.name,
    dailyGoal: family.dailyGoal,
    inviteCode: family.inviteCode,
    organiserId: family.organiserId,
    memberCount,
    isFull: memberCount >= MAX_MEMBERS,
  };
}

/** The caller becomes organiser at position 0. */
export const createFamily = mutation({
  args: { name: v.string(), dailyGoal: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const name = cleanName(args.name);
    const dailyGoal = checkGoal(args.dailyGoal ?? DEFAULT_GOAL);
    const now = Date.now();
    const familyId = await ctx.db.insert("families", {
      name,
      dailyGoal,
      inviteCode: await newInviteCode(ctx),
      organiserId: user._id,
      nextPosition: 1,
      createdAt: now,
    });
    await ctx.db.insert("memberships", {
      familyId,
      userId: user._id,
      position: 0,
      joinedAt: now,
    });
    const family = (await ctx.db.get(familyId))!;
    return familyView(family, 1);
  },
});

/** For the join screen: which family a code points at, before joining. */
export const previewInvite = query({
  args: { code: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const code = normaliseInviteCode(args.code);
    const family = code
      ? await ctx.db
          .query("families")
          .withIndex("by_inviteCode", (q) => q.eq("inviteCode", code))
          .unique()
      : null;
    if (!family) fail("invalid_code");
    const members = await familyMembers(ctx, family._id);
    return {
      familyId: family._id,
      name: family.name,
      memberCount: members.length,
      isFull: members.length >= MAX_MEMBERS,
      alreadyMember: members.some((m) => m.userId === user._id),
    };
  },
});

/** Case/space/dash-insensitive and idempotent. */
export const joinFamily = mutation({
  args: { code: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const code = normaliseInviteCode(args.code);
    const family = code
      ? await ctx.db
          .query("families")
          .withIndex("by_inviteCode", (q) => q.eq("inviteCode", code))
          .unique()
      : null;
    if (!family) fail("invalid_code");
    const members = await familyMembers(ctx, family._id);
    if (members.some((m) => m.userId === user._id)) {
      return familyView(family, members.length);
    }
    if (members.length >= MAX_MEMBERS) fail("family_full");
    await ctx.db.insert("memberships", {
      familyId: family._id,
      userId: user._id,
      position: family.nextPosition,
      joinedAt: Date.now(),
    });
    await ctx.db.patch(family._id, { nextPosition: family.nextPosition + 1 });
    return familyView((await ctx.db.get(family._id))!, members.length + 1);
  },
});

/** Every family the caller is in, in the order they joined them. */
export const myFamilies = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    const memberships = await ctx.db
      .query("memberships")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    memberships.sort((a, b) => a.joinedAt - b.joinedAt);
    const result = [];
    for (const m of memberships) {
      const family = await ctx.db.get(m.familyId);
      if (!family) continue;
      const members = await familyMembers(ctx, family._id);
      result.push({
        ...familyView(family, members.length),
        isOrganiser: family.organiserId === user._id,
        position: m.position,
      });
    }
    return result;
  },
});

/** Organiser only. Either field may be omitted. */
export const updateFamily = mutation({
  args: {
    familyId: v.id("families"),
    name: v.optional(v.string()),
    dailyGoal: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { family } = await requireOrganiser(ctx, args.familyId);
    const patch: Partial<Doc<"families">> = {};
    if (args.name !== undefined) patch.name = cleanName(args.name);
    if (args.dailyGoal !== undefined) patch.dailyGoal = checkGoal(args.dailyGoal);
    await ctx.db.patch(family._id, patch);
    const members = await familyMembers(ctx, family._id);
    return familyView((await ctx.db.get(family._id))!, members.length);
  },
});

/** Organiser only. The old code stops working at once. */
export const regenerateInviteCode = mutation({
  args: { familyId: v.id("families") },
  handler: async (ctx, args) => {
    const { family } = await requireOrganiser(ctx, args.familyId);
    const inviteCode = await newInviteCode(ctx);
    await ctx.db.patch(family._id, { inviteCode });
    return { inviteCode };
  },
});

/** Organiser only; the organiser leaves with `leaveFamily` instead. */
export const removeMember = mutation({
  args: { familyId: v.id("families"), userId: v.id("users") },
  handler: async (ctx, args) => {
    const { user } = await requireOrganiser(ctx, args.familyId);
    if (args.userId === user._id) fail("cannot_remove_self");
    const target = await getMembership(ctx, args.familyId, args.userId);
    if (!target) fail("not_member");
    await removeMembership(ctx, target);
    return null;
  },
});

/**
 * Leaves a family. An organiser's role passes to the earliest-joined
 * remaining member; the last member leaving deletes the family.
 */
export const leaveFamily = mutation({
  args: { familyId: v.id("families") },
  handler: async (ctx, args) => {
    const { membership } = await requireMember(ctx, args.familyId);
    await removeMembership(ctx, membership);
    return null;
  },
});
