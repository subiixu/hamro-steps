# Convex backend 2b: family feed auto-events and reactions (contract F13–F14)
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1700-convex-feed-reactions.md
## What the user asked
(T-9) The Feed and Reactions sections of `docs/contract-activity.md` in Convex, with tests. No push yet: 2c adds it. Each place a push goes gets a marked `// 2c: push` comment.

## What changed
- **Feed events.** Every type is created at most once per (family, day, type, actor). `postEvent` in `lib/feed.ts` checks the `by_family_day_type_actor` index before inserting.
  - `syncSteps`, today only: when the user's value goes from below 5,000 / 10,000 to at or above it, `member_5k` / `member_10k` is posted in each of their families. Each family's live total before and after is computed (after minus the user's change). Crossing 50% or 100% of `dailyGoal` posts `family_50` / `family_100` with no actor. Syncs that go down post nothing.
  - Late syncs for closed days post nothing. I replaced the old phase-2 comment in `applyLateSync` with a note saying so.
  - `walks.startWalk` posts `walk_started` with `data.walkId` in each of the walker's families, in place of the marked comment.
- **`feed.feed({familyId})`** gives `not_member` to outsiders. It returns events whose `day` is in the last 3 Nepal days, newest first by `createdAt`, at most 100. Each event is `{id, type, actor: {userId, name, avatarColor}|null, day, createdAt, data, reactions: [{emoji, count}], myReaction}`. Reactions follow the fixed order 👏 ❤️ 🙌 🔥 😄, and emoji with zero count are left out.
- **`feed.react({eventId, emoji})`** returns `{myReaction: emoji|null}`. The same emoji again removes it and a different one replaces it. ❤ (U+2764 without VS16) is stored as ❤️. Anything outside the 5 gives `invalid_emoji`. `eventId` is taken as a string, so a malformed id, a missing event, an event in a family the caller isn't in, or an event older than the 3-day feed window all give `not_member`.
- **Cleanup**, in `lib/cleanup.ts` at the marked spots:
  - Leaving or being removed deletes the member's events in that family, everyone's reactions to those events, and the member's own reactions to that family's events.
  - Account deletion deletes all of their events, with the reactions to them, and all of their reactions.
  - Deleting an empty family deletes its events and reactions.
- **Purge.** `internal.feed.purgeOld` deletes events with `createdAt` older than 7 days, plus their reactions. It works in batches of 200 and reschedules itself while more remain. It runs from a new daily cron at 19:30 UTC.
- **New error code:** `invalid_emoji`.
- **Push call sites (`// 2c: push`):** `walks.startWalk` (after the walk_started events), `lib/feed.ts` `postTodayStepEvents` (only when family_100 was newly inserted), and `feed.react` (only when the event has an actor who isn't the reactor).

**Schema:**
- `feedEvents`: familyId, type (union of 5 literals), actorId?, day, createdAt, data `{walkId?}`. Indexes `by_family_day_type_actor`, `by_family_created`, `by_actor_family`, `by_createdAt`.
- `reactions`: eventId, userId, emoji. Indexes `by_event`, `by_event_user`, plus `by_user`, which I added for the cleanup paths.

## Files
- backend/convex/feed.ts — created
- backend/convex/lib/feed.ts — created
- backend/convex/schema.ts — modified
- backend/convex/steps.ts — modified
- backend/convex/walks.ts — modified
- backend/convex/crons.ts — modified (one cron line)
- backend/convex/lib/cleanup.ts — modified
- backend/convex/lib/constants.ts — modified
- backend/convex/lib/errors.ts — modified
- backend/convex/_generated/api.d.ts — modified
- backend/tests/feed.test.ts — created

## Checks run
`ultron check`: passed · 2 of 2 passed · 4m 16s
- `scripts/check-ios.sh` · passed · 4m 10s
- `scripts/check-backend.sh` · passed · 6.1 s

Backend: typecheck clean, **106/106 tests** passing (88 existing + 18 new in `tests/feed.test.ts`). The new tests cover:
- Step events:
  - member_5k/10k are posted once each in both of a member's families, including when steps drop and cross the same thresholds again.
  - One sync crossing both thresholds posts both.
  - family_50/100 are posted once each with a null actor, including when the total crosses 100% a second time.
- A late sync after `closeDay` posts nothing.
- walk_started is posted in each family with `data.walkId`, and a second walk that day posts nothing.
- Feed:
  - The 3-day window, with the 4th day back excluded.
  - Newest-first order and the 100 cap, tested with 123 events.
  - `not_member` for outsiders.
  - Reaction counts in the fixed order, and `myReaction` per viewer.
- React:
  - Add, replace and remove.
  - ❤ is normalised to ❤️, and sending ❤️ then toggles it off.
  - `invalid_emoji` for 👍, the empty string, a doubled emoji and plain text.
  - `not_member` for an outsider, an event outside the window, a deleted event and a malformed id.
- Cleanup: leave, organiser removal, account deletion and an emptied family, each checking exactly which events and reactions survive.
- Purge: the boundary at 7 days ± 1 ms, reactions deleted with their event, and 250 events cleared over two batches through the scheduler.

Not checked: a real Convex deployment, or whether the cron actually fires. I tested the cron's function, not its schedule. `_generated/api.d.ts` was edited by hand: two module imports (`feed`, `lib/feed`) in codegen's form.

## Libraries used
none touched (backend only)

## Notes for Jarvis
- **walk_started is once per day per family.** The contract (F13) says every type, walk_started included, is at most once per (family, actor, day, type), and I followed that. So only a user's first walk of the day posts an event, even though they may walk 3 times. The brief's "one per family, with data.walkId" is ambiguous on this. If the user wants an event per walk, drop the `postEvent` uniqueness check for walk_started in `walks.ts` / `lib/feed.ts`. It's a small change.
- Family 50%/100% use "crossing on this sync": the total before is below the threshold and the total after is at or above it. A goal lowered under the current total posts nothing until a sync crosses it, and then only if that sync crosses it.
- `react` returns `{myReaction}`. The contract doesn't specify a return value, so the iOS client can rely on this or ignore it.
- iOS needs the new error code `invalid_emoji`, plus `api.feed.feed` and `api.feed.react`.
- Suggested commit message: `Convex feed and reactions: once-per-day member 5k/10k, family 50%/100% and walk_started events, 3-day feed with reaction counts, toggle/replace reactions, cleanup on leave/delete, daily 7-day purge`

## Second opinion
Skipped at merge: 106 backend tests green; combined second opinion over backend 2a–2c after 2c (2026-11-14 14:53)

## Checks override
Merged anyway: iOS check red only from iOS placement worker's in-progress edits (2026-11-14 14:53)
