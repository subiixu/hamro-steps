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
- 2026-11-14 14:06 · codex/gpt-6-astra high · term s_9dd4f84f · handoffs/briefs/2026-11-14-1440-app-icon.md
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis
- convex-push (2c) sent back (s_4f67a2): second opinion Blocking on the nudge going to every under-goal family (must be once per person); also uncapped devices vs a 20-device read (cap 10 per user, evict oldest). Then merge + combined 2a–2c review.

## To-do
- PRD = docs/PRD.md (backend Convex, invites code-first for pilot). Tasks T-4…T-10. Supabase work dropped (archived ~/.jarvis-archive/hamro-steps/).
- Backend phase 2 (combined second opinion over 2a–2c after 2c merges; 2a skipped one) — spawn the moment convex-core merges (--after it), 2a merged ✓; 2b merged ✓; 2c push RUNNING (also fixes walk_started per walk). Contract docs/contract-activity.md: walks (F9–F11), status (F12), feed auto-events + 5 reactions (F13–F14), APNs action + device tokens + per-type mutes + evening nudge (F15–F16). T-7…T-10. APNs key/env = user supplies; never to free models.
- iOS phase 3 Convex client RUNNING (isolated). After merge: apply its AppLaunch.services() swap line + set CONVEX_URL/SITE_URL build settings once the user has a Convex project. Then ConvexActivityService after backend 2a–2c.
- iOS: after backend 2c → ConvexActivityService + push registration/routing (APNs device token → registerDevice; tap routes by payload type).
- Host web/ (invite + privacy) somewhere — user picks host; TestFlight URL + privacy email placeholders to fill.
- App icon (codex) → Jarvis installs design/app-icon into ios AppIcon.appiconset after merge.
- User setup before device testing: (team id ✓ JQ2D4NNS3B) App ID com.bixustudio.hamrosteps with SIWA + HealthKit (automatic signing should create it on first device build), Convex project (user creates/logs in), APNs key, privacy policy URL before TestFlight.
- ios-convex-client done (isolated, ~1.95k lines): second opinion running. Then merge, apply AppLaunch.services() swap (handoff Notes), set CONVEX_URL=https://harmless-dolphin-642.ap-southeast-2.convex.cloud and CONVEX_SITE_URL=https://harmless-dolphin-642.ap-southeast-2.convex.site in project.yml (dev deployment; no env vars set yet as of 15:20), run check-ios on main.
