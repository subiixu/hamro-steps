# check-ios.sh: break a stale lock atomically
worker: opencode
effort: low
started: 2026-11-14 18:36 · terminal: s_b247e3ad
files: scripts/check-ios.sh

## Goal
In `scripts/check-ios.sh`, the stale-lock break (line 21) checks then `rm -rf "$LOCK"`, so two waiting runs can both judge it stale and one can delete the lock the other just took. Make the break atomic: `mv "$LOCK" "$LOCK.stale.$$" 2>/dev/null` and only if that mv succeeds, `rm -rf` the moved dir and `continue`; if the mv fails, someone else broke it, so just loop again. Done = that change, nothing else.

## Context
Lock code is lines 6–26 of `scripts/check-ios.sh` (`sed -n 1,30p`). Keep the existing mkdir-lock, pid file, 30-min rule, 20-min wait and EXIT trap as they are.

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
- May touch: scripts/check-ios.sh (lock block only)
- Must not touch: everything else

## Checks
`bash -n scripts/check-ios.sh`, then `scripts/check-ios.sh 2>&1 | tail -15` (must pass).

## Questions first
None expected; build straight through and hand off.
