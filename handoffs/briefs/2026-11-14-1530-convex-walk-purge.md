# Convex: purge old walks, smaller nudge pages (combined-review follow-up)
worker: claude
model: claude-sonnet-5-5
effort: medium
Tasks: T-7
files: backend/convex/walks.ts, backend/convex/crons.ts, backend/convex/notifications.ts, backend/convex/lib/constants.ts, backend/tests/walks.test.ts, backend/convex/_generated/**

## Goal
1. Walk rows are never deleted, so account deletion (`deleteUserData`, lib/cleanup.ts ~278) will eventually exceed the per-mutation write limit. Add `internal.walks.purgeOld`: delete ended walks whose Nepal day is older than `WALK_RETENTION_DAYS = 7` (put it in lib/constants.ts), batched and self-rescheduling exactly like `internal.feed.purgeOld` (follow backend/convex/feed.ts). Never delete an unended walk. Register a daily cron at 19:45 UTC in crons.ts next to "purge old feed events". Add an index on walks if the query needs one (schema.ts may be touched for that only; add it to your Files list).
2. In notifications.ts set `NUDGE_BATCH = 25` (was 100), so one nudge page stays well inside Convex read limits.

Done = `scripts/check-backend.sh` green, with new tests in backend/tests/walks.test.ts: old ended walks are purged, recent and unended ones kept, and batching continues across pages.

## Context
Read narrowly: grep -n / sed -n ranges, never whole-file cat. Pattern to copy: `purgeOld` in backend/convex/feed.ts and its test in backend/tests/feed.test.ts. Nepal-day helpers live in backend/convex/lib/.

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

## Must not touch
Anything outside the files list (schema.ts only for an index). No git commands.
