# Steps history backend: home:familyHistory query
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-17 12:42 · terminal: s_d4668198
Tasks: T-44 (part 1 of 2)
files: backend/convex/home.ts, backend/convex/lib/*.ts, backend/tests/history.test.ts

## Goal
A new Convex query `home:familyHistory` returns a family's daily totals vs goal for a range of days, so the iOS History screen can draw a chart and trends. The contract below is fixed: an iOS worker is building against it right now, so don't rename anything.

## Contract (build exactly this)
`home:familyHistory({ familyId: Id<"families">, days: number })`
- `days` must be 7, 30 or 90; anything else throws the project's invalid-argument error (see `lib/errors.ts`, copy how other functions reject bad args).
- Caller must be a member (`requireMember`, same as `familyWeek`): outsiders get `not_member`.
- Returns `{ today: string, days: Array<{ day: string, total: number, goal: number, hit: boolean, isBeforeFamily: boolean }> }`
- `days` covers **2 × N** Nepal days ending with today (inclusive), **oldest first**. The client shows the last N and compares them with the N before.
- Per day, the same rules as `familyWeek` (`backend/convex/home.ts:72`): a closed day uses its `familyDays` snapshot (frozen goal); today, and closed days with no snapshot, use the live total against the current goal. Days before the family's created day: `isBeforeFamily: true`, `total: 0`, `hit: false`, current goal, **no total computed** (cheap for 180-day ranges).

## Done so far
Nothing for history. `familyWeek` (home.ts:72) already does the per-day logic for one week.

## Remaining
- Pull the per-day logic out of `familyWeek` into one helper both queries use (in home.ts or `lib/totals.ts`), so the two can't disagree. `familyWeek`'s output must not change.
- Add `familyHistory` in `backend/convex/home.ts`.
- `backend/tests/history.test.ts` (copy the setup in `backend/tests/steps.test.ts:126`, "closing days and familyWeek"): 2N entries oldest first ending today; snapshot day uses frozen goal; today live; before-family days flagged; days=5 rejected; outsider gets not_member.

## Dead ends
- Per-person history isn't needed here: the iOS "Me" tab reads HealthKit on the phone. Don't add a per-user query.
- No ranking or per-member breakdown in this response (PRD: no ranking inside a family).

## Acceptance
cd backend && npx vitest run tests/history.test.ts

## File scope
- May touch: backend/convex/home.ts, backend/convex/lib/*.ts, backend/tests/history.test.ts
- Must not touch: backend/convex/schema.ts, ios/**, anything else
- Don't deploy to Convex; Nayo does that after merge.

## Context
Read narrowly (grep -n, sed -n ranges). Nepal-day helpers: `backend/convex/lib/nepalDay.ts` (`addDays`, `nepalDay`).

## Libraries and design rules
<!-- written by nayo spawn from `araniko knowledge show`; replaced on every spawn -->
### Libraries

- **Transitions.dev** (motion): Use Transitions.dev for UI transitions such as modals, toasts, tooltips, accordions, toggles and card resizes, instead of hand-rolling animations. Pick the matching effect from its library (CSS or React) and keep it consistent across the project. iOS: Not supported; the page mentions only CSS and React. Mac: Not supported; the page mentions only CSS and React. Web: Some effects are Pro only and need a subscription. Web, Mac and iOS projects only.
- **Hugeicons** (icons): Use Hugeicons for every icon in the UI, keeping one style and stroke weight throughout and colouring with currentColor. No emoji and no hand-drawn SVG icons. iOS: The page lists no native iOS package (no Swift Package Manager or CocoaPods). Mac: The page lists no native macOS package (no Swift Package Manager or CocoaPods). Web: Pro icons need a paid licence; only part of the set is free.
- **Thinking Orbs** (loading): Use Thinking Orbs for every AI "thinking" or loading state instead of a spinner. On web render <ThinkingOrb state="..." size={64|20} /> and pick the state that matches the activity (e.g. searching, composing). Set up: Web: `npm install thinking-orbs`; Mac: `Swift Package Manager: add https://github.com/Jakubantalik/Libraries.dev (branch main), product ThinkingOrbsKit`; iOS: `Swift Package Manager: add https://github.com/Jakubantalik/Libraries.dev (branch main), product ThinkingOrbsKit`. iOS: The page doesn't explicitly say the Swift package supports iOS or macOS, and it gives no CocoaPods option. Mac: The page doesn't explicitly say the Swift package supports macOS; SwiftUI support is implied only. Web: Requires React 18 or newer; the page lists only an npm install line.

### Releasing

- Agents release, deploy, tag and upload (TestFlight, App Store,
  production) when the work calls for it, and say in the handoff what was
  shipped and where. Araniko blocks none of it.
- Each project's Nayo commits and pushes its own main.
- Every release gets a changelog entry in the user's voice: what changed for
  the person using the app, not which files moved.
- Version numbers are semantic. A release that changes stored data bumps
  the minor version and ships a migration with a rollback note.

### Security basics

- No secrets in code, logs or commit history. Use the environment or a keychain.
- Check every input that crosses a boundary: forms, files, network, other processes.
- Give each part only the access it needs.
- Never turn off a security check to make something work.

## Checks
`scripts/check-backend.sh` (typecheck + all convex-test tests) must pass.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
