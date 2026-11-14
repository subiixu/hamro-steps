# Activity contract: walks, status, feed, reactions, notifications (PRD F9–F16)

Decided by Jarvis, 2026-11-14. The Convex backend (phase 2) implements it and the iOS app codes against it. Change it only through Jarvis.
All days are Nepal days (Asia/Kathmandu). Errors are `ConvexError({code})`.

## Walks (F9–F11)
A walk belongs to a user and shows in every family they're in.
- `startWalk()` → `{walkId, startedAt, endsAt}`, where `endsAt = startedAt + 2h`. It pushes "walk started" to every member of each of the walker's families, except the walker and anyone who muted walks, and adds a `walk_started` feed event per family.
  - Errors: `already_walking`, `walk_limit_reached` (3 starts per user per Nepal day).
- `stopWalk()` → void. A no-op when not walking.
- A scheduled function (`ctx.scheduler.runAt(endsAt)`) ends a walk that is still open.
- `familyToday.members[].walkingSince: number | null` (ms epoch), `walkEndsAt: number | null`.

## Status (F12)
- The presets, as enum keys: `at_work`, `at_home`, `commuting`, `working_out`, `on_a_hike`, `resting`, `travelling`. The labels are the PRD's ("At work", …).
- `setStatus({preset?: key, text?: string ≤ 30 chars, expiresAt?: number})`: exactly one of `preset`/`text`. Text is trimmed and its length is counted as UTF-16 code units (JS `.length`), the same on both sides. `expiresAt` defaults to now + 24 h (the app omits it for the 24 h choice, so server time applies; "until tonight" is 21:00 in the phone's time zone), and must be in the future and ≤ now + 7 days.
  - Errors: `invalid_status`, `invalid_expiry`.
- `clearStatus()`.
- `familyToday.members[].status: {preset: key | null, text: string | null, expiresAt: number} | null`. An expired status reads as null.

## Feed (F13)
- `feed(familyId)` → events from the last 3 Nepal days, newest first, at most 100.
- Each event: `{id, type, actor: {userId, name, avatarColor} | null, day, createdAt, data, reactions: [{emoji, count}], myReaction: emoji | null}`.
- Types. `member_*` and `family_*` are created at most once per (family, actor, day, type). `walk_started` is created once per walk (per family), so up to 3 per member per day:
  - `member_5k` / `member_10k`: on `syncSteps` crossing 5,000 or 10,000 for today.
  - `family_50` / `family_100`: on the family total crossing 50% or 100% of today's goal; `actor` is null.
  - `walk_started`, with `data.walkId`.
- `family_100` pushes "goal hit" to members who haven't muted it.

## Reactions (F14)
- The fixed set, exactly these 5 emoji: 👏 ❤️ 🙌 🔥 😄. These are user content per the PRD, not icons, so the no-emoji-icons rule doesn't apply here.
- `react(eventId, emoji)`: one reaction per user per event. Sending the same emoji again removes it; a different emoji replaces it.
  - Errors: `invalid_emoji`, `not_member` (also returned for an event that doesn't exist or isn't visible).
- A reaction to someone's event pushes them "X reacted 👏 to …" unless they muted reactions or they reacted to their own event.

## Notifications (F15, F16)
- `registerDevice(apnsToken: hex string, environment: "sandbox" | "production")`, `unregisterDevice(apnsToken)`.
- `notificationPrefs()` → `{walkStarted, goalHit, reactions, eveningNudge}`, all booleans. Defaults: true, true, true, false.
- `setNotificationPrefs(partial)`.
- Evening nudge: a cron at 19:00 Nepal time. For each family under its goal, it pushes members who opted in, with supportive wording ("Your family is at 62% today. A short evening walk would help everyone get there.").
- Push payload: `aps.alert {title, body}`, `aps.sound "default"`, plus `{type, familyId, eventId?}` so the app can route a tap.
