# iOS: simulator screenshots of every v1 screen + a visual issues list
worker: claude
model: sonnet
effort: medium
started: 2026-11-14 14:21 · terminal: s_08faa7be
Tasks: T-4, T-6
files: handoffs/screens/**

## Goal
Screenshots of each screen from the merged-pending iOS phase, using the debug launch arguments, saved as `handoffs/screens/2026-11-14-ios-<screen>[-dark|-ax].png`, plus a short list of visual problems you see (clipping, truncation, contrast, misalignment). Don't change any code.

## Context
Read narrowly: from `handoffs/2026-11-14-1425-ios-home-mock.md`, read only the "Debug launch arguments" line (`grep -n "Debug launch" …`).
- Build once: `cd ios && xcodegen generate && xcodebuild build -project HamroSteps.xcodeproj -scheme HamroSteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/hamro-dd -quiet`. Then `xcrun simctl install/launch` with `-screen <name> -mockSteps`, and `xcrun simctl io booted screenshot`.
- Screens: welcome, name, health, create-name, create-goal, invite, join, home, settings, me. Home additionally in dark mode (`xcrun simctl ui booted appearance dark`) and at accessibility text size (`xcrun simctl ui booted content_size accessibility-extra-large`). Reset the appearance and text size afterwards.

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

## Scope
- May touch: `handoffs/screens/**`, your handoff
- Must not touch: all code (`ios/`, `backend/`, …)

## Checks
none (no code changes). List the files you saved.

## Questions first
No questions expected; build straight through.
