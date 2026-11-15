# Profile photo: server-side account guard (second-opinion fixes)
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-15 18:41 · terminal: s_20564e20
Tasks: T-39
files: backend/convex/users.ts, backend/tests/profile.test.ts, ios/HamroSteps/Features/Profile/ProfileEditView.swift, ios/HamroSteps/Services/Convex/ConvexAuthService.swift, ios/HamroSteps/App/SessionStore.swift, ios/HamroSteps/Services/FamilyService.swift, ios/HamroSteps/Services/MockAuthService.swift, ios/HamroStepsTests/ProfileTests.swift, ios/HamroStepsTests/TestSupport.swift

## Goal
A photo picked by account A can never be set on account B, however the sign-out/sign-in races. Close both findings in `handoffs/reviews/2026-11-15-1814-profile-ios-second.md` (read it) with one server-side guard instead of more client-side checks.

## Design (decided)
- Backend: `users:setAvatar` takes `{ storageId, userId: v.id("users") }`. After `requireUser`, if `user._id !== args.userId` → `fail("not_authorized")` (or the closest existing code in lib/errors.ts), before any read or delete. Keep the existing ownership/size/type checks. Test: user B calling setAvatar with A's userId fails and changes nothing.
- iOS: capture the signed-in `userId` at the moment the person **starts** a photo action (PhotosPicker selection change / camera result / Remove) in `ProfileEditView`, before `loadTransferable` or conversion. Pass it through `SessionStore.setPhoto` → `AuthService.setPhoto(jpeg:userId:)` → Convex `setAvatar({storageId, userId})`. `SessionStore` throws `CancellationError` up front if `user?.id` no longer equals that id. Because the server compares against whoever's token sends it, an auth retry as B is rejected by the server (finding 2), and a late picker load is rejected client-side and server-side (finding 1).
- Keep the existing generation/epoch guards; they're fine as a first line.
- Map the new server error to no notice when it comes from this path (treat like CancellationError).
- `removeAvatar`: also take `userId` with the same server check (same race shape).

## Context
The previous handoff `handoffs/2026-11-15-1814-profile-ios.md` (status: done) describes the feature and the first round of fixes; read only its "Review fixes" section. The backend for T-39 is merged and deployed (dev); don't deploy, Jarvis does.

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
- Must not touch: anything else; no new dependencies.

## Phase
One phase. **Write your handoff by updating `handoffs/2026-11-15-1814-profile-ios.md`**: add a "Review fixes, round 2" section, add your files to its Files list (backend files included), update Checks run, keep status: done. Don't create a new handoff file.

## Checks
`ultron check` passes (both scripts). New tests: backend B-with-A's-userId rejected for setAvatar and removeAvatar; iOS: photo action started as A, then sign-out + sign-in as B during a paused load → no `users:setAvatar` call; Convex transport sends `userId` in setAvatar args.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. If you have none, build straight through.
