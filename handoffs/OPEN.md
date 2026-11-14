# Open items

Jarvis reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Jarvis
stops, this file must hold everything a fresh session needs: the user may
clear Jarvis after a long idle.

Jarvis session: s_6f0aa16b
Usage band: <green | amber | red> — `handoffs/bin/jarvis status` writes it from the statusline reading

## Questions for the user
- manual test (web pages): open web/invite/index.html?code=K7M2QX and web/privacy/index.html in Safari; check dark mode; founders review the DRAFT privacy text + set real contact email and TestFlight URL.
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
- 2026-11-14 14:39 · claude/claude-opus-5-5 medium · term s_253ca1b2 · handoffs/briefs/2026-11-14-1615-ios-model-fixes.md
- 2026-11-14 14:39 · claude/claude-opus-5-5 medium · term s_d484ac05 · handoffs/briefs/2026-11-14-1615-ios-activity-placement.md
- 2026-11-14 14:06 · codex/gpt-6-astra high · term s_9dd4f84f · handoffs/briefs/2026-11-14-1440-app-icon.md
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis
- convex-core redo #2 (s_d15669): Apple revoke queue must keep tokens until revoked + recovery cron. Then fresh second opinion → merge (--anyway if iOS check red from WIP) → spawn backend phase 2.

## To-do
- PRD = docs/PRD.md (backend Convex, invites code-first for pilot). Tasks T-4…T-10. Supabase work dropped (archived ~/.jarvis-archive/hamro-steps/).
- Backend phase 2 — spawn the moment convex-core merges (--after it), split in 3 narrow briefs run sequentially (schema.ts shared): 2a walks+status (+familyToday fields), 2b feed+reactions, 2c push/devices/prefs/nudge. Contract docs/contract-activity.md: walks (F9–F11), status (F12), feed auto-events + 5 reactions (F13–F14), APNs action + device tokens + per-type mutes + evening nudge (F15–F16). T-7…T-10. APNs key/env = user supplies; never to free models.
- iOS phase 3 (after convex-core merges; ios-home-mock merged ✓): wire ConvexMobile (convex-swift SPM, Jarvis approves) + auth endpoints, replace mock service; background delivery sync.
- iOS phase 4a placement + model fixes RUNNING. Then: push registration/routing (after backend 2c). ios-model-fixes handoff names a HamroStepsApp.swift line to switch reload()→refresh() — apply after placement merges.
- Host web/ (invite + privacy) somewhere — user picks host; TestFlight URL + privacy email placeholders to fill.
- App icon (codex) → Jarvis installs design/app-icon into ios AppIcon.appiconset after merge.
- User setup before device testing: Apple Developer team id + SIWA capability, Convex project (user creates/logs in), APNs key, privacy policy URL before TestFlight.
