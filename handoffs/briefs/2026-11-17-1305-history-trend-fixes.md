# Steps history iOS: two trend fixes from the second opinion
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-17 12:57 · terminal: s_68f9927f
redo: handoffs/2026-11-17-1253-history-ios.md
why: second opinion: unequal trend comparison; recorded zero days dropped
Tasks: T-44
files: ios/HamroSteps/Features/History/HistoryModel.swift, ios/HamroStepsTests/HistoryModelTests.swift

## Goal
Fix the two "Should fix" findings in `handoffs/reviews/2026-11-17-1253-history-ios-second.md` so the History trend lines can't misstate change, with regression tests.

## Done so far
The History screen is built and uncommitted in the working tree: handoff `handoffs/2026-11-17-1253-history-ios.md` (read its "What changed" only). Keep everything else as it is.

## Remaining
1. **Compare like with like** (`HistoryModel.swift` ~:61, `HistoryTrend.compute`). Keep today out of the average (that decision stands: an unfinished day would make every morning read "Down"). But when today is excluded, also drop the **last** day of `previous`, so the comparison is the completed days of this period against the same weekdays exactly N days earlier (N−1 vs N−1). When today isn't in `current` (or is the only day), keep the current behaviour. Goal-hit count and best day are unchanged. Test: identical weekly pattern (six 10,000 days + today 1,000, previous week six 10,000 + a 1,000 on the matching weekday) → "About the same".
2. **Keep recorded zero days** (`HistoryModel.swift` ~:283, `split(_ daily:…)`, and the Me loading at ~:257). "Where Health history starts" must come from which days are **present** in the raw `dailyStepTotals` dictionary, not from the first positive total. A present day with 0 steps counts (in the average, as data). An all-zero window that has entries shows the chart with zeros and trends, not the no-data/no-access sentence; only an empty dictionary means no data. Carry presence through (e.g. `steps: Int?` per day, or a flag), whatever is smallest. Tests: leading recorded zeros are kept; an all-zero window is not "no data"; an empty response is "no data".

## Dead ends
- Don't change the Family tab's data path, the backend, the view layout or the colours.
- Don't include today in the average.

## Acceptance
scripts/check-ios.sh

## File scope
- May touch: ios/HamroSteps/Features/History/HistoryModel.swift, ios/HamroStepsTests/HistoryModelTests.swift (HistoryView.swift only if a type change forces a one-line edit; name it in the handoff)
- Must not touch: everything else, including backend/** and Home

## Context
Read narrowly (grep -n, sed -n ranges), never whole-file cat. Check `StepSource`/`HealthKitStepSource.dailyStepTotals` (`ios/HamroSteps/Health/HealthKitStepSource.swift:49`) for how it reports recorded zeros vs missing days before relying on it.

## Libraries and design rules
<!-- written by nayo spawn from `araniko knowledge show`; replaced on every spawn -->
### Libraries

- **Transitions.dev** (motion): Use Transitions.dev for UI transitions such as modals, toasts, tooltips, accordions, toggles and card resizes, instead of hand-rolling animations. Pick the matching effect from its library (CSS or React) and keep it consistent across the project. iOS: Not supported; the page mentions only CSS and React. Mac: Not supported; the page mentions only CSS and React. Web: Some effects are Pro only and need a subscription. Web, Mac and iOS projects only.
- **Hugeicons** (icons): Use Hugeicons for every icon in the UI, keeping one style and stroke weight throughout and colouring with currentColor. No emoji and no hand-drawn SVG icons. iOS: The page lists no native iOS package (no Swift Package Manager or CocoaPods). Mac: The page lists no native macOS package (no Swift Package Manager or CocoaPods). Web: Pro icons need a paid licence; only part of the set is free.
- **Thinking Orbs** (loading): Use Thinking Orbs for every AI "thinking" or loading state instead of a spinner. On web render <ThinkingOrb state="..." size={64|20} /> and pick the state that matches the activity (e.g. searching, composing). Set up: Web: `npm install thinking-orbs`; Mac: `Swift Package Manager: add https://github.com/Jakubantalik/Libraries.dev (branch main), product ThinkingOrbsKit`; iOS: `Swift Package Manager: add https://github.com/Jakubantalik/Libraries.dev (branch main), product ThinkingOrbsKit`. iOS: The page doesn't explicitly say the Swift package supports iOS or macOS, and it gives no CocoaPods option. Mac: The page doesn't explicitly say the Swift package supports macOS; SwiftUI support is implied only. Web: Requires React 18 or newer; the page lists only an npm install line.

### Releasing

- Agents release, deploy, tag and upload (TestFlight, App Store,
  production) when the work calls for it, and say in the handoff what was
  shipped and where. Araniko blocks none of it.
- Each project's Nayo commits and pushes its own main.
- Every release gets a changelog entry in the user's voice: what changed for
  the person using the app, not which files moved.
- Version numbers are semantic. A release that changes stored data bumps
  the minor version and ships a migration with a rollback note.

### Security basics

- No secrets in code, logs or commit history. Use the environment or a keychain.
- Check every input that crosses a boundary: forms, files, network, other processes.
- Give each part only the access it needs.
- Never turn off a security check to make something work.

## Checks
`scripts/check-ios.sh` must pass.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
