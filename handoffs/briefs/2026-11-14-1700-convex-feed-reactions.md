# Convex backend 2b: family feed auto-events and reactions (contract F13–F14)
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-14 14:44 · terminal: s_8a0603a5
after: handoffs/merged/2026-11-14-1645-convex-walks-status.md
Tasks: T-9
files: backend/convex/feed.ts, backend/convex/schema.ts, backend/convex/steps.ts, backend/convex/walks.ts, backend/convex/lib/**, backend/tests/feed.test.ts, backend/convex/_generated/**

## Goal
Implement the "## Feed" and "## Reactions" sections of `docs/contract-activity.md`, with tests. No push yet: 2c adds it. Leave one marked `// 2c: push` call site wherever a push will go (walk_started, family_100, reaction). Done = `scripts/check-backend.sh` green.

## Context
Read narrowly: grep -n / sed -n ranges. Read only those two contract sections, plus "Where phase 2 plugs in" in `handoffs/merged/2026-11-14-1403-convex-core.md` and the Notes in `handoffs/merged/2026-11-14-1645-convex-walks-status.md`.
- **Tables:**
  - `feedEvents`: familyId, type, actorId?, day, createdAt, data. A unique-ish index by (familyId, day, type, actorId) is used to enforce once per (family, actor, day, type).
  - `reactions`: eventId, userId, emoji, with indexes by_event and by_event_user.
- **Event creation:**
  - In `syncSteps`, compare a user's today value before and after. Crossing 5,000 or 10,000 adds `member_5k` / `member_10k` in each of their families.
  - Recompute each family's live total. Crossing 50% or 100% of today's goal adds `family_50` / `family_100` with actor null.
  - Late syncs for closed days don't create events (today only).
  - `walk_started` goes in from `walks.startWalk` (replace its marked comment), one per family, with `data.walkId`.
- **Queries and mutations:**
  - `feed(familyId)`: last 3 Nepal days, newest first, at most 100, with reaction counts as `[{emoji, count}]` (fixed emoji order) and `myReaction`. Each actor carries `{userId, name, avatarColor}`.
  - `react(eventId, emoji)`: same emoji again removes it, a different one replaces it. Emoji outside 👏 ❤️ 🙌 🔥 😄 gives `invalid_emoji`; accept ❤ without VS16 and normalise it to ❤️. An event that doesn't exist or isn't visible gives `not_member`.
- **Cleanup:**
  - Leaving or being removed deletes that member's events in that family and their reactions to that family's events.
  - Account deletion deletes all of their events and reactions.
  - An empty family deleted also deletes its events and reactions.
  - Use the marked spots in `lib/cleanup.ts`.
- Add a daily purge of events older than 7 days. It must go in `crons.ts`, so you may touch it: add one cron line only.

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
- May touch: the `files:` list, plus one line in `backend/convex/crons.ts`
- Must not touch: `ios/`, `docs/`, `users.ts`, `families.ts`, `home.ts`, `package.json`

## Checks
`ultron check` (iOS failures from the iOS workers' in-progress code aren't yours). Tests:
- each event type created once only, including on a second sync crossing the same threshold
- late syncs creating no events
- the feed window and order
- reaction add, remove and replace, and ❤ normalisation
- `invalid_emoji` and `not_member`
- the cleanup paths
- the purge cron

## Questions first
No questions expected; build straight through.
