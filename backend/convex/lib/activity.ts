import { QueryCtx } from "../_generated/server";
import { Doc, Id } from "../_generated/dataModel";
import { StatusPreset } from "./constants";

/**
 * The user's walk that is still open at `now`: not stopped and not past
 * `endsAt`. A walk past `endsAt` whose autoStop hasn't run yet counts as ended.
 */
export async function openWalk(
  ctx: QueryCtx,
  userId: Id<"users">,
  now: number,
): Promise<Doc<"walks"> | null> {
  const rows = await ctx.db
    .query("walks")
    .withIndex("by_user_open", (q) => q.eq("userId", userId).eq("endedAt", undefined))
    .collect();
  return rows.find((w) => w.endsAt > now) ?? null;
}

export type StatusView = { preset: StatusPreset | null; text: string | null; expiresAt: number };

/** The user's status as `familyToday` shows it, or null when none or expired. */
export async function activeStatus(
  ctx: QueryCtx,
  userId: Id<"users">,
  now: number,
): Promise<StatusView | null> {
  const row = await ctx.db
    .query("statuses")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .first();
  if (!row || row.expiresAt <= now) return null;
  return {
    preset: (row.preset as StatusPreset | undefined) ?? null,
    text: row.text ?? null,
    expiresAt: row.expiresAt,
  };
}
