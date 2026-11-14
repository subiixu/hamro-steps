# Supabase schema: families, invites, daily steps, goals, streaks, cheers, with RLS and pgTAP tests
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1338-supabase-schema.md
## What the user asked
The whole v1 database layer in a local Supabase project. It covers profiles, families with invite codes, membership, daily steps, cheers and nudges, and device tokens. Each table has row-level security so people only see their own families. The brief also asked for the RPCs the iPhone app needs and pgTAP tests that prove them. Local only.

## What changed
- `supabase init` created the project, and one migration holds the whole schema.
- **Ports.** Another local Supabase project (LemFi) was already running on the default 543xx ports, so this project uses **554xx**: API `http://127.0.0.1:55421`, DB `55422`. I didn't touch the other project.
- **Tables.** `profiles`, `families`, `family_members`, `daily_steps`, `cheers` and `device_tokens` all have RLS on.
  - A user can read the profiles and steps of themselves and anyone they share a family with.
  - Families and rosters are readable by members only. Cheers are readable by the sender and receiver only. Device tokens are visible to their owner only.
  - `anon` has no access to anything.
- **What the app can write directly.**
  - Its own profile: `display_name`, `avatar_color`, `personal_goal`, `timezone` (column grants).
  - A family's `name` and `daily_goal`, owner only.
  - Deleting its own device tokens.
  - Everything else goes through the RPCs.
- **New users.** A trigger creates a profile for each new auth user. The name comes from Apple's `full_name`/`name` metadata, otherwise "New member". The avatar colour is picked at random from an 8-colour hex palette.
- **Owner leaves.** If the owner leaves (or deletes their account), the longest-standing member becomes owner. When the last member leaves, the family is deleted. A trigger enforces this, and a unique index allows exactly one owner per family.
- **Invite codes** are 6 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`. Joining ignores case, spaces and dashes.
- **Push.** A comment on `public.cheers` marks where the push trigger or webhook to the Edge Function will go.

### Redo: the owner hand-off race (second-opinion review)
The review was right: an owner and their chosen successor leaving at the same time could both commit and leave the family with nobody as owner. The family's settings and invite code were then stuck. I reproduced it with a two-session test before fixing it.
- **Fix.** Membership changes are now serialised per family. A new `private.lock_family(family_id)` takes a `FOR NO KEY UPDATE` lock on the `families` row, so FK checks from other tables aren't blocked. Every path takes it *before* touching `family_members`:
  - `leave_family` locks first, then deletes.
  - `join_family` reads the family by code `FOR NO KEY UPDATE`. A join can't race the last member's leave. If the family was deleted while the join waited, it returns `invalid_invite_code`.
  - **Account deletion.** A new `BEFORE DELETE` trigger on `profiles` (`on_profile_deleting`) locks all of the user's families in id order before the cascade removes their memberships.
  - `handle_member_removed` takes the lock again, then re-checks. Any future path that forgets to lock first fails with a deadlock error at worst, and never commits an ownerless family.
- **Same-race cases now covered:** the owner leaves while the successor leaves, the owner deletes their account while the successor leaves, and someone joins while the last member leaves. Before the fix, the last one deleted the family the person had just joined.
- I edited the initial migration in place rather than adding a second one, because nothing has been committed or applied anywhere yet.

### RPC signatures (for the iOS phase)
Call these via `supabase.rpc("<name>", params: [...])` with exactly these JSON keys. All require a signed-in user.

| RPC | Params | Returns |
|---|---|---|
| `create_family` | `name text, daily_goal int` | `families` row `{id, name, invite_code, daily_goal, created_by, created_at}`; caller becomes owner |
| `join_family` | `invite_code text` | `families` row; idempotent |
| `leave_family` | `family_id uuid` | void |
| `regenerate_invite_code` | `family_id uuid` | `families` row with the new code; owner only |
| `upsert_steps` | `day date ("YYYY-MM-DD", user's local day), steps int` | `daily_steps` row `{user_id, day, steps, updated_at}`; replaces the day's value |
| `family_today` | `family_id uuid, day date` | jsonb `{family_id, day, daily_goal, total_steps, goal_met, members:[{user_id, display_name, avatar_color, role, personal_goal, steps}]}`; members sorted by steps desc; missing days count as 0 |
| `family_leaderboard` | `family_id uuid, week_start date` | rows `{user_id, display_name, avatar_color, total_steps, rank}` for week_start..week_start+6; ties share a rank |
| `my_streak` | — | int |
| `send_cheer` | `family_id uuid, to_user uuid, kind text ('cheer'\|'nudge')` | `cheers` row `{id, family_id, from_user, to_user, kind, created_at}` |
| `register_device_token` | `apns_token text (hex)` | `device_tokens` row; moves the token to the caller if another account had it |

Errors are SQLSTATE `P0001` with a stable message the app can switch on: `invalid_family_name`, `invalid_daily_goal`, `invalid_invite_code`, `not_a_member`, `not_owner`, `invalid_steps`, `invalid_day` (more than 1 day ahead of UTC), `invalid_kind`, `cannot_cheer_self`, `recipient_not_in_family`, `rate_limited`, `invalid_apns_token`. A missing session gives `not_authenticated` (`28000`).

### Defaults I chose (the brief didn't rule on these; each is easy to change in a follow-up migration)
- **Leaving a family:** ownership passes to the earliest-joined member, and an empty family is deleted.
- **Cheer visibility:** only the sender and receiver can read a cheer. There is no family-wide feed.
- **Rate limit:** it applies per sender → receiver per kind across all families, over a rolling hour. Concurrent sends are serialised with an advisory lock.
- **Streak:**
  - "Today" is today in the caller's `profiles.timezone`, which defaults to `UTC`. **The app should set `timezone` to the device's IANA zone.**
  - The current `personal_goal` applies to past days too; goal history isn't stored.
- **Limits:** `personal_goal` must be 1–100,000, `daily_goal` 1–10,000,000, `display_name` 1–40 characters, family name 1–50 characters.
- **Device tokens:** the token itself is the primary key, and registering goes through `register_device_token`. This stops a shared device from pushing to the wrong account.

## Files
- supabase/.gitignore — created
- supabase/config.toml — created
- supabase/migrations/20261114134000_initial_schema.sql — created
- supabase/tests/01_rls.test.sql — created
- supabase/tests/02_families.test.sql — created
- supabase/tests/03_steps.test.sql — created
- supabase/tests/04_cheers.test.sql — created
- supabase/tests/05_concurrency.test.sql — created

(`supabase/.branches/` and `supabase/.temp/` are CLI state; `supabase/.gitignore` already ignores them.)

## Checks run
`ultron check`: passed · 2 of 2 passed · 52.1 s
- `scripts/check-ios.sh` · passed · 13.3 s
- `scripts/check-db.sh` · passed · 38.8 s

pgTAP: 5 files, 74 tests, all passing. They simulate users with `set local role authenticated` plus `request.jwt.claims`, and cover every case the brief listed:
- Non-members can't read another family's steps or profiles; members can.
- Join by code works, is idempotent and ignores case and dashes. A wrong code fails, and an old code fails after regeneration.
- `upsert_steps` replaces the day's value.
- Leaderboard ordering, ignoring days outside the week.
- Streak with a gap, with today not yet met, and with today met.
- Cheering someone outside the family fails.
- Cheer rate limit, which clears after an hour.

**Concurrency (`05_concurrency.test.sql`, redo).** This file drives two real sessions over `dblink`.
- The three races above each check that the second session actually blocks, then that exactly one correct owner remains (or the family survives).
- Run against the pre-fix migration, its 3 outcome assertions failed (no owner, no owner, family deleted). They pass after the fix. I ran it 3 more times: no flakes.
- Its fixtures are committed, because the sessions are separate. They use their own `c5000000-…` ids and `@race.test` emails, are deleted before and after the run, and I confirmed none were left over.
- It connects to `host=db` with the local default password. That's the db container's network alias, and dblink refuses trust auth for non-superusers. It works only against the local stack, which is all `check-db.sh` targets.

The tests also cover owner/non-owner settings, direct writes being refused, anon access being denied, and owner hand-off and family deletion on leave.

Also checked:
- `supabase db lint --local`: no schema errors.
- REST smoke test against the local API: anon gets `42501` on an RPC and on a table. A signed-up local user can call `create_family`, `upsert_steps`, `family_today` and `family_leaderboard` with the JSON shapes above, and `join_family` with a bad code returns `invalid_invite_code`.

Not checked: anything on a hosted project (none was linked), and Sign in with Apple. `[auth.external.apple]` is still disabled in `config.toml` because it needs Apple credentials.

## Libraries used
none touched

## Questions for the user
none

## Notes for Jarvis
- **Docker:** I started Docker Desktop, which wasn't running. That also auto-started the other project's (LemFi) local Supabase containers on 543xx. I left them running.
- **Ports:** this project's local stack is on 554xx. The iOS worker's local config should point at `http://127.0.0.1:55421`. Get the local publishable key from `supabase status`.
- **Applying to hosted:** nothing has been applied to a hosted project. When there is one, `supabase link` and `supabase db push` are yours (or the user's) to run.
- **Redo for the second-opinion review:** the finding in `handoffs/reviews/2026-11-14-1349-supabase-schema-second.md` is fixed, with a regression test (see "Redo" above). The `dblink` extension is created only inside the test's own transaction, which is rolled back. The schema doesn't depend on it.
- **Known gaps for later phases:**
  - No rate limit on `join_family` attempts. Brute-forcing the 31⁶ code space is impractical but not impossible.
  - No way for an owner to remove a member.
  - No family size cap.
  - No realtime publication for `daily_steps`.
- **Suggested commit message:** `Add Supabase schema: families, invites, daily steps, streaks, cheers with RLS, RPCs and pgTAP tests (membership changes serialised per family)`

## Checks (run by Ultron)
Passed · 2 of 2 · 53.1 s · 2026-11-14 13:51 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 15.5 s
- `scripts/check-db.sh` · passed · 37.6 s

## Outcome (Jarvis)
Dropped 2026-11-14: the PRD (docs/PRD.md) moved the backend to Convex. Not merged; supabase/ archived to ~/.jarvis-archive/hamro-steps/supabase-2026-11-14.tgz. The second opinion (Blocking, owner hand-off race) is moot.
