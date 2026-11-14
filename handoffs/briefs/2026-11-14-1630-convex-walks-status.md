# Convex backend 2a: walks and status (contract F9–F12)
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-14 14:40 · terminal: s_c2e1f17e
after: handoffs/merged/2026-11-14-1403-convex-core.md
Tasks: T-7, T-8
files: backend/convex/walks.ts, backend/convex/status.ts, backend/convex/schema.ts, backend/convex/home.ts, backend/convex/lib/cleanup.ts, backend/convex/lib/**, backend/tests/walks.test.ts, backend/tests/status.test.ts, backend/convex/_generated/**

## Goal
Implement the **Walks** and **Status** sections of `docs/contract-activity.md` in Convex, with convex-test coverage. Done = `scripts/check-backend.sh` green.

## Context
Read narrowly: grep -n / sed -n ranges. In `docs/contract-activity.md`, read only "## Walks" and "## Status". For the API and schema of phase 1, read "API reference" and "Where phase 2 plugs in" in `handoffs/merged/2026-11-14-1403-convex-core.md`.
- **Walks:**
  - Add a `walks` table: userId, startedAt, endsAt, endedAt?, nepalDay; indexes by_user_open and by_user_day.
  - `startWalk` / `stopWalk` (auth via the existing helper). Enforce the 3-per-Nepal-day limit and `already_walking`.
  - Auto-stop with `ctx.scheduler.runAt(endsAt, internal.walks.autoStop, {walkId})`. It's idempotent, since a walk may already be stopped.
  - **Don't send pushes or create feed events yet.** Phases 2b and 2c add those. Leave one clearly marked `// 2b/2c: feed event + push` call site in `startWalk`.
- **Status:**
  - Add a `statuses` table: one row per user, with preset?, text?, expiresAt, updatedAt.
  - `setStatus` / `clearStatus` validate per the contract: exactly one of preset/text; text trimmed and ≤ 30 UTF-16 units (`.length`); expiresAt in the future and ≤ now + 7 days, default now + 24 h. Errors: `invalid_status`, `invalid_expiry`.
- **`familyToday`:** each member gains `walkingSince`, `walkEndsAt` (open walk, not past endsAt) and `status` (null when expired), read with indexes.
- **Cleanup:** account deletion removes the user's walks and status. Leaving a family needs nothing extra, because walks and status are per user.

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
- May touch: the `files:` list
- Must not touch: `ios/`, `docs/`, `backend/convex/families.ts`, `steps.ts`, `users.ts`, `crons.ts`, `package.json`

## Checks
`ultron check` (an iOS failure from the iOS workers' in-progress code isn't yours; say so). Tests:
- the walk limit across Nepal midnight
- `already_walking`
- `stopWalk` as a no-op
- autoStop at 2 h, and idempotent
- status validation (a 30 vs 31 char string, emoji counted as UTF-16, both or neither field, expiry bounds, the default 24 h)
- `familyToday` showing walking and status, and hiding an expired status
- account deletion removing walks and status

## Questions first
No questions expected; build straight through.
