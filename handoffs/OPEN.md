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
- 2026-11-14 14:02 · claude/claude-opus-5-5 high · term s_552f0089 · handoffs/briefs/2026-11-14-1415-convex-core.md
- 2026-11-14 13:53 · claude/claude-opus-5-5 high · term s_ab7939d6 · handoffs/briefs/2026-11-14-1338-supabase-schema.md
- 2026-11-14 13:39 · claude/claude-opus-5-5 high · term s_50e3db05 · handoffs/briefs/2026-11-14-1338-supabase-schema.md
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- PRD = docs/PRD.md (backend Convex, invites code-first for pilot). Tasks T-4…T-10. Supabase work dropped (archived ~/.jarvis-archive/hamro-steps/).
- Backend phase 2 (after convex-core merges, --after it): walks (F9–F11), status (F12), feed auto-events + 5 reactions (F13–F14), APNs action + device tokens + per-type mutes + evening nudge (F15–F16). T-7…T-10. APNs key/env = user supplies; never to free models.
- iOS phase 3 (after convex-core AND ios-home-mock merge): wire ConvexMobile (convex-swift SPM, Jarvis approves) + auth endpoints, replace mock service; background delivery sync.
- iOS phase 4 (after backend phase 2): walking button/badge, status picker, feed + reactions, push registration + mute settings.
- Invite web page (pilot): static page showing the 6-char code + TestFlight link — needs hosting choice later.
- User setup before device testing: Apple Developer team id + SIWA capability, Convex project (user creates/logs in), APNs key, privacy policy URL before TestFlight.
