# iOS redesign, phase 1: light-only design system, Home bento, Liquid Glass
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-2040-ios-redesign-1-system-home.md
## What the user asked
Make the app light mode only and restyle Home to match the approved canvas: flat white bento tiles on a cool grey canvas, no shadows, and native Liquid Glass only on floating or tappable controls. Build the shared pieces that phase 2 will use on the other screens.

## What changed
- **Light only.** `UIUserInterfaceStyle: Light` in project.yml and `.preferredColorScheme(.light)` on the root. All colorsets now hold a single light value (Canvas #F4F4F6, Surface #FFF, SurfaceMuted #EEEEF1, SecondaryText #6B6B72, Accent #E2672F, AccentText #B5481B, Goal #2C9A76). New **GoalText #1F7A5C** (`.goalText`) for green text.
- **Design system (Components/Card.swift)**, for phase 2 to reuse:
  - `Bento`: radius 26 (small tiles 24), 12pt gap, 16pt margin, 20pt padding (small tiles 18), 5% black hairline.
  - `.bentoSurface(fill, radius:)`: flat fill, continuous corners, hairline edge, no shadow.
  - `Card(title:icon:)`: a white tile with an optional `TileLabel`.
  - `TileLabel`: small semibold secondary heading with a 16pt leading icon.
  - `InfoChip`: small grey fact chip.
  - `GlassIconButton`: a 48pt round `.glassEffect(.regular.interactive())` button.
  - `AvatarStack`: overlapping avatars, then "+N".
  - `Avatar` now has a `size:` (default 44, grows with Dynamic Type up to 1.5×) and an optional white ring.
  - `PrimaryButton` is now `.glassProminent`, and `Notice`'s retry is `.glass`.
- **Home, top to bottom:**
  - Header: family name in a large title with the switcher chevron, and a glass settings button. Under it, overlapping member avatars with "N walking together" ("Just you so far" when it's only you).
  - Today tile: the total, "of 50,000 steps", "N more to go, together" in AccentText or "Goal reached! Well walked, everyone." in GoalText. A 124pt ring on the right, capped at 1.3× and stacked under the text at accessibility sizes. Chips for "X of Y synced" and "N walking now", each left out when it would read 0.
  - "I'm walking": a full-width `.glassProminent` button tinted accent, about 60pt tall with radius 26, and the hint below in footnote.
  - Walking state: a flat tile (accent 8% over white) with the "You're walking" pill, "Walking for 12 min", the auto-stop line, and a `.glass` capsule "Stop walk" in neutral text. The model doesn't say who got the walk alert, so those avatars are skipped as the brief allows.
  - Two half tiles, stacked at accessibility sizes: Status ("Status / Set my status" or "Your status / <value>", opens the picker) and "Your steps / Synced 2 minutes ago" (an orb while sending, "Not synced yet / Pull down to try." before the first sync).
  - Everyone today: 44pt avatar, name with a crown for the organiser (VoiceOver hears "…, organiser"), status, and a small orange walker circle on the avatar's corner. Under each row is a 4pt bar in the member's colour showing their share of today's family total, in the fixed family order.
  - This week: hit days are green with a tick, today has an accent ring, future days a 1pt grey ring, and "Goal reached on N days" sits in GoalText on the label row (it wraps under the label when it doesn't fit).
  - Family moments: each event's avatar has a type badge (walk = accent, member steps = goal, family goal = goal tint). The reaction emoji are unchanged. Feed greys now use `secondaryText` (AA).
- **New icons (Hugeicons free, stroke-rounded 1.5, template SVG):** `Icon.calendar` (calendar-03) and `Icon.moments` (favourite).
- **One addition beyond the spec:** member rows also say "Walking now" in AccentText under the name, so the walking state is in words and not only in the small corner dot (parents, plain words). Drop it if the canvas is meant to be dot only.
- **Debug-only launch flags for screenshots (HamroStepsApp.swift, all `#if DEBUG`):**
  - `-homeState walking|goal` wraps the mock family service so the signed-in user is out walking, or today's steps pass the goal.
  - `-homeScroll center|bottom` opens Home scrolled down.
  - A `-screen home` launch no longer shows the notification prompt (`SilentPushAuthorizer`), because it covered the screenshots.

## Files
- ios/project.yml — modified (shared: one line, `INFOPLIST_KEY_UIUserInterfaceStyle: Light`)
- ios/Shared/UI/Palette.swift — modified
- ios/Shared/UI/Icon.swift — modified
- ios/Shared/SharedAssets.xcassets/Colors/AccentColor.colorset/Contents.json — modified
- ios/Shared/SharedAssets.xcassets/Colors/AccentText.colorset/Contents.json — modified
- ios/Shared/SharedAssets.xcassets/Colors/Canvas.colorset/Contents.json — modified
- ios/Shared/SharedAssets.xcassets/Colors/Goal.colorset/Contents.json — modified
- ios/Shared/SharedAssets.xcassets/Colors/SecondaryText.colorset/Contents.json — modified
- ios/Shared/SharedAssets.xcassets/Colors/Surface.colorset/Contents.json — modified
- ios/Shared/SharedAssets.xcassets/Colors/SurfaceMuted.colorset/Contents.json — modified
- ios/Shared/SharedAssets.xcassets/Colors/GoalText.colorset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-calendar.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-calendar.imageset/icon-calendar.svg — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-moments.imageset/Contents.json — created
- ios/Shared/SharedAssets.xcassets/Icons/icon-moments.imageset/icon-moments.svg — created
- ios/HamroSteps/App/HamroStepsApp.swift — modified
- ios/HamroSteps/Components/Card.swift — modified
- ios/HamroSteps/Features/Home/HomeView.swift — modified
- ios/HamroSteps/Features/Activity/WalkButton.swift — modified
- ios/HamroSteps/Features/Activity/WalkingBadge.swift — modified
- ios/HamroSteps/Features/Activity/FeedList.swift — modified
- ios/HamroSteps/Features/Activity/ActivitySupport.swift — modified
- ios/HamroStepsTests/AssetTests.swift — modified
- handoffs/screens/2026-11-14-home-idle.png — created
- handoffs/screens/2026-11-14-home-idle-center.png — created
- handoffs/screens/2026-11-14-home-walking.png — created
- handoffs/screens/2026-11-14-home-goal.png — created
- handoffs/screens/2026-11-14-home-axl.png — created
- handoffs/2026-11-14-2336-ios-redesign-1-home.md — created

## Checks run
`ultron check`: passed · 2 of 2 passed · 1m 01s
- `scripts/check-ios.sh` · passed · 57.5 s
- `scripts/check-backend.sh` · passed · 3.6 s

Also:
- AssetTests now also checks AccentText, SecondaryText and GoalText, plus a new test that every colour resolves the same in light and dark (no dark variants left).
- Screenshots on an iPhone 17 Pro simulator (iOS 26.5), `-screen home -mockSteps`:
  - idle (top, and scrolled to the middle with `-homeScroll center` for Everyone today, This week and Family moments)
  - `-homeState walking`
  - `-homeState goal`
  - accessibility XL text (top only)
- Not checked:
  - the bottom of Home and the lower tiles at accessibility XL (only the top was shot)
  - VoiceOver on a device
  - a real Convex launch (the layout doesn't depend on the backend)
  - the design canvas artifact: I worked from the brief's spec and didn't open it

## Libraries used
- Hugeicons — two new icons (calendar-03, favourite) for the This week and Family moments headings, the same style and stroke as the set
- Thinking Orbs — none touched (the existing `OrbLoader` is reused in the sync tile and the walk buttons)

## Notes for Jarvis
- Shared-file edit: ios/project.yml, one line (`INFOPLIST_KEY_UIUserInterfaceStyle: Light`).
- For phase 2:
  - `StatusLabel.swift` (out of my scope) still uses `.foregroundStyle(.secondary)`, which falls below AA on the new canvas. Switch it to `.secondaryText`.
  - `ActivityGallery.swift` still uses the old `WalkingBadge` pill (it still works).
  - Every screen that uses `Card` already gets the new flat tile, and `PrimaryButton` users get `.glassProminent`.
- The new debug launch flags (`-homeState`, `-homeScroll`, the silent push authorizer on `-screen home`) are Debug-only.
- Suggested commit: `iOS redesign 1: light-only palette (+GoalText), bento tiles, Liquid Glass controls, Home restyle`

## Checks (run by Ultron)
Passed · 2 of 2 · 55.2 s · 2026-11-14 23:36 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 51.7 s
- `scripts/check-backend.sh` · passed · 3.5 s
