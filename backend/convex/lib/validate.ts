import { fail } from "./errors";
import { MAX_GOAL, MAX_NAME_LENGTH, MIN_GOAL } from "./constants";

/** Trims and checks a family or person name (1–40 chars). */
export function cleanName(name: string): string {
  const trimmed = name.trim().replace(/\s+/g, " ");
  if (trimmed.length < 1 || [...trimmed].length > MAX_NAME_LENGTH) fail("invalid_name");
  return trimmed;
}

export function checkGoal(goal: number): number {
  if (!Number.isInteger(goal) || goal < MIN_GOAL || goal > MAX_GOAL) fail("invalid_goal");
  return goal;
}
