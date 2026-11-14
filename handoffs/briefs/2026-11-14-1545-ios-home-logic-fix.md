# iOS fix: Nepal-day rollover on Home, zero-step sync, mock closed-day goals
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-14 14:26 · terminal: s_59da81c5
Tasks: T-5, T-6
files: ios/HamroSteps/Features/Home/HomeModel.swift, ios/HamroSteps/Sync/StepSync.swift, ios/HamroSteps/Services/MockFamilyService.swift, ios/HamroSteps/App/*.swift, ios/HamroStepsTests/**

## Goal
Fix findings 1, 4 and 5 of `handoffs/reviews/2026-11-14-1425-ios-home-mock-second.md`. Done = `ultron check` green with the new tests.

## Context
Read narrowly: `grep -n` / `sed -n` ranges only; don't cat whole files. The review file is short, so read findings 1, 4 and 5 there.
- The code is from the unmerged handoff `handoffs/2026-11-14-1425-ios-home-mock.md`; its files are uncommitted in the checkout.
- **1. Rollover.** Reload `familyToday` + `familyWeek` (re-subscribe) when the app comes to the foreground, when the Nepal day changes (`NepalDay` helper; schedule a refresh at the next 18:15 UTC while the app is active; also handle `UIApplication.significantTimeChangeNotification`), and after a 7-day sync. Tests: crossing Nepal midnight, and Sunday → Monday giving a new week.
- **4. Zero steps.** Distinguish "HealthKit returned no data" (don't send) from an explicit 0 bucket (send it). Test that correcting a positive value to 0 is sent.
- **5. Mock.** Closed days keep the goal frozen at that midnight, and late syncs adjust closed totals like the backend does (see the "Steps" and "Home" bullets in `handoffs/2026-11-14-1403-convex-core.md`). Test a goal change and a late correction.
- Another worker is fixing visuals in the view files at the same time, so touch only the files in `files:`.
- **Handoff rule:** your handoff's `## Files` list must include **every file listed in `handoffs/2026-11-14-1425-ios-home-mock.md`'s Files section** (still uncommitted) plus your own. Your merge commits that whole phase.

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
- Must not touch: `ios/HamroSteps/Features/**/*View*.swift`, `ios/Shared/**`, `backend/`, `docs/`

## Checks
`ultron check`. If `check-ios` fails only on the visual worker's in-progress view edits, say so and rerun once after a minute.

## Questions first
No questions expected; build straight through.
