# iOS redesign, phase 2: every other screen on the new tiles and glass
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-2041-ios-redesign-2-screens.md
## What the user asked
Restyle every screen outside Home to match the design canvas, using phase 1's tiles, glass buttons and colours. No new behaviour.

Built from the brief's per-screen notes and the user's answers (2026-11-15):
- the canvas itself couldn't be opened
- no Notifications row in Family settings
- no avatars row on Welcome
- Health gets a numbered how-to
- the Me Apple Health tile has two mini tiles: state on the left, last sent on the right

## What changed
Copy and order are today's, except "Step 1 of 2" / "Step 2 of 2" and the Health how-to split (both approved). No behaviour changed.

- **New shared pieces (Components/Card.swift):**
  - `.fieldTile()`: an input on a white tile.
  - `.choiceTile(selected:)`: a white tile with a 2pt accent border when selected.
  - `SecondaryButton`: a full-width `.glass` capsule with neutral text.
  - `StepCount`: "Step N of 2" in AccentText.
  - `TileRow` and `TileDivider`: rows inside a tile, with icon, title, optional value and chevron. `TileRow` has an action variant (AccentText) and a destructive variant (system red), and stacks its value under the title at accessibility sizes.
  - `PrimaryButton` and `SecondaryButton` stay on one line (`minimumScaleFactor(0.6)`), as phase 1 did for "I'm walking". At accessibility XXXL on the SE, the two-line buttons took half the screen.
- **Welcome:**
  - a large hero tile with an accent wash, the app mark as a 96pt orange rounded square, the name and the one-line promise
  - the three points in one tile
  - the real `SignInWithAppleButton` in `.black` as a 56pt capsule (the dark branch is gone)
  - no avatars row and no photo
- **Name:** the heading block, then the field on a tile.
- **Health:**
  - a small orange Health mark, then the four reasons in one tile
  - then an "On the next screen" tile with 1 Turn on Steps and 2 Tap Allow
  - "Allow step count" stays `.glassProminent`; "Not now" is now a `.glass` `SecondaryButton`
- **Start or join:** two big choice tiles: an icon disc and a chevron disc on top, then a title2 title and the detail.
- **Family name and Daily goal:**
  - "Step 1 of 2" and "Step 2 of 2" above the titles, via `SetupHeading` (in FamilySetupView.swift)
  - the goal stepper on a tile with round glass −/+ buttons
  - the 2×2 presets as choice tiles: an accent border, an accent number and a tick when selected; "Suggested" under 50,000
  - one column at accessibility sizes, as before
- **Invite:** a code tile, "Share invite" as `.glassProminent`, "Done" as `.glass`, and "Copy code" as a glass capsule.
- **Join:** the heading, the code field on a tile, Paste, and the family preview as a tile.
- **Status picker:**
  - the presets as a 2-column grid of choice tiles (1 column at accessibility sizes)
  - the own-text field as a choice tile, bordered while it has text, with the counter under it
  - expiry capsules: the selected one is AccentText with white text (passes AA); the others are white with a hairline
  - "Clear my status" is a `.glass` capsule
  - "Set status" is `.glassProminent` tinted accent, like "I'm walking"
  - greys moved to `.secondaryText`
- **Family settings:** a List became a ScrollView of tiles:
  - Family: Name, Daily goal, and "Change name or goal" for the organiser, with the organiser note under it
  - Invite code (organiser only): the code, "Share invite" and "Get a new code" as accent rows, with the 8-people note under it
  - People: avatars, "(you)" and "Organiser", and a "Remove" capsule that moves under the name at accessibility sizes
  - a "Leave <family>" row in AccentText, with the footnote under it
  - there's no Notifications row, as the user asked
- **Change name or goal:** labelled tiles (the family name field, then the same goal picker), and the footnote.
- **Notifications:** the four switches in one "Let me know when" tile, with dividers. The footnote sits under the tile. The load-failed state is now a `Notice` with "Try again". Greys moved to `.secondaryText`.
- **Me:**
  - the "Me" title, then a profile tile with a 64pt avatar
  - an Apple Health tile:
    - two grey mini tiles: "Reading steps" or "Permission asked" on the left; "Steps last sent …" or the "No steps read yet…" line on the right
    - they stack at accessibility sizes
    - the "Steps not showing?" hint sits inside the tile
    - the not-connected state keeps its "Connect Apple Health" button, now `.glassProminent`
  - then two row tiles: Notifications and Privacy policy; then Sign out and "Delete account" in system red
- **Delete account:** the list sits in a tile, and "Delete my account" is a `.glass` capsule with red text. The two-step confirmation is unchanged.
- **StatusLabel:** `.secondaryText` (AA).
- **ActivityGallery (debug):**
  - the WalkingBadge pill on member rows is replaced by phase 1's corner `WalkingDot` plus "Walking now" in AccentText, matching Home
  - the "Badge on its own" section shows the dot
  - greys moved to `.secondaryText`
  - `WalkingBadge` is still used by WalkButton ("You're walking"), so it stays.

## Files
- ios/HamroSteps/Components/Card.swift — modified
- ios/HamroSteps/Features/Onboarding/WelcomeView.swift — modified
- ios/HamroSteps/Features/Onboarding/HealthPermissionView.swift — modified
- ios/HamroSteps/Features/Setup/FamilySetupView.swift — modified
- ios/HamroSteps/Features/Setup/InviteCodeView.swift — modified
- ios/HamroSteps/Features/Setup/JoinFamilyView.swift — modified
- ios/HamroSteps/Features/Settings/FamilySettingsView.swift — modified
- ios/HamroSteps/Features/Me/MeView.swift — modified
- ios/HamroSteps/Features/Activity/StatusPicker.swift — modified
- ios/HamroSteps/Features/Activity/StatusLabel.swift — modified
- ios/HamroSteps/Features/Activity/NotificationSettingsView.swift — modified
- ios/HamroSteps/Features/Activity/ActivityGallery.swift — modified
- ios/HamroSteps/App/HamroStepsApp.swift — modified (outside the brief's list, Debug-only, see Notes)
- handoffs/2026-11-14-2353-ios-redesign-2-screens.md — created
- handoffs/screens/2026-11-15-ios-redesign2-welcome.png — created
- handoffs/screens/2026-11-15-ios-redesign2-name.png — created
- handoffs/screens/2026-11-15-ios-redesign2-health.png — created
- handoffs/screens/2026-11-15-ios-redesign2-setup.png — created
- handoffs/screens/2026-11-15-ios-redesign2-create-name.png — created
- handoffs/screens/2026-11-15-ios-redesign2-create-goal.png — created
- handoffs/screens/2026-11-15-ios-redesign2-invite.png — created
- handoffs/screens/2026-11-15-ios-redesign2-join.png — created
- handoffs/screens/2026-11-15-ios-redesign2-settings.png — created
- handoffs/screens/2026-11-15-ios-redesign2-me.png — created
- handoffs/screens/2026-11-15-ios-redesign2-status.png — created
- handoffs/screens/2026-11-15-ios-redesign2-notifications.png — created
- handoffs/screens/2026-11-15-ios-redesign2-se-xxxl-health.png — created
- handoffs/screens/2026-11-15-ios-redesign2-se-xxxl-create-goal.png — created
- handoffs/screens/2026-11-15-ios-redesign2-se-xxxl-settings.png — created
- handoffs/screens/2026-11-15-ios-redesign2-se-xxxl-me.png — created
- handoffs/screens/2026-11-15-ios-redesign2-se-xxxl-status.png — created

## Checks run
`ultron check`: passed · 2 of 2 passed · 58.6 s
- `scripts/check-ios.sh` · passed · 55.1 s
- `scripts/check-backend.sh` · passed · 3.5 s

The first `ultron check` run failed on one test, `PushSessionTests.theLastAccountsRegistrationFinishesBeforeTheNextAccountRegisters`. It's a Push timing test with fixed 50/100 ms sleeps, and my change doesn't touch Push. My two screenshot simulators were booted at the time. Once they were shut down, the re-run above passed. The test may be flaky under load.

Also:
- Screenshots on an iPhone 17 Pro simulator (iOS 26.5), my own erased simulator, so no system prompts:
  - the 10 `-screen` launches with `-mockSteps`: welcome, name, health, setup, create-name, create-goal, invite, join, settings, me
  - `-activityGallery status` and `-activityGallery notifications`
- Accessibility XXXL on an iPhone SE (3rd generation) simulator:
  - every screen above, plus `-activityGallery members`
  - nothing is cut off sideways in the app screens; the headings, tiles, fact rows, mini tiles and status tiles all wrap or stack
  - the only problem found is fixed: the two-line bottom buttons
  - five SE shots are saved (health, create-goal, settings, me, status)
- Not checked:
  - content below the first screen at XXXL (the Health how-to tile, the preset grid, People rows, expiry capsules). The simulator can't scroll without taps. Those use the same wrapping or stacking code as the parts that were checked.
  - the "Change name or goal" and "Delete account" pages, which need a tap to reach (no `-screen` for them)
  - VoiceOver on a device
  - the design canvas, which still can't be opened from a worker

## Libraries used
- Hugeicons — the existing icon set on every restyled screen (`Icon.*`, no new icons)
- Thinking Orbs — none touched (the existing `OrbLoader` states are unchanged)

## Questions for the user
none

## Notes for Jarvis
- **Out-of-list edit (Debug only), ios/HamroSteps/App/HamroStepsApp.swift, two small changes needed for the screenshots:**
  1. `.activityGalleryOnLaunch()` is back on the root view. It was dropped in a7a60e7, so `-activityGallery` did nothing, and the brief's status picker and notifications shots depend on it. It's a no-op in Release and without the flag.
  2. `pushAuthorizer()` now returns `SilentPushAuthorizer` for any `-screen` or `-activityGallery` launch, not only `-screen home`. Before, the notification prompt covered every setup and settings shot.
- **Not mine:** `ios/HamroSteps/Services/Convex/Info.plist` shows as modified (keys reordered, the comment dropped). XcodeGen rewrites it on each `xcodegen generate`, and both my build and `scripts/check-ios.sh` run that. It's not in my file list. Restore it, or make the plist match what XcodeGen writes so the diff stops appearing.
- The `-activityGallery members` page has a debug-only overflow at XXXL: its uppercase section heading runs off the side. It's the gallery's `GallerySection`, not an app screen, so I left it.
- iOS truncates the large "Notifications" title at XXXL on the SE ("Notificatio…"). This is the system navigation title, and it was the same before.
- Delete account keeps system red, as before. "Keep my account" was not added.
- Suggested commit: `iOS redesign 2: onboarding, setup, settings, Me, status and notifications on bento tiles and Liquid Glass; shared field/choice tiles, rows, SecondaryButton`

## Checks (run by Ultron)
Passed · 2 of 2 · 1m 00s · 2026-11-15 00:53 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 56.8 s
- `scripts/check-backend.sh` · passed · 3.4 s
