export const MAX_MEMBERS = 8;
export const MIN_GOAL = 1_000;
export const MAX_GOAL = 1_000_000;
export const DEFAULT_GOAL = 50_000;
export const MAX_NAME_LENGTH = 40;
/** Typed city label on a profile. */
export const MAX_CITY_LENGTH = 40;
/** Largest profile photo upload. */
export const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
/** Uploaded blobs no profile points at are deleted once older than this. */
export const ORPHAN_BLOB_AGE_MS = 60 * 60_000;
/** Blobs the orphan sweep looks at per mutation; it reschedules itself for the rest. */
export const ORPHAN_SWEEP_BATCH = 200;
export const MAX_DAILY_STEPS = 200_000;

export const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const INVITE_LENGTH = 6;

/** Avatar colours; one is picked at random when a user is created. */
export const AVATAR_PALETTE = [
  "#E4572E", // vermilion
  "#F3A712", // marigold
  "#2E86AB", // lake blue
  "#3BB273", // rice green
  "#7768AE", // lavender
  "#D45D79", // rhododendron
  "#1B998B", // teal
  "#8C5E58", // clay
] as const;

export const ACCESS_TOKEN_TTL_MS = 60 * 60 * 1000;
export const REFRESH_TOKEN_TTL_MS = 90 * 24 * 60 * 60 * 1000;
/** `aud` of our access JWTs; must match `applicationID` in auth.config.ts. */
export const JWT_AUDIENCE = "hamro-steps";
export const DEFAULT_BUNDLE_ID = "com.bixustudio.hamrosteps";

/**
 * Waits before each retry of a failed Apple revoke after account deletion
 * (1 min, 10 min, 1 h, 6 h, then daily). After the last one the daily wait
 * repeats forever: the token is kept until Apple confirms the revoke.
 */
export const APPLE_REVOKE_RETRY_DELAYS_MS = [
  60_000,
  10 * 60_000,
  60 * 60_000,
  6 * 60 * 60_000,
  24 * 60 * 60_000,
  24 * 60 * 60_000,
  24 * 60 * 60_000,
];

/** A walk ends by itself this long after it starts (contract F9). */
export const WALK_DURATION_MS = 2 * 60 * 60 * 1000;
/** Walk starts allowed per user per Nepal day. */
export const MAX_WALKS_PER_DAY = 3;

/** Status presets, as the enum keys the app sends (contract F12). */
export const STATUS_PRESETS = [
  "at_work",
  "at_home",
  "commuting",
  "working_out",
  "on_a_hike",
  "resting",
  "travelling",
] as const;
export type StatusPreset = (typeof STATUS_PRESETS)[number];
/** Max custom status length in UTF-16 code units (JS `.length`), after trimming. */
export const MAX_STATUS_TEXT_LENGTH = 30;
export const DEFAULT_STATUS_TTL_MS = 24 * 60 * 60 * 1000;
export const MAX_STATUS_TTL_MS = 7 * 24 * 60 * 60 * 1000;

/** Feed (contract F13): how many Nepal days `feed` shows, and its cap. */
export const FEED_WINDOW_DAYS = 3;
export const FEED_MAX_EVENTS = 100;
/** Feed events older than this are purged daily. */
export const FEED_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
/** Ended walks whose Nepal day is older than this many days are purged daily. */
export const WALK_RETENTION_DAYS = 7;
export const MEMBER_STEP_MILESTONES = [
  { steps: 5_000, type: "member_5k" },
  { steps: 10_000, type: "member_10k" },
] as const;

/** Reactions (contract F14), in the fixed order `feed` reports them. */
export const REACTION_EMOJI = ["👏", "❤️", "🙌", "🔥", "😄"] as const;
export type ReactionEmoji = (typeof REACTION_EMOJI)[number];

/** Notification prefs (contract F15) when the user has never set them. */
export const DEFAULT_NOTIFICATION_PREFS = {
  walkStarted: true,
  goalHit: true,
  reactions: true,
  eveningNudge: false,
} as const;
/** At most one reaction push per feed event in this window. */
export const REACTION_PUSH_COALESCE_MS = 10 * 60 * 1000;
/** APNs provider JWTs are reused this long (Apple allows 20–60 min). */
export const APNS_JWT_TTL_MS = 50 * 60 * 1000;
export const APNS_HOSTS = {
  production: "api.push.apple.com",
  sandbox: "api.sandbox.push.apple.com",
} as const;

/**
 * Registered phones kept per user. Registering one more retires the device
 * that registered least recently, so delivery can always reach every device.
 */
export const MAX_DEVICES_PER_USER = 10;
