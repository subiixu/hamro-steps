# Steps history backend: home:familyHistory query
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-17-1200-history-backend.md
## What the user asked
T-44 (part 1 of 2): a Convex query `home:familyHistory({ familyId, days })` returning a family's daily totals vs goal over 2 × N Nepal days, for the iOS History screen.
## What changed
- New query `home:familyHistory({ familyId, days })`, built to the brief's contract exactly. It returns `{ today, days: [{ day, total, goal, hit, isBeforeFamily }] }`: 2 × `days` Nepal days ending today (today included), oldest first.
- Callers who aren't members get `not_member`. That check runs first, so an outsider who also sends a bad `days` still gets `not_member`.
- Any `days` other than 7, 30 or 90 throws `invalid_day` with the message "days must be 7, 30 or 90". `errors.ts` has no general invalid-argument code, and `invalid_day` is the existing code for bad day arguments (as in `syncSteps`), so I used it rather than add a new error code the iOS app would need to know.
- Days before the family's created day come back as `isBeforeFamily: true`, `total: 0`, `hit: false` with the current goal, and no total is computed for them.
- The per-day rules now live in one helper, `familyDayProgress`, in `backend/convex/lib/totals.ts`. Both `familyWeek` and `familyHistory` use it: a closed day uses its snapshot and frozen goal; today, and closed days with no snapshot, use the live total against the current goal.
- `familyWeek`'s output hasn't changed. Its existing tests pass, including the one where days before the family get a live total. Only `familyHistory` skips those days.
## Files
- backend/convex/lib/totals.ts — modified
- backend/convex/home.ts — modified
- backend/tests/history.test.ts — created
## Checks run
`cd backend && npx vitest run tests/history.test.ts`: 5 passed. The tests cover:
- 2N days, oldest first, ending today, for 7, 30 and 90
- a snapshot day keeps its frozen goal after a goal change
- today uses the live total
- a closed day with no snapshot falls back to the live total
- days before the family are flagged with total 0, even when steps were synced for them
- history matches `familyWeek` on the days both return
- days = 5, 0, -7, 14, 7.5 and 365 are rejected with `invalid_day`
- an outsider gets `not_member`

## Checks run
`araniko check`: passed · 2 of 2 passed · 5m 03s
- `scripts/check-ios.sh` · passed · 4m 57s
- `scripts/check-backend.sh` · passed · 5.2 s

Not checked: anything against a deployed Convex backend. Nothing was deployed, as the brief says.
## Libraries used
none touched
## Notes for Nayo
- Deploy the backend to Convex after merge. It adds the query and doesn't change the schema.
- Tell the iOS worker (T-44 part 2) that a bad `days` throws `invalid_day`. The app only ever sends 7, 30 or 90, so this shouldn't matter in practice.
- Suggested commit message: "Backend: home:familyHistory query for the History screen; share per-day logic with familyWeek"

## Checks (run by Araniko)
Passed · 2 of 2 · 2m 31s · 2026-11-17 12:51 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 2m 25s
- `scripts/check-backend.sh` · passed · 5.8 s
