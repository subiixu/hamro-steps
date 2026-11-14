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
- 2026-11-14 14:40 · claude/claude-opus-5-5 high · term s_07720fdd · handoffs/briefs/2026-11-14-1630-ios-convex-client.md · isolate: /Users/subixu/.jarvis-worktrees/hamro-steps/ios-convex-client · branch: jw/ios-convex-client
- 2026-11-14 14:39 · claude/claude-opus-5-5 medium · term s_253ca1b2 · handoffs/briefs/2026-11-14-1615-ios-model-fixes.md
- 2026-11-14 14:39 · claude/claude-opus-5-5 medium · term s_d484ac05 · handoffs/briefs/2026-11-14-1615-ios-activity-placement.md
- 2026-11-14 14:06 · codex/gpt-6-astra high · term s_9dd4f84f · handoffs/briefs/2026-11-14-1440-app-icon.md
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis
- ios-model-fixes done (checks green): merge AFTER ios-activity-placement (shared MockFamilyService.swift); skip second opinion only with reason (fixes of reviewed findings).

## To-do
- PRD = docs/PRD.md (backend Convex, invites code-first for pilot). Tasks T-4…T-10. Supabase work dropped (archived ~/.jarvis-archive/hamro-steps/).
- Backend phase 2 (combined second opinion over 2a–2c after 2c merges; 2a skipped one) — spawn the moment convex-core merges (--after it), 2a merged ✓; 2b feed+reactions RUNNING; then 2c push/devices/prefs/nudge (--after 2b). Contract docs/contract-activity.md: walks (F9–F11), status (F12), feed auto-events + 5 reactions (F13–F14), APNs action + device tokens + per-type mutes + evening nudge (F15–F16). T-7…T-10. APNs key/env = user supplies; never to free models.
- iOS phase 3 Convex client RUNNING (isolated). After merge: apply its AppLaunch.services() swap line + set CONVEX_URL/SITE_URL build settings once the user has a Convex project. Then ConvexActivityService after backend 2a–2c.
- iOS phase 4a placement + model fixes RUNNING. Then: push registration/routing (after backend 2c). ios-model-fixes handoff names a HamroStepsApp.swift line to switch reload()→refresh() — apply after placement merges.
- Host web/ (invite + privacy) somewhere — user picks host; TestFlight URL + privacy email placeholders to fill.
- App icon (codex) → Jarvis installs design/app-icon into ios AppIcon.appiconset after merge.
- User setup before device testing: (team id ✓ JQ2D4NNS3B) App ID com.bixustudio.hamrosteps with SIWA + HealthKit (automatic signing should create it on first device build), Convex project (user creates/logs in), APNs key, privacy policy URL before TestFlight.
