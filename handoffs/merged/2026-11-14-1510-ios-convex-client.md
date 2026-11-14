# iOS phase 3: real Convex services (auth + family) behind the existing protocols
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1630-ios-convex-client.md
## What the user asked
(T-4, T-5, T-6) Add `ConvexAuthService` and `ConvexFamilyService`, implementing the existing `AuthService` / `FamilyService` protocols against the merged Convex backend. Use only new files plus the SPM entry, with unit tests over a stubbed transport. The app isn't switched over yet.

**Redo (15:17):** fix the 3 findings in the second opinion (`handoffs/reviews/2026-11-14-1510-ios-convex-client-second.md`), each with a test.

**Redo 2 (15:35):** fix the 2 Blocking findings in the second opinion of 15:34, each with tests.

## Redo 2
1. **A queued refresh can't touch a newer session** (Blocking #1).
   - `performRefresh` now checks its captured generation **before** it flushes, reads the Keychain or calls `/auth/refresh`. The check after the response stays.
   - A refresh that finds the session replaced throws a private `superseded` error, before it starts or after its response. `refresh()` catches that and starts over against whatever session exists now. With a new sign-in, the caller gets that session's token. After a sign-out, the caller gets `signedOut` and no backend call is made. So a replacement sign-in is never logged out, and its refresh token is never rotated by a stale task.
   - Test seam: `ConvexSession(refreshWillStart:)` is an optional hook each refresh task awaits before it does anything, so a test can hold a queued refresh. It defaults to `nil`, and `live` doesn't set it.
2. **A Keychain delete that fails no longer brings the session back** (Blocking #2).
   - A new **sign-out marker** is stored outside the Keychain (`SignOutMarkerStoring`; live it's `UserDefaultsSignOutMarker`, key `convex.signOutPending`). `signOut` sets it before `/auth/logout`. `forget` and a revoked refresh (`invalid_token`) set it too.
   - While the marker is set, the Keychain's session doesn't count: `hasStoredSession` is false, `userId` and `cachedUser` are nil, and refresh / `validAccessToken` throw `signedOut`. This holds across restarts.
   - Every read retries the removal, and a backoff loop (1 s doubling to 30 s, on `writeRetrySleep`) keeps retrying too. The marker clears only once both Keychain items are gone.
   - Signing in again while the marker is set: the new session's Keychain write overwrites the old one, and the marker clears when that write lands. The old removal loop is cancelled, so it can't delete the new session.
   - `cachedUser` now also requires the cached person's `userId` to match the stored session.
   - Because the marker is set before the logout call, an app killed mid-logout restarts signed out too.
3. Tests added in `ConvexSessionTests` (all pass):
   - `queuedRefreshStartingAfterASignInLeavesTheNewSessionAlone`: one refresh, of `refresh-2` (the new session's token), nothing logged out, and the Keychain holds `refresh-3`.
   - `queuedRefreshStartingAfterASignOutNeverCallsTheBackend`
   - `failedRemovalWithOfflineLogoutStaysSignedOutThroughRestartsAndRecovers`: offline logout plus a failing delete. Afterwards the session is unusable, `currentUser` / `cachedUser` are nil and `myFamilies` gives `notAuthenticated`. A restart while the delete still fails is signed out with no refresh call. The retry backs off 1 s then 2 s. Once the Keychain recovers, it's emptied and the marker clears, and a restart after that is signed out.
   - `restartMidLogoutDoesNotRestoreTheSession`
   - `signInAfterAFailedRemovalTakesOverTheKeychain`: the new session survives the old retry loop and a restart.
   - Test support: `InMemoryKeychain.removeFailure` (only deletes fail), `InMemorySignOutMarker`, `TestGate`, and a `storageSleeper` in `ConvexHarness` that drives the write and removal retries.

## What changed in redo 1
1. **The SDK's forced refresh now really refreshes** (Blocking #1).
   - When the server rejects a token, ConvexMobile calls `AuthProvider.loginFromCache` through its `fetchToken(forceRefresh: true)` bridge. That call now goes to a new `ConvexSession.refreshRejectedToken()`, which refreshes even when the token has time left.
   - The one exception: a token issued in the last 10 s (`rejectedTokenGrace`) is handed back instead. This stops a backend that keeps rejecting from driving a refresh loop.
   - `login` still installs the current token, refreshed first only when it's within 2 minutes of expiry. `LiveConvexTransport.authenticate()` now calls `client.login()` instead of `client.loginFromCache()`, so `loginFromCache` is left to mean "the server rejected the token".
2. **Sign-out can't race a refresh any more** (Blocking #2).
   - `signOut` sets a `signingOut` flag before it waits on `/auth/logout`. Until the logout finishes, nothing can load the session from the Keychain (`hasStoredSession` is false, `userId` is nil, `cacheUser` does nothing), and `refresh` / `validAccessToken` throw `signedOut`.
   - When the logout returns, the session ends again: in-memory state is cleared and the generation is bumped, then the Keychain is cleared.
   - A refresh already in flight when sign-out starts is still dropped by the generation check, and the token pair it rotated to is logged out.
   - A sign-in that happens during the logout keeps its new session. Sign-out sees the generation has moved on and leaves the new session alone.
3. **A failed Keychain write of a rotated token is retried** (Should fix #3).
   - `keep()` stores the new session as `pendingWrite` and tries the write. If the write fails, it schedules a retry loop (1 s, then doubling up to 30 s) until the write lands.
   - Every `validAccessToken` and every refresh also tries the pending write first.
   - Sign-out and `forget` drop the pending write and stop the retry loop.
   - The retry sleep is injectable (`writeRetrySleep`, which defaults to `sleep`) so a test can drive it on its own.

Everything from the first pass is unchanged: the Keychain session, the refresh 2 minutes early and on `invalid_token`, coalesced refreshes, only a 401 signs out, the cached `me()` at launch, the family mappings, `ConvexError` code decoding, the `familyToday` subscription, and the delete outcomes.

## Files
- ios/project.yml — modified (ConvexMobile package + dependency, `INFOPLIST_FILE`, `CONVEX_URL`/`CONVEX_SITE_URL` placeholders, `EXCLUDED_ARCHS[sdk=iphonesimulator*]: x86_64`)
- ios/HamroSteps/Services/Convex/Info.plist — created
- ios/HamroSteps/Services/Convex/ConvexConfig.swift — created
- ios/HamroSteps/Services/Convex/Keychain.swift — created
- ios/HamroSteps/Services/Convex/AuthEndpoints.swift — created
- ios/HamroSteps/Services/Convex/ConvexSession.swift — created (redo: sign-out guard, pending write retry, `refreshRejectedToken`; redo 2: generation check before refresh, sign-out marker, removal retry)
- ios/HamroSteps/Services/Convex/ConvexTransport.swift — created
- ios/HamroSteps/Services/Convex/LiveConvexTransport.swift — created (redo: `loginFromCache` forces a refresh; `authenticate` uses `client.login()`)
- ios/HamroSteps/Services/Convex/ConvexConnection.swift — created
- ios/HamroSteps/Services/Convex/ConvexFamilyService.swift — created
- ios/HamroSteps/Services/Convex/ConvexAuthService.swift — created
- ios/HamroSteps/Services/Convex/ConvexServices.swift — created (redo 2: passes `UserDefaultsSignOutMarker`)
- ios/HamroSteps/Services/Convex/SignOutMarker.swift — created (redo 2)
- ios/HamroStepsTests/ConvexTestSupport.swift — created (redo: logout gate in `FakeAuthEndpoints`; redo 2: `removeFailure`, `InMemorySignOutMarker`, `TestGate`, harness `marker` / `storageSleeper`)
- ios/HamroStepsTests/ConvexSessionTests.swift — created (redo: 8 new tests; redo 2: 5 more)
- ios/HamroStepsTests/ConvexServiceTests.swift — created

## Checks run
**Redo 2. `ultron check` in the worktree is still red, still only because of the base commit.** The worktree is on a7a60e7, where `ios/Shared/UI/Icon.swift` has the duplicate `case clock`. Every error below is in `Icon.swift`; the Convex files compile.

```
## Checks run
`ultron check`: FAILED · 0 of 2 passed · 2m 47s
- `scripts/check-ios.sh` · exit 65 · 2m 47s
  Testing failed:
  	Ambiguous use of 'clock'
  	Raw value for enum case is not unique
  	Invalid redeclaration of 'clock'
  	'Icon' declares raw type 'String', but does not conform to RawRepresentable and conformance could not be synthesized
  	Cannot find 'rawValue' in scope
  	Testing cancelled because the build failed.
  ** TEST FAILED **
- `scripts/check-backend.sh` · not run (an earlier check failed)
```

What I checked instead (redo 2):
- **Full iOS suite on current `main` (f6a23fe) plus this branch.** I extracted `git archive main ios scripts` into my scratchpad, patched in this branch's `project.yml` diff (it applied cleanly) and copied in the Convex sources and tests. Then I ran `scripts/check-ios.sh` there: exit 0, **170 tests (247 runs with parameters) passed, 0 failed** (from the xcresult summary). That includes the 5 new tests, each finishing in under 0.06 s. The run took 26 min, almost all of it simulator start-up before the first test, not the tests themselves.
- **Backend:** `scripts/check-backend.sh` run on its own in the worktree passed: 61 tests in 4 files (no backend changes).

Not checked:
- Nothing ran against a real Convex deployment, real Sign in with Apple, or the real Keychain. Removal failures are simulated with the in-memory fake.
- I didn't do repeated flakiness runs in redo 2, because the simulator start-up made each run very slow. The new tests drive every wait with gates and sleepers, not real time, except one 50 ms settle in `signInAfterAFailedRemovalTakesOverTheKeychain`.

## Libraries used
none touched (Hugeicons and Thinking Orbs aren't involved; there's no UI in this change)

## Notes for Jarvis
- **Rebase onto main before committing/merging.** That brings in the Icon/cheer fix. After that, `ultron check` should be green, which is what the scratch run on main shows. `ios/project.yml` merges cleanly with main's two signing lines.
- **Dependency:** ConvexMobile 0.8.2 is added as you approved. Its Rust xcframework is about 147 MB and has no x86_64 simulator slice, hence `EXCLUDED_ARCHS[sdk=iphonesimulator*]: x86_64`. The first resolve downloads the binary.
- **Shared-file edit:** `ios/project.yml` gets the package and dependency entries, `INFOPLIST_FILE: HamroSteps/Services/Convex/Info.plist` (merged with the generated plist), the two URL placeholders, and the arch exclusion.
- **Environment:** set `CONVEX_URL` (`https://<name>.convex.cloud`) and `CONVEX_SITE_URL` (`https://<name>.convex.site`) per environment.
- **The swap in `AppLaunch.services()` (HamroStepsApp.swift)**, for whoever owns that file. Put it after the `#if DEBUG` block, so `-screen`, `-newUser` and `-signedOut` keep the mocks:
  ```swift
  #if DEBUG
  let useMocks = args.contains("-signedOut") || args.contains("-newUser") || screen != nil
  #else
  let useMocks = false
  #endif
  if !useMocks, let config = ConvexConfig() {
      let convex = ConvexServices.live(config: config)
      return AppServices(family: convex.family, auth: convex.auth, steps: stepSource())
  }
  ```
- **Behaviour to know (redo 2):** the sign-out marker lives in `UserDefaults` (`convex.signOutPending`), so it goes when the app is deleted while the Keychain stays. A reinstall after a delete that never succeeded could find the old session. By then `/auth/logout` normally revoked it, so the first refresh signs out. If the logout also failed offline, that one session could come back on reinstall. A failed offline logout isn't retried later; the brief asked only for local invalidation.
- **Behaviour to know:**
  - `SessionStore.refreshFamilies` signs out on `notAuthenticated`. The Convex layer only throws that when there's no session or the backend revoked it; offline gives `unavailable("network")`.
  - The Keychain survives app deletion, so a reinstall opens signed in. There's no first-launch wipe (see the first pass).
- **Later:** `familyToday` members on main now carry `status`, which `FamilyMember` ignores for now. The activity service still runs on its mock.
- **Suggested commit message:** `iOS: Convex auth and family services behind the existing protocols (Keychain session, refresh 2 min early and on invalid_token or SDK rejection, stale refreshes never touch a newer session, sign-out survives failed Keychain deletes via a persisted marker, retried Keychain writes), ConvexMobile 0.8.2`

## Checks override
Merged anyway: red only from the worktree base's duplicate Icon.clock case, fixed on main; check-ios re-run on main after merge (2026-11-14 16:40)
