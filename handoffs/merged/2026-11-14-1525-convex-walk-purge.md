# Convex: purge old walks, smaller nudge pages
status: done
agent: claude claude-sonnet-5-5
brief: handoffs/briefs/2026-11-14-1530-convex-walk-purge.md
## What the user asked
(T-7) Delete old ended walks on a daily schedule so account deletion never hits the write limit, and cut the evening-nudge page size to 25.
## What changed
- `internal.walks.purgeOld`: deletes ended walks whose Nepal day is more than `WALK_RETENTION_DAYS` (7) days before today (a walk on the cutoff day, 7 days ago, is kept). Unended walks are never deleted. It pages 200 rows at a time and reschedules itself with the cursor until the old range is exhausted. It uses a cursor rather than feed's "take again" pattern, so old unended walks can't stall the loop.
- New index `walks.by_day` on `nepalDay`.
- Daily cron "purge old walks" at 19:45 UTC.
- `NUDGE_BATCH` is now 25.
- Tests: old ended walks purged; edge-day, recent and old-unended walks kept; 450 old walks across several pages purged while an old unended walk and a recent walk stay.
## Files
- backend/convex/walks.ts — modified
- backend/convex/crons.ts — modified
- backend/convex/notifications.ts — modified
- backend/convex/lib/constants.ts — modified
- backend/convex/schema.ts — modified (index only)
- backend/tests/walks.test.ts — modified
- backend/tests/notifications.test.ts — modified (outside the brief's list, see Notes)
## Checks run
`ultron check`: passed · 2 of 2 passed · 3m 35s
- `scripts/check-ios.sh` · passed · 3m 32s
- `scripts/check-backend.sh` · passed · 3.7 s (9 files, 141 tests)

Not checked: the cron and index on a deployed Convex instance. `_generated/` needed no change (`walks` was already exported).
## Libraries used
none touched
## Notes for Jarvis
- Shared-file edit outside the brief: the existing evening-nudge paging test in `backend/tests/notifications.test.ts` hardcoded the page size of 100. I changed the three `nudged: 100` expectations to `25` (and one comment). The 130-person fixture and its other assertions are unchanged and still pass.
- The new `by_day` index needs a Convex deploy to take effect.
- Suggested commit: "Convex: daily purge of ended walks older than 7 Nepal days, nudge pages of 25"

## Checks override
Merged anyway: worker's ultron check passed 2/2 (141 backend tests); Ultron's re-run still in progress (2026-11-14 15:26)
