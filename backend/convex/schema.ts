import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/**
 * Phase 1 tables, then phase 2 (walks, statuses, feed events, reactions,
 * devices, notification prefs). Anything per-user or per-member
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

  /**
   * Walks (contract F9–F11). Per user, so a walk shows in every family they're
   * in. Open while `endedAt` is unset and `endsAt` hasn't passed; a scheduled
   * `walks.autoStop` sets `endedAt = endsAt` if nobody stopped it. `nepalDay`
   * is the day it started, for the 3-per-day limit.
   */
  walks: defineTable({
    userId: v.id("users"),
    startedAt: v.number(),
    endsAt: v.number(),
    endedAt: v.optional(v.number()),
    nepalDay: v.string(),
  })
    .index("by_user_open", ["userId", "endedAt"])
    .index("by_user_day", ["userId", "nepalDay"]),

  /**
   * Status (contract F12): at most one row per user. Exactly one of `preset`
   * and `text` is set. Reads as null once `expiresAt` has passed; the row is
   * replaced on the next `setStatus` or removed by `clearStatus`.
   */
  statuses: defineTable({
    userId: v.id("users"),
    preset: v.optional(v.string()),
    text: v.optional(v.string()),
    expiresAt: v.number(),
    updatedAt: v.number(),
  }).index("by_user", ["userId"]),

  /**
   * Family feed (contract F13). member_* / family_* have at most one row per
   * (family, day, type, actor), enforced by checking `by_family_day_type_actor`
   * before inserting; walk_started has one row per walk per family.
   * `actorId` is unset for family_50 / family_100. Purged after 7 days.
   * `lastReactionPushAt` coalesces reaction pushes to the actor (1 per 10 min).
   */
  feedEvents: defineTable({
    familyId: v.id("families"),
    type: v.union(
      v.literal("member_5k"),
      v.literal("member_10k"),
      v.literal("family_50"),
      v.literal("family_100"),
      v.literal("walk_started"),
    ),
    actorId: v.optional(v.id("users")),
    day: v.string(),
    createdAt: v.number(),
    data: v.object({ walkId: v.optional(v.id("walks")) }),
    lastReactionPushAt: v.optional(v.number()),
  })
    .index("by_family_day_type_actor", ["familyId", "day", "type", "actorId"])
    .index("by_family_created", ["familyId", "createdAt"])
    .index("by_actor_family", ["actorId", "familyId"])
    .index("by_createdAt", ["createdAt"]),

  /** Reactions (contract F14): at most one per (event, user). */
  reactions: defineTable({
    eventId: v.id("feedEvents"),
    userId: v.id("users"),
    emoji: v.string(),
  })
    .index("by_event", ["eventId"])
    .index("by_event_user", ["eventId", "userId"])
    .index("by_user", ["userId"]),

  /**
   * APNs device tokens (contract F15). One row per token; registering a token
   * another user had moves it to the caller. `environment` picks the APNs host.
   */
  devices: defineTable({
    apnsToken: v.string(),
    userId: v.id("users"),
    environment: v.union(v.literal("sandbox"), v.literal("production")),
    updatedAt: v.number(),
  })
    .index("by_token", ["apnsToken"])
    .index("by_user", ["userId"])
    .index("by_user_updated", ["userId", "updatedAt"]),

  /** Notification preferences (contract F15). No row means the defaults. */
  notificationPrefs: defineTable({
    userId: v.id("users"),
    walkStarted: v.boolean(),
    goalHit: v.boolean(),
    reactions: v.boolean(),
    eveningNudge: v.boolean(),
    /** Nepal day of the last evening nudge sent, so it goes once per day. */
    lastNudgeDay: v.optional(v.string()),
  })
    .index("by_user", ["userId"])
    .index("by_evening_nudge", ["eveningNudge"]),
});
