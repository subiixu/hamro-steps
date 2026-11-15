import { QueryCtx } from "../_generated/server";
import { Doc } from "../_generated/dataModel";
import { fail } from "./errors";
import { MAX_CITY_LENGTH } from "./constants";

/** Signed URL of the user's photo, or null when none (or the blob is gone). */
export async function photoUrl(ctx: QueryCtx, user: Doc<"users">): Promise<string | null> {
  return user.photoId ? await ctx.storage.getUrl(user.photoId) : null;
}

/** What family members see of each other beyond name: photo, city, zone. */
export async function memberProfile(ctx: QueryCtx, user: Doc<"users">) {
  return {
    photoUrl: await photoUrl(ctx, user),
    city: user.city ?? null,
    timezone: user.timezone ?? null,
  };
}

/** Trims a typed city label; `undefined` means "clear it". Max 40 chars. */
export function cleanCity(city: string): string | undefined {
  const trimmed = city.trim().replace(/\s+/g, " ");
  if (trimmed.length === 0) return undefined;
  if ([...trimmed].length > MAX_CITY_LENGTH) fail("invalid_city");
  return trimmed;
}

/**
 * A real calendar date "YYYY-MM-DD", year ≥ 1900, not in the future.
 * "Future" is judged against the date at UTC+14 (the earliest zone), so a
 * birthday set to today is accepted wherever the user is.
 */
export function checkBirthday(birthday: string, now: number): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(birthday);
  if (!m) fail("invalid_birthday");
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const date = new Date(Date.UTC(y, mo - 1, d));
  if (
    y < 1900 ||
    date.getUTCFullYear() !== y ||
    date.getUTCMonth() !== mo - 1 ||
    date.getUTCDate() !== d
  ) {
    fail("invalid_birthday");
  }
  const latest = new Date(now + 14 * 3_600_000).toISOString().slice(0, 10);
  if (birthday > latest) fail("invalid_birthday");
  return birthday;
}
