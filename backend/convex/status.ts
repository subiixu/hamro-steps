import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { requireUser } from "./lib/access";
import {
  DEFAULT_STATUS_TTL_MS,
  MAX_STATUS_TEXT_LENGTH,
  MAX_STATUS_TTL_MS,
  STATUS_PRESETS,
  StatusPreset,
} from "./lib/constants";
import { fail } from "./lib/errors";

/**
 * Sets the user's status (contract F12): exactly one of `preset` (an enum key)
 * or `text` (trimmed, 1–30 UTF-16 code units). `expiresAt` defaults to now +
 * 24 h and must be in the future and at most now + 7 days.
 * Returns the stored status.
 */
export const setStatus = mutation({
  args: {
    preset: v.optional(v.string()),
    text: v.optional(v.string()),
    expiresAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const now = Date.now();

    const hasPreset = args.preset !== undefined;
    const hasText = args.text !== undefined;
    if (hasPreset === hasText) fail("invalid_status");
    let preset: StatusPreset | undefined;
    let text: string | undefined;
    if (hasPreset) {
      if (!(STATUS_PRESETS as readonly string[]).includes(args.preset!)) fail("invalid_status");
      preset = args.preset as StatusPreset;
    } else {
      text = args.text!.trim();
      if (text.length === 0 || text.length > MAX_STATUS_TEXT_LENGTH) fail("invalid_status");
    }

    const expiresAt = args.expiresAt ?? now + DEFAULT_STATUS_TTL_MS;
    if (!Number.isFinite(expiresAt) || expiresAt <= now || expiresAt > now + MAX_STATUS_TTL_MS) {
      fail("invalid_expiry");
    }

    const row = { userId: user._id, preset, text, expiresAt, updatedAt: now };
    const existing = await ctx.db
      .query("statuses")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    if (existing[0]) {
      await ctx.db.replace(existing[0]._id, row);
      for (const extra of existing.slice(1)) await ctx.db.delete(extra._id);
    } else {
      await ctx.db.insert("statuses", row);
    }
    return { preset: preset ?? null, text: text ?? null, expiresAt };
  },
});

/** Clears the user's status. A no-op when none is set. */
export const clearStatus = mutation({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    for await (const row of ctx.db
      .query("statuses")
      .withIndex("by_user", (q) => q.eq("userId", user._id))) {
      await ctx.db.delete(row._id);
    }
    return null;
  },
});
