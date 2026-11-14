# iOS fix: Nepal-day rollover on Home, zero-step sync, mock closed-day goals
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1545-ios-home-logic-fix.md
## What the user asked
Fix findings 1, 4 and 5 of `handoffs/reviews/2026-11-14-1425-ios-home-mock-second.md` (T-5, T-6), with tests, and hand off the whole uncommitted ios-home-mock phase.
## What changed
- **Rollover (finding 1).** Home now reloads today and the whole week, and opens a fresh live subscription, when:
  - the app comes back to the foreground (`RootView` scenePhase → `home.refresh()`);
  - Nepal midnight passes while the app is active (a timer for the next 18:15 UTC, plus `UIApplication.significantTimeChangeNotification`; it only runs while the scene is active);
  - a live update arrives for a day the loaded week wasn't built for (a safety net if the timer missed it);
  - any successful step sync (`StepSync.onSynced` → `home.reload()`, set in `AppDelegate`), so a late correction updates a closed day's marker.
  `HomeModel` takes an injectable `now` clock and records `loadedDay`. `listen()` re-subscribes when `refresh()` is called, so `HomeView`'s `.task(id:)` didn't need to change.
- **Zero steps (finding 4).** `StepSync` no longer requires a positive day. It sends nothing only when Health returns no day at all in the 7-day window (the "access off" case). A day Health returns as 0 is sent, so correcting a positive value down to 0 now replaces it and updates `lastSyncedAt`. No change was needed to `StepSource` or `HealthKitStepSource`: they already leave out days with no samples.
- **Mock closed days (finding 5).** `MockFamilyService` now mirrors Convex `closeDay` plus `dayContributions`. Each closed day keeps a snapshot of the goal and of the members at that midnight. Days are closed lazily on the first call after Nepal midnight (and, at init, for the 7-day window). A late `syncSteps` replaces the user's contribution in every family that counted them at that close, and the goal stays frozen. `familyWeek` reads snapshots for closed days; today, and any closed day without a snapshot, use live totals against the current goal, the same as `home.ts`. Seeded sample totals are kept as an `unattributed` base, so corrections add on top of them.
## Files
- ios/project.yml — modified
- ios/HamroSteps/Resources/HamroSteps.entitlements — modified
- ios/HamroSteps/App/HamroStepsApp.swift — modified
- ios/HamroSteps/App/RootView.swift — modified
- ios/HamroSteps/App/SessionStore.swift — created
- ios/HamroSteps/Components/Card.swift — modified
- ios/HamroSteps/Components/OrbLoader.swift — modified
- ios/HamroSteps/Features/Family/FamilyView.swift — deleted
- ios/HamroSteps/Features/Today/TodayView.swift — deleted
- ios/HamroSteps/Features/Onboarding/ConnectHealthView.swift — deleted
- ios/HamroSteps/Features/Onboarding/WelcomeView.swift — created
- ios/HamroSteps/Features/Onboarding/HealthPermissionView.swift — created
- ios/HamroSteps/Features/Setup/FamilySetupView.swift — created
- ios/HamroSteps/Features/Setup/InviteCodeView.swift — created
- ios/HamroSteps/Features/Setup/JoinFamilyView.swift — created
- ios/HamroSteps/Features/Home/HomeModel.swift — created
- ios/HamroSteps/Features/Home/HomeView.swift — created
- ios/HamroSteps/Features/Settings/FamilySettingsView.swift — created
- ios/HamroSteps/Features/Me/MeView.swift — modified
- ios/HamroSteps/Health/HealthKitStepSource.swift — modified
- ios/HamroSteps/Health/StepStore.swift — deleted
- ios/HamroSteps/Services/FamilyService.swift — created
- ios/HamroSteps/Services/MockAuthService.swift — created
- ios/HamroSteps/Services/MockFamilyService.swift — created
- ios/HamroSteps/Sync/StepSync.swift — created
- ios/HamroStepsTests/AssetTests.swift — modified
- ios/HamroStepsTests/StepHistoryTests.swift — modified
- ios/HamroStepsTests/TestSupport.swift — created
- ios/HamroStepsTests/StepSyncTests.swift — created
- ios/HamroStepsTests/InviteCodeTests.swift — created
- ios/HamroStepsTests/HomeModelTests.swift — created
- ios/Shared/Models/Family.swift — created
- ios/Shared/Models/InviteCode.swift — created
- ios/Shared/Steps/NepalDay.swift — created
- ios/Shared/Steps/StepSource.swift — modified
- ios/Shared/Steps/MockStepSource.swift — modified
- ios/Shared/UI/Icon.swift — modified
- ios/Shared/UI/Palette.swift — modified
- ios/Shared/SharedAssets.xcassets/Colors/Cheer.colorset/Contents.json — deleted
- ios/Shared/SharedAssets.xcassets/Colors/Streak.colorset/Contents.json — deleted
- ios/Shared/SharedAssets.xcassets/Icons/icon-cheer.imageset/Contents.json — deleted
- ios/Shared/SharedAssets.xcassets/Icons/icon-cheer.imageset/icon-cheer.svg — deleted
- ios/Shared/SharedAssets.xcassets/Icons/icon-fire.imageset/Contents.json — deleted
- ios/Shared/SharedAssets.xcassets/Icons/icon-fire.imageset/icon-fire.svg — deleted
- ios/Shared/SharedAssets.xcassets/Icons/icon-celebrate.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-celebrate.imageset/icon-celebrate.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-chevron-down.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-chevron-down.imageset/icon-chevron-down.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-clock.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-clock.imageset/icon-clock.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-close.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-close.imageset/icon-close.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-copy.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-copy.imageset/icon-copy.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-delete.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-delete.imageset/icon-delete.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-edit.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-edit.imageset/icon-edit.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-health.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-health.imageset/icon-health.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-logout.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-logout.imageset/icon-logout.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-minus.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-minus.imageset/icon-minus.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-organiser.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-organiser.imageset/icon-organiser.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-refresh.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-refresh.imageset/icon-refresh.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-tick.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-tick.imageset/icon-tick.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-user-remove.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-user-remove.imageset/icon-user-remove.svg — created
- handoffs/2026-11-14-1425-ios-home-mock.md — created
- ios/HamroStepsTests/RolloverTests.swift — created
- handoffs/2026-11-14-1545-ios-home-logic-fix.md — created

(Files this brief changed: `ios/HamroSteps/Features/Home/HomeModel.swift`, `ios/HamroSteps/Sync/StepSync.swift`, `ios/HamroSteps/Services/MockFamilyService.swift`, `ios/HamroSteps/App/RootView.swift`, `ios/HamroSteps/App/HamroStepsApp.swift`, `ios/HamroStepsTests/StepSyncTests.swift` and the new `ios/HamroStepsTests/RolloverTests.swift`. The rest are the earlier phase's still-uncommitted files, listed as the brief asked. The view files in that list may also carry the visual worker's concurrent edits.)
## Checks run
`ultron check`: passed · 2 of 2 passed · 2m 03s
- `scripts/check-ios.sh` · passed · 2m 00s
- `scripts/check-backend.sh` · passed · 3.0 s

New tests, which all run in that check and all use injected clocks and isolated `UserDefaults`:
- `HomeRolloverTests`: next refresh at 18:15 UTC; crossing Nepal midnight (Fri 23:45 → Sat 00:05) moves `today`, `loadedDay` and the future flags, and a same-day check fetches nothing; Sunday → Monday gives the 16–22 Nov week; live updates still arrive after a rollover refresh; a live update for a new day reloads the week; a successful sync reloads the week, so a late step shows on a closed day.
- `MockClosedDayTests`: a goal change keeps closed days' goals (including a day closed after an earlier change); a late sync turns a closed day into a hit against its frozen goal; a late sync adjusts only families that counted the user at that midnight (a family created today has nothing to adjust).
- `StepSyncTests.aCorrectionDownToZeroIsSent` and `hasDataCountsOnlyDaysHealthReturned`.

Not checked: real HealthKit on a device, and the real midnight timer or significant-time notification firing in the running app (tests call `refreshIfDayChanged()` directly). No screenshots, since nothing visual changed.
## Libraries used
none touched
## Notes for Jarvis
- While I was working, `scripts/check-ios.sh` was edited by someone else: one run hit "syntax error: unexpected end of file", and it now uses a sim `id` and `-derivedDataPath`. That isn't mine and isn't in my list.
- The Convex phase's `familyTodayUpdates` should key its query on the Nepal day, so `refresh()`'s re-subscribe picks up the new day.
- Suggested commit message: "iOS Home: refresh on Nepal-day rollover, sync explicit zero steps, freeze closed-day goals in the mock backend"

## Checks (run by Ultron)
Failed: scripts/check-backend.sh · 1 of 2 passed · 2026-11-14 14:37 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 1m 44s
- `scripts/check-backend.sh` · exit 1 · 0.6 s

Last 1 lines of `scripts/check-backend.sh`:
```text
convex/users.ts(102,56): error TS2741: Property 'nextAttemptAt' is missing in type '{ refreshToken: string; attempts: number; createdAt: number; }' but required in type '{ attempts: number; createdAt: number; nextAttemptAt: number; refreshToken: string; }'.
```

## Second opinion
Skipped at merge: Blocking finding is mock-only (MockFamilyService drop() keeps contributions); real Convex backend handles it; all 3 findings carried into the iOS Convex-wiring brief (2026-11-14 14:38)

## Checks override
Merged anyway: check-backend red only from the convex-core redo worker's in-progress edits; iOS check passed (2026-11-14 14:38)
