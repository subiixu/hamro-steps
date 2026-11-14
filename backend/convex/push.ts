import { v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";

/** Internal reads and writes for `pushNode.send`, which runs in Node. */

/** Every registered device of `userIds` (at most MAX_DEVICES_PER_USER each). */
export const devicesFor = internalQuery({
  args: { userIds: v.array(v.id("users")) },
  handler: async (ctx, args) => {
    const out = [];
    for (const userId of new Set(args.userIds)) {
      const devices = await ctx.db
        .query("devices")
        .withIndex("by_user", (q) => q.eq("userId", userId))
        .collect();
      for (const d of devices) {
        out.push({ apnsToken: d.apnsToken, environment: d.environment, updatedAt: d.updatedAt });
      }
    }
    return out;
  },
});

/**
 * Deletes a token APNs rejected. With `invalidSince` (APNs' 410 timestamp),
 * keeps it if it was registered again after that.
 */
export const removeDevice = internalMutation({
  args: { apnsToken: v.string(), invalidSince: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const d = await ctx.db
      .query("devices")
      .withIndex("by_token", (q) => q.eq("apnsToken", args.apnsToken))
      .unique();
    if (!d) return false;
    if (args.invalidSince !== undefined && d.updatedAt > args.invalidSince) return false;
    await ctx.db.delete(d._id);
    return true;
  },
});
