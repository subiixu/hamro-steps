# iOS phase 4a: place walking, status and feed into Home and Me (mock services)
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-14 14:39 · terminal: s_d484ac05
Tasks: T-7, T-8, T-9, T-10
files: ios/HamroSteps/Features/Home/HomeView.swift, ios/HamroSteps/Features/Me/MeView.swift, ios/HamroSteps/App/RootView.swift, ios/HamroSteps/App/HamroStepsApp.swift, ios/Shared/Models/Family.swift, handoffs/screens/**

## Goal
Wire the merged activity components into the app on mock services:
- **Home:** `WalkButton` near the top, a "Set my status" entry, and the `FeedList` below the contributions.
- **`MemberRow`:** `WalkingBadge` and `StatusLabel`.
- **Me:** a "Notifications" row pushing `NotificationSettingsView`.

Done = `ultron check` green, plus screenshots (Home light, dark and accessibility size; Me) from `-screen home -mockSteps` and `-screen me`, saved to `handoffs/screens/2026-11-14-ios-placed-*.png`.

## Context
Read narrowly: grep -n and sed -n ranges only. Read the "For the placement phase" notes in `handoffs/merged/2026-11-14-1429-ios-activity-ui.md` (grep for it).
- `FamilyMember` (in `ios/Shared/Models/Family.swift`) gains `walkingSince`, `walkEndsAt` and `status: MemberStatus?`, matching `docs/contract-activity.md`. The mock `familyToday` data must fill them, so make the minimal edit to `MockFamilyService` sample data only, in the `members` seed.
- Inject `ActivityService` through the environment the way `FamilyService` is (`AppLaunch.services()`).
- **Layout order on Home (relationship first):**
  1. header
  2. ring
  3. WalkButton
  4. "Everyone's steps today" with badges and status
  5. this week
  6. "Family moments" feed
- At accessibility sizes, member rows stack the steps under the name.
- Use a single provider of "now" for walk timers, so screenshots are deterministic.
- Another worker is editing `HomeModel.swift`, `MockFamilyService.swift` (except the seed), `WalkButton.swift`, `FeedList.swift` and `NotificationSettingsView.swift` at the same time. Don't touch those; if you need a change there, say so in the handoff.
- Use your own simulator for screenshots (`xcrun simctl create`), never the shared one.

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
- May touch: the `files:` list, plus the `members` seed in `ios/HamroSteps/Services/MockFamilyService.swift`
- Must not touch: anything else

## Checks
`ultron check`, plus the screenshots.

## Questions first
No questions expected; build straight through.
