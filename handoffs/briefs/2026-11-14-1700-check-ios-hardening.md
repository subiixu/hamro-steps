# check-ios.sh: break stale locks, skip slow failure diagnostics
worker: claude
model: sonnet
effort: medium
started: 2026-11-14 16:55 · terminal: s_e1cfeb1b
files: scripts/check-ios.sh

## Goal
`scripts/check-ios.sh` never blocks on a lock left by a killed run, and a failing test run ends in about 2 minutes instead of running past the 15-minute cap.

## Context
Today a killed check (SIGKILL from the 15-min cap, so the EXIT trap never ran) left `$TMPDIR/hamro-check-<key>.lock` behind, and every later check on that checkout waited 15 minutes on it. Separately, when a test fails, `xcodebuild test` runs `simctl diagnose` for up to 10 minutes, which pushes the run past the cap. The leftover simulator `hamro-check-<pid>` also stays booted.

## Libraries and design rules
<!-- written by jarvis spawn from `ultron knowledge show`; replaced on every spawn -->
### Libraries

- **Hugeicons** (icons): Use Hugeicons for every icon in the UI, keeping one style and stroke weight throughout and colouring with currentColor. No emoji and no hand-drawn SVG icons.
- **Thinking Orbs** (loading): Use Thinking Orbs for every AI "thinking" or loading state instead of a spinner. On web render <ThinkingOrb state="..." size={64|20} /> and pick the state that matches the activity (e.g. searching, composing). Set up: Web: `npm install thinking-orbs`; Mac: `Swift Package Manager: add https://github.com/Jakubantalik/Libraries.dev (branch main), product ThinkingOrbsKit`; iOS: `Swift Package Manager: add https://github.com/Jakubantalik/Libraries.dev (branch main), product ThinkingOrbsKit`. iOS: The page doesn't explicitly say the Swift package supports iOS or macOS, and it gives no CocoaPods option. Mac: The page doesn't explicitly say the Swift package supports macOS; SwiftUI support is implied only. Web: Requires React 18 or newer; the page lists only an npm install line.

### Releasing

- Pushing the default branch isn't a release: each project's Jarvis
  commits and pushes its own main (a plain fast-forward) and never leaves
  the push for the user, unless the project marks main as a release
  (`gates.default_branch_is_release: true`).
- Releasing is the user's: Ultron blocks agents from tagging, force-pushing,
  deploying to production or submitting to a store. Ask the user to do it.
- Every release gets a changelog entry in the user's voice: what changed for
  the person using the app, not which files moved.
- Version numbers are semantic. A release that changes stored data bumps
  the minor version and ships a migration with a rollback note.
- Preview or staging deployments are fine without the user; say where the
  preview is in the handoff.

## Scope
- May touch: scripts/check-ios.sh only.
- Must not touch: anything else.

## Phase
1. Lock: after `mkdir "$LOCK"` succeeds, write `$$` to `$LOCK/pid`. While waiting, if `$LOCK/pid` names a process that's no longer alive (`kill -0` fails), or the lock dir has no pid file and is older than 30 minutes, remove it and retry. The trap removes `$LOCK/pid` before `rmdir`.
2. Add `-collect-test-diagnostics never` to the `xcodebuild test` call.
3. Before creating its simulator, delete any `hamro-check-<pid>` simulators whose pid is dead (parse the names from `xcrun simctl list devices`). Don't touch other simulators.
Keep it bash 3.2-compatible (macOS /bin/bash).

## Checks
`bash -n scripts/check-ios.sh`, then `scripts/check-ios.sh` passes. Then prove the stale lock: `mkdir $TMPDIR/hamro-check-<key>.lock && echo 999999 > …/pid`, run the script, and it must start building within a few seconds. Put the timings in the handoff.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
