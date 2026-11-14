# iOS redesign, phase 1: light-only design system, Home bento, Liquid Glass
worker: claude
model: claude-opus-5-5
effort: high
files: ios/project.yml, ios/Shared/UI/Palette.swift, ios/Shared/UI/Icon.swift, ios/Shared/SharedAssets.xcassets/Colors/**, ios/Shared/SharedAssets.xcassets/Icons/**, ios/HamroSteps/App/HamroStepsApp.swift, ios/HamroSteps/Components/Card.swift, ios/HamroSteps/Features/Home/HomeView.swift, ios/HamroSteps/Features/Activity/WalkButton.swift, ios/HamroSteps/Features/Activity/WalkingBadge.swift, ios/HamroSteps/Features/Activity/FeedList.swift, ios/HamroSteps/Features/Activity/ActivitySupport.swift, ios/HamroStepsTests/AssetTests.swift

## Goal
The app is light mode only and Home matches the approved design canvas: flat white bento tiles on a cool grey canvas, no shadows, Apple's native Liquid Glass only on floating and tappable controls. Phase 2 (a separate brief) restyles every other screen with the components this phase builds.

## Context
- Design (source of truth, 16 screens, tap-through): https://claude.ai/artifact/B24MPUiweEWxkdJ1Muuzbi. Home = "Home" and "Home, walking, goal reached" artboards. If you can't open it, the spec below is enough.
- Starting point: design/redesign-v1.patch (an earlier pass of the same direction; reverted, not applied). Read it with grep -n / sed -n; reuse what fits (Bento constants, `bentoSurface`, `GlassIconButton`, `TileLabel`, light-only lock, colorsets), but the canvas wins where they differ.
- iOS 26 target, so use the real APIs: `.glassEffect(.regular.interactive(), in:)`, `.buttonStyle(.glass)` / `.glassProminent`, `GlassEffectContainer` where glass shapes sit together. The tab bar is already native glass; don't restyle it.
- PRD rules still hold: built for parents (large text, plain words, Dynamic Type), no red failure states, never rank members.
Read narrowly: grep -n and sed -n line ranges.

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

## Spec
- Light only: `INFOPLIST_KEY_UIUserInterfaceStyle: Light` in project.yml and `.preferredColorScheme(.light)` on the root. Colorsets lose their dark variants.
- Colours: Canvas #F4F4F6, Surface #FFFFFF, SurfaceMuted #EEEEF1, SecondaryText #6B6B72, AccentColor #E2672F, AccentText #B5481B, Goal #2C9A76, plus a new GoalText #1F7A5C for green text (Goal fails AA as small text). Keep AssetTests in step.
- Tiles: white, continuous corner radius 26 (small tiles 24), 1pt hairline edge black 5%, no shadow, 12pt gaps, 16pt screen margins, 18–20pt padding. Tile headings = small semibold secondary label with a leading 16pt icon (Today, Everyone today, This week, Family moments).
- Header: family name large title with the switcher chevron; round glass settings button; under it a row of overlapping member avatars + "4 walking together" style caption (member count; drop the city text from the canvas, it's sample copy).
- Today tile: total left (large rounded bold), "of 50,000 steps", accent-text line "N more to go, together" / goal-text "Goal reached! Well walked, everyone."; ring right (~124pt, capped for accessibility sizes, stacks under the text at accessibility sizes). Under it small grey chips with icons: "3 of 4 synced", "1 walking now" (only facts the app already has; omit a chip when it would read 0).
- "I'm walking": full-width `.glassProminent` tinted accent, 60pt tall, radius 26; hint text below in footnote.
- Walking state: soft-orange flat tile (accent 8%), "You're walking" pill, "Walking for 12 min", auto-stop line, avatars of who got the alert if the model has it (else skip), `.glass` capsule "Stop walk".
- Two half tiles side by side (stack at accessibility sizes): Status (icon, "Status"/"Your status", value) and sync (clock icon, "Your steps", "Synced 2 min ago").
- Everyone today: avatar 44pt, name, organiser crown, status, walking badge as a small orange circle with the walk icon on the avatar's corner, and a thin 4pt bar in the member's avatar colour showing their share of today's family total (not a rank; fixed order stays).
- This week: 7 day markers, hit = green filled with tick, today = accent ring, future = 1pt grey ring; "Goal reached on N days" in GoalText on the label row.
- Family moments: each event's avatar gets a small type badge (walk = accent, steps = goal, family goal = goal tint). Reaction pills stay emoji (they're the product's reactions).
- Avatars: keep initials on the member's colour (no photos exist in the data model). The canvas shows drawn portraits and photo placeholders: NOT in scope; real photos are blocked until licensed images are available (see Notes).

## Scope
- May touch: the files in `files:` above.
- Must not touch: Services/, Sync/, Push/, backend/, web/, other Features/ screens (phase 2).
- Shared files (edit minimally, name in handoff): ios/project.yml.

## Phase
Phase 1 of 2. Phase 2 brief: handoffs/briefs/2026-11-14-2041-ios-redesign-2-screens.md, spawned with `--after` this handoff.

## Checks
`ultron check`. Then screenshots of Home (idle, walking, goal reached, accessibility XL text) on the iPhone 17 Pro simulator via the debug `-screen home` launch, saved under handoffs/screens/, once per state.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After the answers arrive on your terminal, finish this phase without stopping again. If you have no questions, build straight through.
