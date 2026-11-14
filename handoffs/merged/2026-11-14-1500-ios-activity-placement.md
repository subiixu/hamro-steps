# iOS phase 4a: place walking, status and feed into Home and Me (mock services)
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1615-ios-activity-placement.md
## What the user asked
Wire the merged activity components into the app on mock services: the walk button, "Set my status" and the feed on Home; a walking badge and status on member rows; Notifications in Me (T-7, T-8, T-9, T-10).

## What changed
- **Home**, in the brief's order: header, ring and sync line, `WalkButton`, a "Set my status" card that shows your current status once one is set and opens `StatusPicker` in a sheet, "Everyone's steps today", "This week", and a "Family moments" card holding `FeedList`. Pull to refresh reloads the feed too.
- **Member rows** show `WalkingBadge` while a walk is running and `StatusLabel` under the name. A 30 s timeline drops a walk or status when it ends, without waiting for a refresh. At accessibility sizes the steps already sit under the name.
- **Walk controller** syncs with your own `walkingSince` and `walkEndsAt` from `familyToday`, and calls `expireStaleNotice()` when the app comes back to the foreground (as Jarvis asked).
- **A status you save or clear** shows straight away and stays until `familyToday` brings a new status for you. The mock family service doesn't see activity-service writes, so this is how it shows up in mock mode.
- **Me** has a Notifications row that pushes `NotificationSettingsView`, inside Me's existing `NavigationStack`.
- **Model:** `FamilyMember` gains `walkingSince`, `walkEndsAt` and `status` (decoded per `docs/contract-activity.md`, all optional), plus an `activeWalk` helper. I wrote `MemberStatus: Hashable` by hand in `Family.swift`, because `FamilyMember` is Hashable and Swift only synthesises the conformance in the declaring file.
- **Injection:** `AppServices` gains `activity` and `now`. `\.activityService` and `\.now` are environment entries, set in `HamroStepsApp` the same way `familyService` is. The one `now` clock goes to `MockFamilyService.sample`, `MockActivityService` and the views, so the sample walks (Aama 12 min in, Sunita 34 min in) are seeded from the same clock the timers read.
- **Mock data:** Aama and Sunita are walking. Aama is At home, Buwa At work, Sunita "Visiting Pokhara", and Rohan On a hike (in the cousins family).
- **After a sync** the app calls `home.syncFinished()` instead of `reload()`, as Jarvis asked.

## Files
- ios/Shared/Models/Family.swift — modified
- ios/HamroSteps/Features/Home/HomeView.swift — modified
- ios/HamroSteps/Features/Me/MeView.swift — modified
- ios/HamroSteps/App/HamroStepsApp.swift — modified
- ios/HamroSteps/Services/MockFamilyService.swift — modified (my part only: see Notes)
- ios/Shared/UI/Icon.swift — modified (shared file, one line: see Notes)
- handoffs/screens/2026-11-14-ios-placed-home-light.png — created
- handoffs/screens/2026-11-14-ios-placed-home-dark.png — created
- handoffs/screens/2026-11-14-ios-placed-home-ax.png — created
- handoffs/screens/2026-11-14-ios-placed-me.png — created

`RootView.swift` turned out not to need a change.

## Checks run
`ultron check`: passed · 2 of 2 passed · 4m 48s
- `scripts/check-ios.sh` · passed · 4m 36s
- `scripts/check-backend.sh` · passed · 11.5 s

I also ran a debug build on my own simulator (`hamro-placement`, deleted afterwards) and took screenshots with `-screen home -mockSteps` (light, dark, accessibility-extra-large) and `-screen me`.

**Not checked:**
- **Lower Home cards:** the screenshots show only the top of Home. The member rows (badges, status), "This week" and "Family moments" sit below the fold, and `simctl` can't scroll. They compile and pass the checks, but nobody has looked at them on screen.
- **Interactions:** the StatusPicker sheet, the walk start/stop flow and the Notifications screen weren't opened.
- **The two Jarvis additions** (`syncFinished`, `expireStaleNotice`) came in after the screenshots. They change no visuals; they pass `ultron check`.
- **Tests:** none added. This phase is placement; the logic stays in the components and models that already have tests.

## Libraries used
- Hugeicons: existing `Icon` cases only (`.notification` on the Me row; `.edit`, the status preset icons and `.chevronRight` on the status card). No new icons.

## Notes for Jarvis
- **`Shared/UI/Icon.swift` (shared, outside my list):** main declared `case clock` twice, once from each branch in the activity-UI merge, so nothing compiled. I removed the second line and merged its comment into the first. The other change in that file's diff (`cheer`) is the model-fixes worker's.
- **`MockFamilyService.swift`:** the seed had nowhere to put walk or status data, so beyond the `members` seed I added three defaulted fields to `StoredUser` and passed them through in `snapshot()` (an expired status reads as nil, per the contract). The other worker's `actAs(_:)` and `drop()` changes are in the same file. Commit the file as one, with both workers' edits.
- **`SampleFamilyActivity` (temporary, in `HamroStepsApp.swift`):** a thin wrapper that sends every family's `feed` call to `MockActivityService.familyId`, because the mock throws `notMember` for any other family. Remove it once the mock accepts any family, or when Convex lands.
- **Mock mismatch (follow-up for the mock owner):** the activity mock's sample people (Anish, Mum, Dad, Ram, Priya) don't match the family mock's (Priya, Aama, Buwa, Sunita…), and its "me" is `user-anish`, not the signed-in sample user. So feed names differ from the Home rows, and reactions don't show as yours on Home.
- **"Single provider of now", only partly done:** `WalkButton`, `FeedList` and `StatusPicker` still use `TimelineView(.periodic(from: .now, …))` and `Date.now` inside the other worker's files. Their timers read the real clock, but because the sample walks are seeded from the same clock, the screenshots still read the same each run. To make it complete, those components should read `@Environment(\.now)`, which this phase adds.
- **Suggested commit message:** `Place walking, status and feed on Home and Notifications in Me, on mock services`

## Second opinion
Skipped at merge: UI integration of already-reviewed components; Jarvis checked screenshots; checks green (2026-11-14 14:58)

## Checks override
Merged anyway: iOS check passed; backend check red only from the push (2c) worker's in-progress edits (2026-11-14 14:58)
