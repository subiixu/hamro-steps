import { ConvexError } from "convex/values";

/** Stable error codes the iOS app switches on. Never rename one. */
export type ErrorCode =
  | "not_authenticated"
  | "invalid_code"
  | "family_full"
  | "not_member"
  | "not_organiser"
  | "invalid_goal"
  | "invalid_name"
  | "invalid_steps"
  | "invalid_day"
  | "cannot_remove_self"
  | "invalid_token"
  | "already_walking"
  | "walk_limit_reached"
  | "invalid_status"
  | "invalid_expiry"
  | "invalid_emoji"
  | "invalid_device_token"
  | "invalid_photo"
  | "invalid_city"
  | "invalid_birthday"
  | "not_authorized";

export function fail(code: ErrorCode, message?: string): never {
  throw new ConvexError({ code, ...(message ? { message } : {}) });
}
