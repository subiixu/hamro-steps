# iOS: App Store audit fixes (privacy link, encryption key, tinted icon alpha)
worker: claude
model: sonnet
effort: medium
Tasks: T-24
files: ios/project.yml, ios/HamroSteps/Features/Me/MeView.swift, ios/HamroSteps/Features/Onboarding/WelcomeView.swift, ios/HamroSteps/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png, docs/app-store-preflight.md

## Goal
The three code-side items from docs/app-store-preflight.md are fixed: #8 privacy link, #9 `ITSAppUsesNonExemptEncryption`, #11 tinted icon alpha. The audit table says so.

## Context
- Audit: docs/app-store-preflight.md (read rows 8, 9, 11 with grep -n).
- Privacy page: https://subiixu.github.io/hamro-steps/privacy/
- Notes that matter here: built for parents (large text, plain words); use Hugeicons for any icon (an existing `Icon` enum is in ios/Shared/UI/Icon.swift; reuse a case, don't hand-draw); no red failure states.
- Push no longer needs row #6: `aps-environment` is merged, and the app sends alert pushes only (no silent pushes), so no `UIBackgroundModes: remote-notification`. Mark #6 OK in the doc with that reason.

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
- May touch: the files in `files:`.
- Must not touch: anything else. Another worker is editing ios/HamroSteps/App/HamroStepsApp.swift and Services/Convex; stay out.
- Shared: ios/project.yml: one line, `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` in the target's base settings, next to the other INFOPLIST_KEY_ lines.

## Phase
1. Me tab: a "Privacy policy" row in an existing section that opens the URL (SwiftUI `Link`). Welcome: a small "Privacy policy" link under the Sign in with Apple button, same URL.
2. project.yml: the encryption key.
3. Flatten AppIcon-1024-tinted.png to no alpha without changing its pixels' look (e.g. `sips` or a Python/PIL one-liner onto the same background the tinted variant uses; check `sips -g hasAlpha` says no after).
4. Update rows 6, 8, 9, 11 in docs/app-store-preflight.md.

## Checks
`ultron check` green; paste the result. Screenshot Me and Welcome in the simulator (`-screen` launch args exist in AppLaunch) and give the paths.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
