# iOS: walk button + badge, status picker, feed + reactions, notification settings (standalone, mock service)
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1440-ios-activity-ui.md
Tasks: T-7, T-8, T-9, T-10
## What the user asked
Standalone SwiftUI components for walks, status, the feed with reactions, and notification settings (PRD F9–F16), coded against `docs/contract-activity.md`. Also needed: an `ActivityService` protocol with a mock, and a debug-only gallery with light, dark and accessibility-size screenshots. Nothing gets wired into Home, the tabs or app startup in this phase.

## What changed
- **Models** (`ios/Shared/Models/Activity.swift`, Foundation only, so a widget can use them too): Codable types that match the contract JSON. Timestamps are ms epoch (`EpochMillis`, converted with `ActivityTime`). The file covers `WalkStart`/`ActiveWalk`, `StatusPreset` (the 7 contract keys with the PRD labels), `MemberStatus`, `StatusInput`, `StatusExpiry`, `FeedEvent`/`FeedActor`/`ReactionCount`, `Reaction` (the fixed 5 emoji), `NotificationPrefs` + `NotificationPrefsPatch`, `APNsEnvironment`, and `ActivityError` (the contract's error codes).
  - Decoding is lenient where it matters: an unknown event type becomes `.unknown` and the feed hides it; emoji outside the set are dropped; ❤ without the variation selector still counts as ❤️; an unknown preset reads as no preset.
  - The pure rules live here and are shared by the mock and the UI: `StatusInput.validated` (exactly one of preset/text, trimmed text ≤ 30, expiry in the future and ≤ 7 days ahead), `FeedEvent.reacting(with:)` (add / same again removes / different replaces), and `FeedEvent.text(viewerId:)`. That gives "Mum passed 5,000 steps", "You started a walk", "The family is halfway to today's goal!" and "The family reached today's goal!".
- **Formatting** (`ActivityFormatting.swift`): elapsed time ("Just started", "12 min", "1 hr 5 min"), "Walking for 12 min", "Stops by itself at 4:06 PM", status expiry ("Until 9:00 PM" / "Until tomorrow, 10:00 AM" / "Until Tue, 10:00 AM"), and feed relative time ("Just now", "6 mins ago").
- **Service**: `ActivityService` has one method per contract function. Walking state and member status still come from `familyToday`, so they aren't duplicated here. `MockActivityService` is an actor with a sample family (Anish = me, Mum, Dad, Ram, Priya; avatar hexes from the backend palette). It enforces the contract itself: 3 walks per Nepal day, `already_walking`, the 2-hour auto-stop, status validation with the 24 h default, reaction toggle/replace, and a 3-Nepal-day feed window, newest first, capped at 100. It also has `failNextCall(with:)` and an optional delay for showing error and loading states.
- **Components** (`ios/HamroSteps/Features/Activity/`):
  - `WalkButton` plus a `WalkController`. A big "I'm walking" button with a line about what it does. While walking, it becomes a card: badge, "Walking for 12 min", "Stops by itself at …", and "Stop walk". It hides itself once `endsAt` passes. Contract errors become kind notices: `walk_limit_reached` shows "You've shared 3 walks today. Your steps still count for the family, and you can share a walk again tomorrow." and dims the button; `already_walking` and network errors get their own copy. There's a success haptic on start. `controller.sync(walkingSince:walkEndsAt:)` takes the values from `familyToday`.
  - `WalkingBadge`: a "Walking now" pill with a pulsing dot. The pulse is off under Reduce Motion. The text never wraps, and the walker icon drops first when space is tight.
  - `StatusPicker`: a sheet with the 7 presets (icon rows, check on the selected one) and "Or write your own" with a live `n/30` counter that clamps typing. Picking one clears the other. Expiry chips: 24 hours (default), Until tonight (21:00 local, hidden from 21:00 on), 1 hour, 4 hours, with the resulting "Until …" shown below. It has "Clear my status" when one is set, a "Set status" button, and friendly copy for `invalid_status` / `invalid_expiry` / offline. For the 24-hour default it sends no `expiresAt`, so the server default applies and phone clock drift can't matter.
  - `StatusLabel`: preset icon + label, or the custom text, on one line. It shows nothing when the status is null or expired.
  - `FeedList` / `FeedRow` / `ReactionBar` / `ReactionChip`, plus a `FeedModel`. Each row shows the actor's avatar colour and initial (a family icon for family events), the plain-language text, relative time, and the 5 emoji chips with counts. My reaction is highlighted with an accent fill and outline. Reactions are optimistic and revert if the server fails. It has loading (orb), empty and retry states, and isn't scrollable by itself, so it can sit inside Home's ScrollView.
  - `NotificationSettingsView` plus a `NotificationSettingsModel`: 4 toggles, each with a plain description. The evening one says "At 7 pm Nepal time…". A switch flips back if saving fails, with a footer note.
  - Loading uses `OrbLoader(compact: true)` with my own caption (`ActivityLoadingRow`); there's no `ProgressView`. Icon sizes in the badge, status label and walk card scale with Dynamic Type. VoiceOver labels are set for chips (e.g. "Clap, 3 reactions, including yours"), the counter and the status.
- **Icons:** 14 new Hugeicons (free set 4.4.0, stroke-rounded 1.5, template SVGs, made the same way as the scaffold's): walking, stop, clock-01, notification-01, tick-02, cancel-01, briefcase-01, home-01, bus-01, dumbbell-01, mountain, sofa-01, airplane-01, message-01. They're added as new cases in `Icon.swift`; no existing case changed.
- **Gallery** (debug only, `ActivityGallery.swift`): with `-activityGallery` the app shows a list of 5 pages. `-activityGallery walk|members|status|feed|notifications` opens one directly. Release builds compile the modifier as a no-op.

## Files
- ios/Shared/UI/Icon.swift — modified
- ios/HamroSteps/Features/Activity/ActivityGallery.swift — created
- ios/HamroSteps/Features/Activity/ActivitySupport.swift — created
- ios/HamroSteps/Features/Activity/FeedList.swift — created
- ios/HamroSteps/Features/Activity/NotificationSettingsView.swift — created
- ios/HamroSteps/Features/Activity/StatusLabel.swift — created
- ios/HamroSteps/Features/Activity/StatusPicker.swift — created
- ios/HamroSteps/Features/Activity/WalkButton.swift — created
- ios/HamroSteps/Features/Activity/WalkingBadge.swift — created
- ios/HamroSteps/Services/ActivityMockService.swift — created
- ios/HamroSteps/Services/ActivityService.swift — created
- ios/HamroStepsTests/ActivityModelTests.swift — created
- ios/HamroStepsTests/ActivityServiceTests.swift — created
- ios/Shared/Models/Activity.swift — created
- ios/Shared/Models/ActivityFormatting.swift — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-check.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-check.imageset/icon-check.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-clear.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-clear.imageset/icon-clear.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-clock.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-clock.imageset/icon-clock.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-notification.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-notification.imageset/icon-notification.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-commuting.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-commuting.imageset/icon-status-commuting.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-custom.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-custom.imageset/icon-status-custom.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-hike.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-hike.imageset/icon-status-hike.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-home.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-home.imageset/icon-status-home.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-resting.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-resting.imageset/icon-status-resting.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-travelling.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-travelling.imageset/icon-status-travelling.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-work.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-work.imageset/icon-status-work.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-workout.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-status-workout.imageset/icon-status-workout.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-stop.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-stop.imageset/icon-stop.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-walking.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-walking.imageset/icon-walking.svg — created
- handoffs/2026-11-14-1429-ios-activity-ui.md — created

The 15 screenshots are in the **main checkout's** `handoffs/screens/` (next to this handoff), not in my worktree.

## Checks run
`ultron check`: passed · 2 of 2 passed · 22.6 s
- `scripts/check-ios.sh` · passed · 22.6 s
- `scripts/check-backend.sh` · passed · 0.0 s

(The run before the last small UI tweaks took 1m 43s and also passed; the 22.6 s run is incremental, after the final edits.)

Also checked:
- `xcodebuild test` on iPhone 17 Pro: **62 tests in 16 suites passed** (48 new), with no Swift warnings. The new tests cover:
  - status validation: preset only, trimmed text only, both/neither/blank → `invalid_status`, 30 vs 31 chars, UTF-16 counting (15 emoji OK, 16 not), clamping that keeps whole characters, expiry at now / past / 7 days / 7 days + 1 s, JSON that sends only set fields, contract preset keys and labels, and expiry choices including "until tonight" hidden from 21:00
  - reactions: the pure logic plus the mock's add, same-again removes, different replaces, zero counts dropped, unknown event refused
  - feed text for every type, for others and for "You", with a missing actor and an unknown type; decoding the contract's JSON shape, including ❤ without VS16 and an unknown emoji
  - walks in the mock: endsAt = +2 h, `already_walking`, auto-stop at exactly 2 h, 3 per Nepal day then allowed again after Nepal midnight, stop as a no-op
  - elapsed / auto-stop / status-until / relative time formatting
  - `WalkController` (limit notice, start/stop, offline, sync from familyToday), `FeedModel` optimistic revert, the notification switch moving back on failure, and parsing of the gallery launch argument
  - `AssetTests` now also loads all 14 new icons as 24×24 templates
- **Screenshots**, taken on a simulator I created for this run and then deleted: 5 gallery pages × light / dark / accessibility-large text, all reviewed at reduced size. At AX size, the reaction chips and expiry chips wrap onto new lines instead of clipping.

**Not checked:**
- Real Convex calls (there's no backend activity code yet) and push delivery.
- VoiceOver run-through on device; labels are set but weren't listened to.
- The live gallery walk button tapped through in the simulator. Its flow is covered by `WalkController` tests, not by UI taps.
- Reduce Motion was only checked in code (the pulse is skipped), not on a screenshot.

## Libraries used
- Hugeicons — 14 new icons (walk button, badge, walk timer, status presets, custom status, selected check, clear status, notification settings header), free set stroke-rounded 1.5, template SVGs in `ios/Shared/SharedAssets.xcassets/Icons`
- Thinking Orbs — via the existing `OrbLoader(compact: true)` for the walk button and Set status while sending, and for loading the feed and notification settings

## Questions for the user
none

## Notes for Jarvis
- **One line for `RootView`** (I didn't edit it): in `ios/HamroSteps/App/RootView.swift`, add `.activityGalleryOnLaunch()` directly after `.background(.canvas)` on the `Group` in `body`. In my worktree I added that exact line temporarily to build the screenshot app, then removed it; `git diff` on `RootView.swift` is clean.
- **Shared simulator clash:** my first screenshot run caught another worker's build, which had been installed over mine on the shared "iPhone 17 Pro" simulator (same bundle ID), so one shot showed their onboarding. I recaptured everything on a private simulator. `ultron check` from two worktrees at once can hit the same clash. Workers taking screenshots should use their own simulator (`xcrun simctl create`).
- **For the Convex activity phase (contract details the backend should match):**
  - The app counts the 30-char status limit as JavaScript `.length` (UTF-16) and trims the text before sending. The server should do the same so the two never disagree.
  - The app sends no `expiresAt` for the 24-hour choice. "Until tonight" is 21:00 in the **phone's** time zone.
  - `react` on a missing event: the contract has no `not_found`, so the mock throws `not_member`. Worth stating in the contract.
  - Avatar colour is parsed as `#RRGGBB` (from `AVATAR_PALETTE` in the convex-core work); anything else falls back to the accent colour.
- **For the placement phase:** `WalkButton(controller:)` and `FeedList(model:)` take models built from an `ActivityService`. `StatusPicker` is meant for a `.sheet` and dismisses itself. `NotificationSettingsView` expects to be inside a `NavigationStack`. Member rows should stack the step count under the name at accessibility sizes, as the gallery's sample row does (`dynamicTypeSize.isAccessibilitySize`).
- No shared files edited apart from `ios/Shared/UI/Icon.swift` (new cases only). No new packages, and `project.yml` is untouched; XcodeGen picks the new folders up from the existing source paths.
- Suggested commit message: `Add activity UI: walk button and badge, status picker, feed with reactions, notification settings, mock ActivityService, debug gallery`

## Checks (run by Ultron)
Passed · 2 of 2 · 9.3 s · 2026-11-14 14:30 · in `/Users/subixu/.jarvis-worktrees/hamro-steps/ios-activity-ui`
- `scripts/check-ios.sh` · passed · 9.3 s
- `scripts/check-backend.sh` · passed · 0.0 s

## Second opinion
Skipped at merge: reviewed: Has concerns (handoffs/reviews/2026-11-14-1429-ios-activity-ui-second.md); stale only because Jarvis removed screenshot lines from Files; 3 should-fix items carried into iOS phase 4 (2026-11-14 14:39)
