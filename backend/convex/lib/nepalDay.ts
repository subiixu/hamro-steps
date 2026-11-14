/**
 * Nepal-day helpers. Every "day" in Hamro Steps is a calendar day in
 * Asia/Kathmandu (UTC+5:45, no DST), written as "YYYY-MM-DD".
 * Nepal midnight is 18:15 UTC on the previous UTC date.
 */

export const NEPAL_OFFSET_MS = (5 * 60 + 45) * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const DAY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** The Nepal day containing the instant `ms` (epoch millis). */
export function nepalDay(ms: number): string {
  return new Date(ms + NEPAL_OFFSET_MS).toISOString().slice(0, 10);
}

/** True when `day` is a real calendar date written as YYYY-MM-DD. */
export function isValidDay(day: string): boolean {
  const m = DAY_RE.exec(day);
  if (!m) return false;
  const d = new Date(`${day}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === day;
}

/** Epoch millis of Nepal midnight at the start of `day`. */
export function nepalDayStart(day: string): number {
  return Date.parse(`${day}T00:00:00Z`) - NEPAL_OFFSET_MS;
}

/** Epoch millis of Nepal midnight at the end of `day` (start of the next day). */
export function nepalDayEnd(day: string): number {
  return nepalDayStart(day) + DAY_MS;
}

/** `day` shifted by `n` calendar days. */
export function addDays(day: string, n: number): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) + n * DAY_MS)
    .toISOString()
    .slice(0, 10);
}

/** Monday = 0 … Sunday = 6. */
export function weekdayIndex(day: string): number {
  return (new Date(`${day}T00:00:00Z`).getUTCDay() + 6) % 7;
}

/** The seven days Monday–Sunday of the week containing `day`. */
export function weekDays(day: string): string[] {
  const monday = addDays(day, -weekdayIndex(day));
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i));
}

/** How many days back `syncSteps` accepts: today plus the previous 6. */
export const SYNC_WINDOW_DAYS = 7;

/** The oldest day `syncSteps` accepts at instant `ms`. */
export function oldestSyncableDay(ms: number): string {
  return addDays(nepalDay(ms), -(SYNC_WINDOW_DAYS - 1));
}
