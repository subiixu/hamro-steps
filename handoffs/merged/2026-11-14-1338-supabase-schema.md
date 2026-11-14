# Supabase schema: families, invites, daily steps, goals, streaks, cheers, with RLS and pgTAP tests
worker: claude
model: claude-opus-5-5
effort: high
started: 2026-11-14 13:53 · terminal: s_ab7939d6
redo: handoffs/2026-11-14-1349-supabase-schema.md
why: Second opinion Blocking: owner hand-off races with concurrent successor departure (migration:244); serialize per family + regression test — see handoffs/reviews/2026-11-14-1349-supabase-schema-second.md
files: supabase/**

## Goal
A local Supabase project in `supabase/` (`supabase init`) with SQL migrations for Hamro Steps' data model, row-level security so a user sees only their own families, the RPCs the app needs, and pgTAP tests proving the RLS and RPCs. Done = `scripts/check-db.sh` passes (it starts the local stack, `supabase db reset --local`, `supabase test db --local`). Local only: never link, push to, or touch a hosted Supabase project.

## Context
- Product: Hamro Steps, a shared family step tracker, iPhone app (another worker is building `ios/` now; don't touch it). Auth will be Sign in with Apple through Supabase Auth, so users come from `auth.users`.
- Data model (decided; refine names/types, keep the shape):
  - `profiles` (id = auth.users.id, display_name, `avatar_color text` (no emoji avatars), `personal_goal int default 8000`, `timezone text`, created_at). Auto-created by a trigger on `auth.users` insert.
  - `families` (id, name, `invite_code` short unique human-friendly code, e.g. 6 chars without ambiguous letters, `daily_goal int` = combined family target, created_by, created_at).
  - `family_members` (family_id, user_id, role `owner|member`, joined_at; PK both). A user may be in more than one family.
  - `daily_steps` (user_id, `day date` in the user's local calendar, steps int >= 0, updated_at; PK user_id+day). Written only by the user themselves via an upsert RPC; a later sync for the same day replaces the value (HealthKit totals only grow, but accept any value).
  - `cheers` (id, family_id, from_user, to_user, kind `cheer|nudge`, created_at). Sender and receiver must share that family; rate limit: at most 1 per sender→receiver per kind per hour (enforce in the RPC).
  - `device_tokens` (user_id, apns_token, created_at) for push later; owner-only access.
- RPCs (security definer where needed, `search_path` pinned): `create_family(name, daily_goal)` → family (caller becomes owner); `join_family(invite_code)` → family (idempotent); `leave_family(family_id)`; `regenerate_invite_code(family_id)` owner only; `upsert_steps(day, steps)`; `family_today(family_id, day)` → each member's steps that day + the total vs daily_goal; `family_leaderboard(family_id, week_start date)` → members ranked by 7-day total; `my_streak()` → consecutive days up to today (or yesterday, if today isn't met yet) where steps >= personal_goal; `send_cheer(family_id, to_user, kind)`.
- RLS on every table. A user can read profiles and daily_steps of anyone who shares a family with them, and nothing else. A user can write only their own rows. Family settings are owner-editable only.
- Push delivery for cheers comes later (an Edge Function); for now just the table + RPC, and leave a short comment where the trigger/webhook will go.

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
- May touch: `supabase/**`
- Must not touch: `ios/`, `scripts/`, `handoffs/` (except your handoff), `.ultron/`, `CLAUDE.md`, `AGENTS.md`
- Shared files: none

## Phase
The whole database layer for v1. No Edge Functions yet.

## Checks
`ultron check` (runs `scripts/check-db.sh`; `check-ios.sh` belongs to the other worker, so report its result but don't fix it). pgTAP tests in `supabase/tests/` must cover: a non-member can't read another family's steps or profiles; a member can; join by invite code works and is idempotent; a wrong code fails; `upsert_steps` replaces the value; leaderboard ordering; streak counting across a gap and with today not yet met; cheer to a non-family user fails; the cheer rate limit. Simulate users with `set local role authenticated` + `request.jwt.claims`. In the handoff, list each RPC's signature so the iOS phase can code against it.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
