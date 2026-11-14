# check-ios.sh: break stale locks, skip slow failure diagnostics
status: done
agent: claude sonnet-5-5
brief: handoffs/briefs/2026-11-14-1700-check-ios-hardening.md
## What the user asked
`scripts/check-ios.sh` should never block on a lock left by a killed run, should not run `simctl diagnose` on test failure, and should clean up dead `hamro-check-<pid>` simulators.
## What changed
- Lock: after `mkdir` succeeds the script writes `$$` to `$LOCK/pid`. While waiting, a lock whose pid is dead (`kill -0` fails), or with no pid file and older than 30 minutes, is removed and the loop retries at once. The EXIT trap removes `pid` before `rmdir`.
- `xcodebuild test` now has `-collect-test-diagnostics never`.
- Before creating its simulator the script deletes `hamro-check-<pid>` simulators whose pid is dead (names parsed from `xcrun simctl list devices`). Live and non-matching simulators are untouched. Shutdown/delete failures are non-fatal (`simctl shutdown` errors on an already-shut-down device, which tripped `set -e` on my first try).
- Bash 3.2-compatible (no new bashisms; `bash -n` passes).
## Files
- scripts/check-ios.sh — modified
## Checks run
- `bash -n scripts/check-ios.sh`: ok.
- `scripts/check-ios.sh`: exit 0, 64 s.
- Stale lock: created `$TMPDIR/hamro-check-8cbc433b.lock` with `pid` = 999999, ran the script. It printed "removing stale lock" and went straight to building (no wait; whole run 80 s including the build).
- Dead simulator: created `hamro-check-999998`, ran the script: it was deleted. `hamro-check-22476` (another worker's live check, pid alive) was left alone. The lock dir was gone after each run.
- Not checked: the no-pid-file >30 min branch (not exercised, only reviewed), and the failing-test path (no `-collect-test-diagnostics` timing on a real failure).

## Checks run
`ultron check`: passed · 2 of 2 passed · 1m 02s
- `scripts/check-ios.sh` · passed · 58.3 s
- `scripts/check-backend.sh` · passed · 3.8 s
## Libraries used
none touched
## Notes for Jarvis
No shared files touched. Suggested commit message: "check-ios: break stale locks, skip test diagnostics, delete dead check simulators"

## Checks (run by Ultron)
Passed · 2 of 2 · 2m 17s · 2026-11-14 17:02 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 2m 13s
- `scripts/check-backend.sh` · passed · 3.9 s
