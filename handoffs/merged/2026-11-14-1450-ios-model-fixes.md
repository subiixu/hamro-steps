# iOS: fix review findings in Home model, mock service and activity controllers
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1615-ios-model-fixes.md
## What the user asked
Fix findings 1–3 of `reviews/2026-11-14-1545-ios-home-logic-fix-second.md` and findings 1–3 of `reviews/2026-11-14-1429-ios-activity-ui-second.md`, each with a test (T-5, T-6, T-7, T-9, T-10).

## What changed
- **Mock: leaving, removal and account deletion** (1545 #1): `drop()` now removes the user's contributions from every closed day of that family. Frozen goals stay. Later syncs no longer reach that family because the late-sync loop only updates days where the user still has a contribution. Rejoining doesn't put the user back into past closes. Added a test-only `actAs(_:)` so tests can sync as another seeded member.
- **Home after a sync** (1545 #2): new `HomeModel.syncFinished()` calls `refresh()`, which reloads and re-opens the live subscription. I did not edit `HamroStepsApp.swift`: **line 32 should become `stepSync.onSynced = { await home.syncFinished() }`** (it currently calls `home.reload()`).
- **Clock changes** (1545 #3): `watchDayChanges` cancels and recomputes the midnight wait on every significant time change, not only when the day changed. `HomeModel.init` takes an optional `sleep:` closure (defaults to `Task.sleep`) so tests can see the requested wait. Existing call sites don't change.
- **Notification switches** (1429 #1): saves are serialised per switch. A switch is disabled while its save is in flight (`isSaving(_:)`, `.disabled` on the Toggle), and a tap on it during that time is ignored. Other switches save independently.
- **Reactions** (1429 #2): reactions to one event go to the server one at a time. The model keeps the last confirmed event plus a queue of pending taps, and the event on screen is always confirmed + pending. A refused tap drops out without undoing a later tap that saved. While an event has taps pending, a feed `load()` keeps that event's local copy instead of overwriting it.
- **Walk limit** (1429 #3): `WalkController` records when it got `walk_limit_reached`. `notice` stops being `.limitReached` once the Nepal day changes. `sync(...)` and `start()` also clear a stale limit, and `expireStaleNotice()` is public so it can be called on foreground. `init` takes an optional `now:`.
- **Pre-existing build break in FeedList** (outside the findings): the committed `FeedList.swift` used `Icon.cheer` and the `.cheer` colour, and neither exists, so the app didn't build. I changed the empty-feed icon to `Icon.celebrate` with `.goal`, the same pair Home uses for "goal reached".

## Files
- ios/HamroSteps/Services/MockFamilyService.swift — modified (**shared**: it also holds the other worker's uncommitted walking/status seed edits, see Notes)
- ios/HamroSteps/Features/Home/HomeModel.swift — modified
- ios/HamroSteps/Features/Activity/NotificationSettingsView.swift — modified
- ios/HamroSteps/Features/Activity/FeedList.swift — modified
- ios/HamroSteps/Features/Activity/WalkButton.swift — modified
- ios/HamroStepsTests/RolloverTests.swift — modified (3 mock tests: leaving, removal, account deletion, each followed by a late sync)
- ios/HamroStepsTests/HomeDayWatchTests.swift — created (a sync across midnight with a day-pinned subscription; a clock jump within the day re-measures the midnight wait)
- ios/HamroStepsTests/ActivityOverlapTests.swift — created (overlapping toggle saves with a failure; heart fails then fire saves; heart saves then fire fails; walk limit across Nepal midnight)

## Checks run
`ultron check`: passed · 2 of 2 passed · 3m 20s
- `scripts/check-ios.sh` · passed · 3m 01s
- `scripts/check-backend.sh` · passed · 18.7 s

The first two runs failed on other workers' in-progress files (`Family.swift`, then the `Icon.cheer` break described above). Both are fixed in the run above.

Not checked:
- The iOS script runs `-quiet`, so the log doesn't name individual tests. The new test files are in the test target (one of them failed to compile in an earlier run), and any failing test would fail the run.
- I took no screenshots of the disabled switch or the new empty-feed icon.
- The `syncFinished()` wiring in `HamroStepsApp.swift` isn't in place yet, so the app still calls `reload()` until that line changes.

## Libraries used
- Hugeicons — empty-feed icon moved from the missing `Icon.cheer` to the existing `Icon.celebrate` asset

## Notes for Jarvis
- **HamroStepsApp.swift:32** (owned by the other worker): change `stepSync.onSynced = { await home.reload() }` to `stepSync.onSynced = { await home.syncFinished() }`.
- **MockFamilyService.swift is shared with the other worker.** My changes are `actAs(_:)` (after `signOut()`) and the closed-day removal in `drop()` with its doc comment. The `walkingSince`/`walkEndsAt`/`status` fields, the `FamilyMember` init change and the walking/status seed lines are theirs. Commit this file together with their handoff, or after it.
- Optionally call `walkController.expireStaleNotice()` when the app comes to the foreground (from Home, which isn't my file). `sync(...)` already covers the familyToday refresh at midnight.
- Suggested commit message: `Fix review findings: mock drops closed-day steps on leave, Home re-subscribes after sync and reschedules midnight on clock changes, serialised notification saves and reactions, walk limit expires at Nepal midnight`

## Checks (run by Ultron)
Failed: scripts/check-backend.sh · 1 of 2 passed · 2026-11-14 14:58 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 7m 45s
- `scripts/check-backend.sh` · exit 1 · 0.7 s

Last 3 lines of `scripts/check-backend.sh`:
```text
convex/crons.ts(17,71): error TS2339: Property 'notifications' does not exist on type '{ days: { closeDay: FunctionReference<"mutation", "internal", { day?: string | undefined; }, { day: string; closed: number; }, string | undefined>; }; feed: { purgeOld: FunctionReference<...>; }; sessions: { ...; }; users: { ...; }; walks: { ...; }; }'.
convex/lib/push.ts(66,44): error TS2339: Property 'pushNode' does not exist on type '{ days: { closeDay: FunctionReference<"mutation", "internal", { day?: string | undefined; }, { day: string; closed: number; }, string | undefined>; }; feed: { purgeOld: FunctionReference<...>; }; sessions: { ...; }; users: { ...; }; walks: { ...; }; }'.
convex/notifications.ts(118,48): error TS2339: Property 'notifications' does not exist on type '{ days: { closeDay: FunctionReference<"mutation", "internal", { day?: string | undefined; }, { day: string; closed: number; }, string | undefined>; }; feed: { purgeOld: FunctionReference<...>; }; sessions: { ...; }; users: { ...; }; walks: { ...; }; }'.
```

## Second opinion
Skipped at merge: fixes of six reviewed findings, each with a test (2026-11-14 14:58)

## Checks override
Merged anyway: iOS check passed; backend red only from 2c worker WIP (2026-11-14 14:58)
