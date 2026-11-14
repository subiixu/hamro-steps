import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { AVATAR_PALETTE, MAX_NAME_LENGTH } from "./lib/constants";

/** Internal: called only from the HTTP actions in http.ts. */

function tidyAppleName(name: string | undefined): string | undefined {
  const trimmed = name?.trim().replace(/\s+/g, " ");
  if (!trimmed) return undefined;
  return [...trimmed].slice(0, MAX_NAME_LENGTH).join("");
}

/** Upserts the user by Apple `sub` and opens a new session. */
export const signInWithApple = internalMutation({
  args: {
    appleSub: v.string(),
    name: v.optional(v.string()),
    timezone: v.optional(v.string()),
    appleRefreshToken: v.optional(v.string()),
    refreshTokenHash: v.string(),
    refreshExpiresAt: v.number(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const appleName = tidyAppleName(args.name);
    let user = await ctx.db
      .query("users")
      .withIndex("by_appleSub", (q) => q.eq("appleSub", args.appleSub))
      .unique();
    const isNewUser = !user;
    if (!user) {
      const userId = await ctx.db.insert("users", {
        appleSub: args.appleSub,
        name: appleName,
        avatarColor: AVATAR_PALETTE[Math.floor(Math.random() * AVATAR_PALETTE.length)]!,
        timezone: args.timezone,
        createdAt: now,
      });
      user = (await ctx.db.get(userId))!;
    } else {
      const patch: { name?: string; timezone?: string } = {};
      // Apple only sends the name on the very first authorisation.
      if (!user.name && appleName) patch.name = appleName;
      if (args.timezone) patch.timezone = args.timezone;
      if (Object.keys(patch).length) await ctx.db.patch(user._id, patch);
    }

    if (args.appleRefreshToken) {
      const existing = await ctx.db
        .query("appleTokens")
        .withIndex("by_user", (q) => q.eq("userId", user._id))
        .unique();
      if (existing) {
        await ctx.db.patch(existing._id, { refreshToken: args.appleRefreshToken, updatedAt: now });
      } else {
        await ctx.db.insert("appleTokens", {
          userId: user._id,
          refreshToken: args.appleRefreshToken,
          updatedAt: now,
        });
      }
    }

    const sessionId = await ctx.db.insert("sessions", { userId: user._id, createdAt: now });
    await ctx.db.insert("refreshTokens", {
      sessionId,
      userId: user._id,
      tokenHash: args.refreshTokenHash,
      expiresAt: args.refreshExpiresAt,
    });
    const name = user.name ?? appleName ?? null;
    return { userId: user._id, isNewUser, name, needsName: !name };
  },
});

/**
 * Rotates a refresh token. A token presented a second time means it leaked:
 * the whole session is revoked. Returns `{ ok: false }` instead of throwing
 * so that revocation commits.
 */
export const rotateRefreshToken = internalMutation({
  args: { tokenHash: v.string(), newTokenHash: v.string(), newExpiresAt: v.number() },
  handler: async (ctx, args) => {
    const now = Date.now();
    const token = await ctx.db
      .query("refreshTokens")
      .withIndex("by_hash", (q) => q.eq("tokenHash", args.tokenHash))
      .unique();
    if (!token) return { ok: false as const, reason: "unknown" };
    const session = await ctx.db.get(token.sessionId);
    if (!session || session.revokedAt !== undefined) return { ok: false as const, reason: "revoked" };
    if (token.usedAt !== undefined) {
      await ctx.db.patch(session._id, { revokedAt: now });
      return { ok: false as const, reason: "reused" };
    }
    if (token.expiresAt <= now) return { ok: false as const, reason: "expired" };
    const user = await ctx.db.get(token.userId);
    if (!user) return { ok: false as const, reason: "unknown" };

    await ctx.db.patch(token._id, { usedAt: now });
    await ctx.db.insert("refreshTokens", {
      sessionId: session._id,
      userId: token.userId,
      tokenHash: args.newTokenHash,
      expiresAt: args.newExpiresAt,
    });
    return { ok: true as const, userId: token.userId };
  },
});

/** Signs out the session the refresh token belongs to. Unknown tokens are ignored. */
export const revokeSession = internalMutation({
  args: { tokenHash: v.string() },
  handler: async (ctx, args) => {
    const token = await ctx.db
      .query("refreshTokens")
      .withIndex("by_hash", (q) => q.eq("tokenHash", args.tokenHash))
      .unique();
    if (!token) return null;
    const session = await ctx.db.get(token.sessionId);
    if (session && session.revokedAt === undefined) {
      await ctx.db.patch(session._id, { revokedAt: Date.now() });
    }
    return null;
  },
});

/** Daily: deletes expired refresh tokens and sessions left with none. */
export const purgeExpired = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const expired = await ctx.db
      .query("refreshTokens")
      .withIndex("by_expiresAt", (q) => q.lt("expiresAt", now))
      .take(1000);
    const sessionIds = new Set(expired.map((t) => t.sessionId));
    for (const t of expired) await ctx.db.delete(t._id);
    for (const sessionId of sessionIds) {
      const left = await ctx.db
        .query("refreshTokens")
        .withIndex("by_session", (q) => q.eq("sessionId", sessionId))
        .first();
      if (!left && (await ctx.db.get(sessionId))) await ctx.db.delete(sessionId);
    }
    return { deleted: expired.length };
  },
});
