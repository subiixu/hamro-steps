# iOS: walking button + badge, status picker, feed + reactions, notification settings (standalone components, mock service)
worker: claude
model: claude-opus-5-5
effort: high
started: 2026-11-14 14:40
Tasks: T-7, T-8, T-9, T-10
isolate: yes
files: ios/HamroSteps/Features/Activity/**, ios/HamroSteps/Services/Activity*.swift, ios/Shared/Models/Activity*.swift, ios/HamroStepsTests/Activity*.swift, ios/Shared/SharedAssets.xcassets/Icons/**, ios/Shared/UI/Icon.swift

## Goal
Self-contained SwiftUI components and an `ActivityService` protocol + `MockActivityService` for PRD F9–F16, following `docs/contract-activity.md` exactly. Another worker is building Home/onboarding in the main checkout right now, so this phase does **not** wire anything into Home, tabs or app startup. A later phase places the components. Done = `scripts/check-ios.sh` passes in your worktree, plus screenshots (light, dark, one accessibility text size) of each component rendered on a debug-only gallery screen, saved to `handoffs/screens/`.

## Context
- Read `docs/PRD.md` (design principles: relationship first, built for parents, celebrate never shame) and `docs/contract-activity.md`.
- Merged scaffold: `handoffs/merged/2026-11-14-1400-ios-scaffold.md`. Reuse `Icon`, `Palette`, `Card`, `OrbLoader`. Icons only Hugeicons stroke-rounded 1.5, fetched the way the scaffold did (new imagesets only; add cases to `Icon.swift` without changing existing ones). Loading only `OrbLoader`.
- **Components** (all under `ios/HamroSteps/Features/Activity/`):
  1. `WalkButton`: a big "I'm walking" button. When walking, it becomes "Stop walk" with elapsed time and auto-stop time. It shows friendly copy for `walk_limit_reached` ("You've shared 3 walks today").
  2. `WalkingBadge`: a small live "walking now" pill (with subtle motion; respect Reduce Motion) for a member row.
  3. `StatusPicker`: a sheet with the 7 presets, custom text (30-char limit with counter), and expiry options (24 h default, "until tonight" = 21:00 local, 1 h, 4 h), plus clear.
  4. `StatusLabel`: compact status text for a member row; nothing when null.
  5. `FeedList` / `FeedRow`: plain-language event text ("Mum passed 5,000 steps", "The family reached today's goal!", "Ram started a walk"), the actor's avatar colour, relative time, and a reactions row: the 5 fixed emoji as one-tap chips with counts, with my reaction highlighted.
  6. `NotificationSettingsView`: 4 toggles with plain descriptions.
- Models in `ios/Shared/Models/Activity.swift` (Codable, matching the contract JSON); service protocol in `ios/HamroSteps/Services/ActivityService.swift`; mock in `ActivityMockService.swift` with realistic sample data.
- The gallery screen is shown only with the `-activityGallery` debug launch argument, and its code lives in your Features folder. Handle that argument inside your folder via a view modifier you expose; note in the handoff the one line that needs adding to `RootView` (don't edit `RootView` yourself).

## Scope
- May touch: the `files:` globs above, `handoffs/screens/`
- Must not touch: anything else in `ios/` (Home, onboarding, RootView, project.yml, other Services), `backend/`, `docs/`, `scripts/`
- No new Swift packages.

## Phase
iOS activity UI, standalone. Its integration into Home and the real Convex service come in a later phase.

## Checks
`ultron check` in your worktree. Unit tests: status validation (exactly one of preset/text, 30 chars, expiry bounds), reaction toggle/replace logic in the mock, feed event text for each type, and elapsed/auto-stop time formatting.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
