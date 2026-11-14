# check-ios.sh: break a stale lock atomically
status: done
agent: opencode iceman-free
brief: handoffs/briefs/2026-11-14-1840-check-ios-atomic-lock.md
## What the user asked
Make the stale-lock break in `scripts/check-ios.sh` atomic so two waiting runs cannot both judge the lock stale and delete a lock the other just acquired.
## What changed
When a stale lock is detected, the script now moves `$LOCK` to `$LOCK.stale.$$` and only removes the moved directory if that `mv` succeeds, then retries acquiring the lock. If the `mv` fails (another process already broke/claimed it), the script falls through and loops again. The existing mkdir lock, pid file handling, 30-minute stale rule, 20-minute wait, and EXIT trap are unchanged.
## Files
- scripts/check-ios.sh — modified
## Checks run
`ultron check`: passed · 2 of 2 passed · 1m 23s
- `scripts/check-ios.sh` · passed · 1m 19s
- `scripts/check-backend.sh` · passed · 4.1 s

Additional: `bash -n scripts/check-ios.sh` (syntax ok).
## Libraries used
none touched
## Questions for the user
## Notes for Jarvis
Suggested commit: "Make check-ios stale lock break atomic"
No shared files outside the lock block in `scripts/check-ios.sh` were modified.

## Checks (run by Ultron)
Passed · 2 of 2 · 1m 12s · 2026-11-14 18:40 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 1m 08s
- `scripts/check-backend.sh` · passed · 3.9 s
