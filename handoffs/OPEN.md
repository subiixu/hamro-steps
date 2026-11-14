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
- 2026-11-14 15:17 · claude/claude-opus-5-5 high · term s_19a93bf3 · handoffs/briefs/2026-11-14-1630-ios-convex-client.md · isolate: /Users/subixu/.jarvis-worktrees/hamro-steps/ios-convex-client · branch: jw/ios-convex-client
- 2026-11-14 14:06 · codex/gpt-6-astra high · term s_9dd4f84f · handoffs/briefs/2026-11-14-1440-app-icon.md
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- PRD = docs/PRD.md (backend Convex, invites code-first for pilot). Tasks T-4…T-10. Supabase work dropped (archived ~/.jarvis-archive/hamro-steps/).
- Backend 2a–2c merged; combined review clean (no blocking). Follow-up walk-purge + NUDGE_BATCH=25 RUNNING (s_12142e). Next iOS brief (ConvexActivityService + push registration) MUST call unregisterDevice before sign-out AND on account switch (review item: pushes reach handed-over phones otherwise). Goal-hit push includes the tipping member: per spec, left as is.
- iOS phase 3 Convex client sent back (isolated, s_19a93b). After merge: apply its AppLaunch.services() swap + CONVEX_URL/SITE_URL (harmless-dolphin-642, see above).
- iOS: after backend 2c → ConvexActivityService + push registration/routing (APNs device token → registerDevice; tap routes by payload type).
- Host web/ (invite + privacy) somewhere — user picks host; TestFlight URL + privacy email placeholders to fill.
- App icon (codex) → Jarvis installs design/app-icon into ios AppIcon.appiconset after merge.
- User setup before device testing: (team id ✓ JQ2D4NNS3B) App ID com.bixustudio.hamrosteps with SIWA + HealthKit (automatic signing should create it on first device build), Convex project (user creates/logs in), APNs key, privacy policy URL before TestFlight.
- ios-convex-client sent back (s_19a93b, isolated): second opinion Blocking on token refresh via SDK, sign-out/refresh race, Keychain write retry. Then merge, apply AppLaunch.services() swap (handoff Notes), set CONVEX_URL=https://harmless-dolphin-642.ap-southeast-2.convex.cloud and CONVEX_SITE_URL=https://harmless-dolphin-642.ap-southeast-2.convex.site in project.yml (dev deployment; all 6 env vars set, JWKS verified 15:40), run check-ios on main.
