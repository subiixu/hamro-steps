# iOS: ConvexActivityService + switch the app to the live Convex services
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1720-ios-convex-activity.md
## What the user asked
Tasks: T-4, T-5, T-6, T-7, T-9. Put walks, status, feed, reactions and notification settings on Convex, make the device register/unregister calls return as soon as they're cancelled, and run the app on Convex (auth, family, activity) outside the Debug mock launches.

## What changed
- **`ConvexActivityService`** covers all 10 `ActivityService` methods: `walks:startWalk/stopWalk`, `status:setStatus/clearStatus`, `feed:feed`, `feed:react`, `notifications:notificationPrefs/setNotificationPrefs/registerDevice/unregisterDevice`. It follows the `ConvexFamilyService` pattern (`connection.run`, so it gets the same refresh and retry on `invalid_token`).
  - `setStatus` and `setNotificationPrefs` send only the fields that are set, never `null`. The backend validators are `v.optional`, so a `null` would be rejected.
  - Errors: the contract codes (`already_walking`, `walk_limit_reached`, `invalid_status`, `invalid_expiry`, `invalid_emoji`, `not_member`) come back as `ActivityError`. Anything else stays the connection's `FamilyServiceError` (`.notAuthenticated`, `.unavailable("server" | "client" | "network" | <unknown code>)`).
  - Feed: the backend sends `actor.name: null` for someone who hasn't given a name yet. `FeedActor.name` is a non-optional `String`, so that would have failed the **whole feed**. A private wire decoder turns it into `""`, the way `familyToday` members already work. Everything else decodes as `FeedEvent.init(from:)` does: unknown types become `.unknown`, emoji outside the set are dropped, a plain ❤ counts as ❤️.
- **Cancellation contract (Phase 2):** `registerDevice` and `unregisterDevice` go through `ConvexActivityService.returningOnCancel`. The call runs in its own task, raced against a `withTaskCancellationHandler` and a continuation that's resumed only once. When the caller is cancelled, it throws `CancellationError` right away and cancels the inner call without waiting for it. A call that's already cancelled sends nothing. So a transport that ignores cancellation can no longer hang `PushRegistrar`'s serial queue. That was the open finding from the push review.
- **`ConvexServices`** now also has `activity`.
- **`AppLaunch.services()`** uses `ConvexServices.live(config:)` for family, auth and activity, plus `stepSource()` and `now: { .now }`, unless:
  - it's a Debug mock launch (`-signedOut`, `-newUser` or `-screen`, see `AppLaunch.isMockLaunch`), or
  - `ConvexConfig()` is nil.

  In those cases it falls back to the old mock setup, now in `mockServices()`, with `SampleFamilyActivity` kept for it. Release builds are never a mock launch. `-mockSteps` / `-mockStepsLoading` still only swap the step source, so they combine with Convex. I updated the doc comments to match.

## Files
- ios/HamroSteps/Services/Convex/ConvexActivityService.swift — created
- ios/HamroSteps/Services/Convex/ConvexServices.swift — modified
- ios/HamroSteps/App/HamroStepsApp.swift — modified (only `AppLaunch.services()`, plus the new `isMockLaunch` / `mockServices()` and doc comments on `AppServices`, `AppLaunch` and `SampleFamilyActivity`)
- ios/HamroStepsTests/ConvexActivityServiceTests.swift — created

## Checks run
`ultron check`: passed · 2 of 2 passed · 1m 13s
- `scripts/check-ios.sh` · passed · 1m 06s
- `scripts/check-backend.sh` · passed · 7.0 s

Also ran:
- `xcodebuild test -only-testing:HamroStepsTests/ConvexActivityServiceTests` on a private iPhone 17 Pro simulator (iOS 26.5): **14 tests (19 cases) passed**.
  - Args per method, including the omitted-nil fields and the `production` environment.
  - Decoding of `startWalk`, prefs and the feed (null actor name, no actor, unknown type, unknown and plain-heart emoji, missing `data`).
  - Each contract code becomes `ActivityError`; each method maps its errors; signed out → `notAuthenticated`; `invalid_token` refresh and retry.
  - Device calls against a stub transport that never answers, even when cancelled: `register` and `unregister` both return `CancellationError` well under 100 ms (the test asserts `< 100ms`). An already-cancelled call sends nothing. Normal results and errors still pass through.
- **No-flags simulator launch** (Debug build, `ConvexURL` = harmless-dolphin-642 in the built Info.plist): **Welcome** shows the app icon, "Hamro Steps", the tagline, the three feature rows, **Continue with Apple**, Privacy policy, and the Debug-only "Use the sample account (debug)" link.

Not checked:
- No real call against the dev deployment from the app: Sign in with Apple can't complete in the simulator, so nothing past Welcome ran on Convex.
- I didn't deliberately break the race to watch the cancellation test fail. Without the race, that test would hang rather than fail.

## Libraries used
none touched

## Questions for the user
none

## Notes for Jarvis
- **Debug sample-account button on live Convex:** `WelcomeView`'s "Use the sample account (debug)" calls `signIn(token: "debug-token", …)`. On a no-flags Debug launch that now goes to the real `/auth/apple`, which will reject it, so it only works under the mock launches now. I didn't touch it because views were out of scope. Options: hide it unless `AppLaunch.isMockLaunch`, or drop it. Worth a tiny follow-up brief.
- **`FeedActor.name`:** better to make it `decodeIfPresent(...) ?? ""` in `Shared/Models/Activity.swift` itself (not in my file list). The service's wire decoder then becomes redundant, though harmless.
- No dependencies added, no shared-file edits beyond `HamroStepsApp.swift`, which the brief named.
- Suggested commit message:
  `iOS: ConvexActivityService for walks, status, feed, reactions and notifications; device calls return on cancellation; app runs on Convex outside Debug mock launches`

## Checks (run by Ultron)
Passed · 2 of 2 · 2m 20s · 2026-11-14 17:47 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 2m 11s
- `scripts/check-backend.sh` · passed · 8.7 s

## Second opinion
Skipped at merge: second opinion ran at 17:5x on this code (Has concerns, test-only findings, folded into briefs/2026-11-14-1800-ios-cleanup.md); only the handoff's Ultron checks section changed since (2026-11-14 17:48)
