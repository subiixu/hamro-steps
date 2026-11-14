# iOS: fix review findings in Home model, mock service and activity controllers
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-14 14:39 · terminal: s_253ca1b2
Tasks: T-5, T-6, T-7, T-9, T-10
files: ios/HamroSteps/Features/Home/HomeModel.swift, ios/HamroSteps/Services/MockFamilyService.swift, ios/HamroSteps/Features/Activity/WalkButton.swift, ios/HamroSteps/Features/Activity/FeedList.swift, ios/HamroSteps/Features/Activity/NotificationSettingsView.swift, ios/HamroSteps/Services/ActivityMockService.swift, ios/HamroStepsTests/**

## Goal
Fix these review findings, each with a test. Done = `ultron check` green.
- **`handoffs/reviews/2026-11-14-1545-ios-home-logic-fix-second.md`, findings 1–3:**
  1. The mock's `drop()` removes the user's closed-day contributions on leave, remove and delete.
  2. After a sync, call `refresh()`, not `reload()`. Don't touch `HamroStepsApp.swift` (another worker owns it); expose a method on `HomeModel` and say in the handoff which line should call it.
  3. Significant time changes reschedule the midnight wait.
- **`handoffs/reviews/2026-11-14-1429-ios-activity-ui-second.md`, findings 1–3:**
  1. Notification toggles: serialise saves and disable a toggle while it saves.
  2. Reactions: serialise per event, and reconcile against confirmed state.
  3. The walk-limit notice expires at Nepal midnight.

## Context
Read narrowly: grep -n and sed -n ranges only. The two review files are short; read their Findings sections.
- Another worker is editing `HomeView.swift`, `MeView.swift`, `RootView.swift`, `HamroStepsApp.swift`, `Family.swift` and the `members` seed in `MockFamilyService.swift` at the same time. Stay out of those files, and out of that part of the mock.

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
- May touch: the `files:` list (but not the `members` seed in MockFamilyService)
- Must not touch: anything else

## Checks
`ultron check`. If it fails only on the other worker's in-progress files, say so, wait a minute and rerun once.

## Questions first
No questions expected; build straight through.
