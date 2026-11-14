import { describe, expect, test } from "vitest";
import {
  addDays,
  isValidDay,
  nepalDay,
  nepalDayEnd,
  nepalDayStart,
  oldestSyncableDay,
  weekDays,
  weekdayIndex,
} from "../convex/lib/nepalDay";

describe("Nepal day", () => {
  test("rolls over at 18:15 UTC", () => {
    expect(nepalDay(Date.parse("2026-11-14T18:14:59.999Z"))).toBe("2026-11-14");
    expect(nepalDay(Date.parse("2026-11-14T18:15:00.000Z"))).toBe("2026-11-15");
    expect(nepalDay(Date.parse("2026-11-14T00:00:00Z"))).toBe("2026-11-14");
    // Sydney morning on the 15th is still the 14th in Nepal before 18:15 UTC.
    expect(nepalDay(Date.parse("2026-11-14T22:00:00Z"))).toBe("2026-11-15");
  });

  test("day start and end are Nepal midnights", () => {
    expect(new Date(nepalDayStart("2026-11-15")).toISOString()).toBe("2026-11-14T18:15:00.000Z");
    expect(new Date(nepalDayEnd("2026-11-15")).toISOString()).toBe("2026-11-15T18:15:00.000Z");
    expect(nepalDay(nepalDayStart("2026-11-15"))).toBe("2026-11-15");
    expect(nepalDay(nepalDayEnd("2026-11-15") - 1)).toBe("2026-11-15");
  });

  test("validates dates", () => {
    expect(isValidDay("2026-11-14")).toBe(true);
    expect(isValidDay("2024-02-29")).toBe(true);
    expect(isValidDay("2026-02-29")).toBe(false);
    expect(isValidDay("2026-13-01")).toBe(false);
    expect(isValidDay("2026-1-01")).toBe(false);
    expect(isValidDay("yesterday")).toBe(false);
  });

  test("adds days across months and years", () => {
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
  });

  test("weeks run Monday to Sunday", () => {
    // 2026-11-14 is a Saturday.
    expect(weekdayIndex("2026-11-14")).toBe(5);
    expect(weekDays("2026-11-14")).toEqual([
      "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12",
      "2026-11-13", "2026-11-14", "2026-11-15",
    ]);
    expect(weekDays("2026-11-09")[0]).toBe("2026-11-09");
    expect(weekDays("2026-11-15")[0]).toBe("2026-11-09");
  });

  test("sync window is today plus the previous 6 days", () => {
    expect(oldestSyncableDay(Date.parse("2026-11-14T18:15:00Z"))).toBe("2026-11-09");
  });
});
