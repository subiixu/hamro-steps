# iOS: ConvexActivityService + switch the app to the live Convex services
worker: claude
model: claude-opus-5-5
effort: high
Tasks: T-4, T-5, T-6, T-7, T-9
files: ios/HamroSteps/Services/Convex/ConvexActivityService.swift, ios/HamroSteps/Services/Convex/ConvexServices.swift, ios/HamroSteps/App/HamroStepsApp.swift, ios/HamroStepsTests/ConvexActivityServiceTests.swift

## Goal
A Release build (and a Debug build launched without `-screen`, `-newUser`, `-signedOut`) runs entirely on Convex: auth, family and activity. `ConvexActivityService` implements every method of `ActivityService` (ios/HamroSteps/Services/ActivityService.swift) against the backend, with unit tests over the stubbed transport. Device calls honour cancellation promptly (see Phase 2).

## Context
- Copy the pattern of `ios/HamroSteps/Services/Convex/ConvexFamilyService.swift` (the `query`/`mutation` helpers over `ConvexConnection`, error mapping) and its tests in `ios/HamroStepsTests/ConvexServiceTests.swift` + `ConvexTestSupport.swift` (stub transport).
- Backend functions (read their `args` validators and return shapes with `sed -n`): `walks:startWalk`, `walks:stopWalk` (backend/convex/walks.ts); `status:setStatus`, `status:clearStatus` (status.ts); `feed:feed` query, `feed:react` (feed.ts); `notifications:registerDevice`, `notifications:unregisterDevice`, `notifications:notificationPrefs`, `notifications:setNotificationPrefs` (notifications.ts). Match the Swift model types already in ActivityService.swift; don't change the protocol.
- Push merged in handoffs/merged/2026-11-14-1600-ios-push.md: `PushRegistrar` runs register/unregister/sign-out on one serial queue and cancels a device call after its timeout. Its review's open finding: a device call that ignores cancellation would hang that queue.
- The swap the Convex client handoff suggested (handoffs/merged/2026-11-14-1510-ios-convex-client.md, "The swap in AppLaunch.services()") is stale: `AppServices` now also takes `activity` and `now`. `CONVEX_URL` / `CONVEX_SITE_URL` are already set in ios/project.yml (dev deployment).
Read narrowly: grep -n and sed -n line ranges, never whole-file cat.

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
- May touch: the files in `files:` above.
- Must not touch: backend/, ios/HamroSteps/Push/**, SessionStore.swift, RootView.swift, the views, project.yml.
- Shared: HamroStepsApp.swift (only `AppLaunch.services()` and what it needs).

## Phase
1. `ConvexActivityService` for every protocol method, tests per method (args sent, decoding, error mapping).
2. Cancellation contract: `registerDevice` and `unregisterDevice` return (throwing `CancellationError`) as soon as their task is cancelled, even if the transport call never returns. Race the call against cancellation (e.g. `withTaskCancellationHandler` + a continuation that resumes once). Test with a stub transport that never answers: cancel, and the call must return within 100 ms.
3. `ConvexServices` gains `activity`; `AppLaunch.services()` uses `ConvexServices.live` when not in a mock launch (keep the `#if DEBUG` mock paths and `SampleFamilyActivity` for them) and `ConvexConfig()` is non-nil; `now: { .now }`.

## Checks
`ultron check` green; paste the result. Also launch once in the simulator with no flags and say what Welcome shows (the real Sign in with Apple can't complete in the simulator; that's fine).

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
