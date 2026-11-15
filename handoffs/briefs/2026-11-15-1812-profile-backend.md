# Profile backend: photo avatar, city, birthday
worker: claude
model: claude-opus-5-5
effort: medium
started: 2026-11-15 18:13 · terminal: s_afe51b97
Tasks: T-39 (part 1 of 2)
files: backend/convex/crons.ts, backend/convex/schema.ts, backend/convex/users.ts, backend/convex/home.ts, backend/convex/feed.ts, backend/convex/families.ts, backend/convex/lib/*.ts, backend/tests/*.ts

## Goal
Members can set a profile photo, a typed city and a birthday, and family members see them. The API below is a fixed contract: an iOS worker is building against it right now, so don't rename anything.

## Contract (build exactly this)
Schema `users` gains (all optional): `photoId: v.id("_storage")`, `city: v.string()`, `birthday: v.string()` ("YYYY-MM-DD"). Keep `avatarColor` in the schema and keep returning it where it's returned today (older builds decode it), but nothing new uses it.
- `users:generateAvatarUploadUrl` mutation, no args → string (`ctx.storage.generateUploadUrl()`), requires a signed-in user.
- `users:setAvatar` mutation `{ storageId: Id<"_storage"> }` → null. Deletes the previous photo blob if any. Reject a blob over 5 MB or with a content type not starting `image/` (check `ctx.db.system.get(storageId)`), deleting the rejected blob; use the existing error helpers in lib/errors.ts.
- `users:removeAvatar` mutation, no args → null. Deletes the blob, clears `photoId`.
- `users:updateProfile` adds optional `city: v.optional(v.string())` (trimmed, max 40 chars, empty string clears it) and `birthday: v.optional(v.union(v.string(), v.null()))` (must be a real date "YYYY-MM-DD", not in the future, year ≥ 1900; null clears). Existing `name`/`timezone` args unchanged.
- `users:me` adds `photoUrl: string | null` (`ctx.storage.getUrl`), `city: string | null`, `birthday: string | null`.
- Every per-member object returned by `home:familyToday`, `home:familyWeek` (if it has member objects), the feed actors in `feed.ts`, and family member lists in `families.ts` adds `photoUrl`, `city`, `timezone` (string | null each). Birthday only on `home:familyToday` members (`birthday: string | null`).
- Account deletion (`deleteAccountData` in users.ts / lib/cleanup.ts) also deletes the photo blob.

## Context
- Read narrowly: `backend/convex/users.ts` lines 30-70 (me, updateProfile, cleanName), `home.ts` 13-60, `feed.ts` 40-60, `schema.ts` users table. Copy the validation style of `cleanName` and the test style of `backend/tests/auth.test.ts` (convex-test, helpers.ts).
- Product rules: no device location; city is a free-text label the user types. Local time is computed on the phone from `timezone`, which sign-in already stores.
- Don't deploy to Convex; Jarvis does that after merge.

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
- May touch: the files in `files:` above.
- Must not touch: `ios/`, `web/`, `backend/package.json` (ask in the handoff if you need a dependency).

## Phase
One phase: schema + functions + tests.

## Checks
`scripts/check-backend.sh` passes. Add tests for: setAvatar replaces and deletes the old blob; rejects non-image / oversize; removeAvatar; city trim/clear/length; birthday valid/invalid/future/null; me and familyToday return the new fields; account deletion deletes the blob.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. If you have none, build straight through.
