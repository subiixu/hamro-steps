# Open items

Jarvis reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Jarvis
stops, this file must hold everything a fresh session needs: the user may
clear Jarvis after a long idle.

Jarvis session: s_6f0aa16b
Usage band: <green | amber | red> — `handoffs/bin/jarvis status` writes it from the statusline reading

## Questions for the user
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
- 2026-11-14 13:39 · claude/claude-opus-5-5 high · term s_50e3db05 · handoffs/briefs/2026-11-14-1338-supabase-schema.md
- 2026-11-14 13:39 · claude/claude-opus-5-5 high · term s_bb05b6a4 · handoffs/briefs/2026-11-14-1338-ios-scaffold.md
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis
<!-- - handoff to review: handoffs/<file>.md · migration to apply · release to cut -->

## To-do
- Record the launch message's tasks once a numbered message exists (launch prompt wasn't numbered): T "Build Hamro Steps v1" — stack decided 2026-11-14: iPhone-only SwiftUI + HealthKit, Supabase; v1 = invites, today view, weekly leaderboard, family daily goal, streaks, cheers/nudges (push), home-screen widget.
- Phase 2 (after both phase-1 handoffs merge): iOS Sign in with Apple via Supabase Auth (supabase-swift SPM — Jarvis approves the dependency), create/join family by invite code + share sheet, step sync (upsert_steps on foreground + background delivery), Today screen (family_today) + weekly leaderboard. opus/high, --after both handoffs.
- Phase 3a: family daily goal ring, streaks on Me + Today, cheers/nudges UI + Edge Function sending APNs on cheers insert (APNs key = user supplies; never to free models).
- Phase 3b (isolated or after 3a): WidgetKit extension + app group showing today's family total.
- User setup needed before device testing: Apple Developer team id, hosted Supabase project (user creates; Jarvis never pushes migrations to prod without asking), Sign in with Apple capability.
