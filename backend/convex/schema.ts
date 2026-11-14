import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/**
 * Phase 1 tables. Phase 2 (walks, statuses, feed events, reactions, devices,
 * notification mutes) adds its own tables; anything per-user or per-member
 * must also be cleaned up in `lib/cleanup.ts` (account deletion, leaving).
 */
export default defineSchema({
  users: defineTable({
    appleSub: v.string(),
    /** Missing until Apple gives a name or the user types one. */
    name: v.optional(v.string()),
    avatarColor: v.string(),
    /** IANA zone from the device; informational only. */
    timezone: v.optional(v.string()),
    lastSyncedAt: v.optional(v.number()),
    createdAt: v.number(),
  }).index("by_appleSub", ["appleSub"]),

  /** Apple's refresh token, kept only to revoke it on account deletion. */
  appleTokens: defineTable({
    userId: v.id("users"),
    refreshToken: v.string(),
    updatedAt: v.number(),
  }).index("by_user", ["userId"]),

  /**
   * Apple refresh tokens still to revoke after their account was deleted,
   * because Apple's /auth/revoke failed at deletion time. Not linked to any
   * user. Retried by `users.retryAppleRevoke` with backoff capped at daily,
   * forever: the row is deleted only once Apple confirms the revoke.
   * `nextAttemptAt` is when the scheduled retry is due; the hourly
   * `users.recoverAppleRevocations` cron reschedules rows long overdue
   * (scheduled actions run at most once, so a retry can be lost).
   */
  appleRevocations: defineTable({
    refreshToken: v.string(),
    /** Failed retries so far (the attempt at deletion isn't counted). */
    attempts: v.number(),
    nextAttemptAt: v.number(),
    createdAt: v.number(),
  }).index("by_nextAttemptAt", ["nextAttemptAt"]),

  /** One per signed-in device. Refresh tokens rotate inside a session. */
  sessions: defineTable({
    userId: v.id("users"),
    createdAt: v.number(),
    revokedAt: v.optional(v.number()),
  }).index("by_user", ["userId"]),

  /**
   * Opaque refresh tokens, stored as SHA-256 hex. A used token stays (with
   * `usedAt`) until it expires, so presenting it again is detected as reuse
   * and revokes the whole session.
   */
  refreshTokens: defineTable({
    sessionId: v.id("sessions"),
    userId: v.id("users"),
    tokenHash: v.string(),
    expiresAt: v.number(),
    usedAt: v.optional(v.number()),
  })
    .index("by_hash", ["tokenHash"])
    .index("by_session", ["sessionId"])
    .index("by_user", ["userId"])
    .index("by_expiresAt", ["expiresAt"]),

  families: defineTable({
    name: v.string(),
    dailyGoal: v.number(),
    inviteCode: v.string(),
    organiserId: v.id("users"),
    /** Next membership position to hand out; positions are never reused. */
    nextPosition: v.number(),
    createdAt: v.number(),
  }).index("by_inviteCode", ["inviteCode"]),

  /** Fixed family order = `position` (join order, organiser first). */
  memberships: defineTable({
    familyId: v.id("families"),
    userId: v.id("users"),
    position: v.number(),
    joinedAt: v.number(),
  })
    .index("by_family_position", ["familyId", "position"])
    .index("by_family_user", ["familyId", "userId"])
    .index("by_user", ["userId"]),

  /** One row per user per Nepal day; shared with every family they're in. */
  dailySteps: defineTable({
    userId: v.id("users"),
    day: v.string(),
    steps: v.number(),
    updatedAt: v.number(),
  }).index("by_user_day", ["userId", "day"]),

  /**
   * A family's closed day, written at Nepal midnight. `goal` is frozen;
   * `total` and `hit` keep updating when members sync late for that day.
   */
  familyDays: defineTable({
    familyId: v.id("families"),
    day: v.string(),
    goal: v.number(),
    total: v.number(),
    hit: v.boolean(),
    closedAt: v.number(),
  }).index("by_family_day", ["familyId", "day"]),

  /**
   * Who counted toward a closed day, one row per member at the close
   * (steps 0 when they hadn't synced). `familyDays.total` is always the sum
   * of these rows. Late syncs update a row; leaving, removal and account
   * deletion delete the member's rows and recompute total and hit (the goal
   * stays frozen).
   */
  dayContributions: defineTable({
    familyId: v.id("families"),
    day: v.string(),
    userId: v.id("users"),
    steps: v.number(),
  })
    .index("by_family_day", ["familyId", "day"])
    .index("by_user_day", ["userId", "day"])
    .index("by_user_family", ["userId", "familyId"]),
});
