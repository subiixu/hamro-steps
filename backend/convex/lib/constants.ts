export const MAX_MEMBERS = 8;
export const MIN_GOAL = 1_000;
export const MAX_GOAL = 1_000_000;
export const DEFAULT_GOAL = 50_000;
export const MAX_NAME_LENGTH = 40;
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
 * (1 min, 10 min, 1 h, 6 h, then daily). After the last one the token is
 * dropped with an error log.
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
