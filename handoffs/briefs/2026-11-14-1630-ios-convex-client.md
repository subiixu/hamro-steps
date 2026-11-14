# iOS phase 3: real Convex services (auth + family) behind the existing protocols
worker: claude
model: claude-opus-5-5
effort: high
started: 2026-11-14 15:35 · terminal: s_21a6035f
redo: handoffs/2026-11-14-1510-ios-convex-client.md
why: Redo 2: second opinion (15:34) still Blocking. 1) performRefresh must check captured generation BEFORE reading storage/calling /auth/refresh (keep post-response check); test queued refresh starting after a replacement sign-in. 2) Keychain delete failure in signOut must not be swallowed: stay invalidated until deletion succeeds, retry, persist a signed-out marker so restart can't restore session/cached user; test failed removal + offline logout, recovery, restart. Add a 'Redo 2' section.
isolate: /Users/subixu/.jarvis-worktrees/hamro-steps/ios-convex-client · branch: jw/ios-convex-client
Tasks: T-4, T-5, T-6
files: ios/project.yml, ios/HamroSteps/Services/Convex/**, ios/HamroStepsTests/Convex*.swift

## Goal
Add `ConvexAuthService` and `ConvexFamilyService` implementing the existing `AuthService` and `FamilyService` protocols against the merged Convex backend, in new files only. Done = `scripts/check-ios.sh` green in your worktree, with unit tests over a stubbed transport. This phase doesn't switch the app over. The one-line swap in `AppLaunch.services()` is listed in your handoff for Jarvis to apply, because another worker owns `HamroStepsApp.swift`.

## Context
Read narrowly: grep -n / sed -n ranges.
- Backend API: "API reference" in `handoffs/merged/2026-11-14-1403-convex-core.md`.
- Protocols: `grep -n "protocol\|func " ios/HamroSteps/Services/FamilyService.swift ios/HamroSteps/Services/AuthService.swift`.
- **Dependency (approved by Jarvis):** add the Convex Swift SDK via SPM in `project.yml`: `https://github.com/get-convex/convex-swift`, product `ConvexMobile`, latest release. Read its sources for the `ConvexClientWithAuth` / `AuthProvider` API.
- **Auth:**
  - Implement an `AuthProvider` over our HTTP endpoints: `POST {siteURL}/auth/apple`, `/auth/refresh` and `/auth/logout`.
  - Store the refresh token in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`, so background HealthKit sync works) and keep the access token in memory. Refresh it 2 minutes before expiry and on `invalid_token`.
  - The session survives app restarts (the ios.md rule: a forced sign-out is a bug unless the token was revoked).
  - Sign-out calls `/auth/logout` and then clears the Keychain.
- **Configuration:** `CONVEX_URL` and `CONVEX_SITE_URL` come from build settings in Info.plist (`$(CONVEX_URL)`). Use placeholder values in `project.yml` with a comment. Jarvis/user sets them per environment.
- **Family service:**
  - Map each function with `client.mutation` / `query` / `action`.
  - `familyTodayUpdates` uses `client.subscribe` to `home:familyToday`.
  - Decode `ConvexError` data `{code}` into `FamilyServiceError`.
  - `deleteMyAccount` treats `revoked`, `skipped` and `queued` all as success.
- **Tests:** a fake transport layer (a protocol around the client calls) covering token refresh timing, refresh on `invalid_token`, Keychain persistence (an in-memory keychain fake), error-code decoding, and a JSON fixture decode for each backend return shape.

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
- May touch: the `files:` list only (new files plus the package entry in project.yml)
- Must not touch: existing Swift files, `backend/`, `docs/`

## Checks
`ultron check` in your worktree.

## Questions first
No questions expected; build straight through.
