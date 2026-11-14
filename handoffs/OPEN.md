# Open items

Jarvis reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Jarvis
stops, this file must hold everything a fresh session needs: the user may
clear Jarvis after a long idle.

Jarvis session: s_6f0aa16b
Usage band: green (5h 42% used, 15:36)

## Questions for the user
- manual test (web pages): open web/invite/index.html?code=K7M2QX and web/privacy/index.html in Safari; check dark mode; founders review the DRAFT privacy text + set real contact email and TestFlight URL.
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
- 2026-11-14 15:55 · claude/claude-sonnet-5-5 medium · term s_9884cc40 · handoffs/briefs/2026-11-14-1610-ios-store-prep.md
- 2026-11-14 15:35 · claude/claude-opus-5-5 high · term s_21a6035f · handoffs/briefs/2026-11-14-1630-ios-convex-client.md · isolate: /Users/subixu/.jarvis-worktrees/hamro-steps/ios-convex-client · branch: jw/ios-convex-client
- 2026-11-14 15:35 · claude/claude-opus-5-5 medium · term s_2d8f7e3e · handoffs/briefs/2026-11-14-1600-ios-push.md · isolate: /Users/subixu/.jarvis-worktrees/hamro-steps/ios-push · branch: jw/ios-push
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- PRD = docs/PRD.md (backend Convex, invites code-first for pilot). Tasks T-4…T-10. Supabase work dropped (archived ~/.jarvis-archive/hamro-steps/).
- Backend 2a–2c merged; combined review clean (no blocking). Follow-up walk-purge + NUDGE_BATCH=25 merged (84366ca). Next iOS brief (ConvexActivityService + push registration) MUST call unregisterDevice before sign-out AND on account switch (review item: pushes reach handed-over phones otherwise). Goal-hit push includes the tipping member: per spec, left as is.
- iOS: after backend 2c → ConvexActivityService + push registration/routing (APNs device token → registerDevice; tap routes by payload type).
- Host web/ (invite + privacy) somewhere — user picks host; TestFlight URL + privacy email placeholders to fill.
- App icon (codex) → Jarvis installs design/app-icon into ios AppIcon.appiconset after merge.
- User setup: Apple + Convex DONE (App ID w/ HealthKit+Push+SIWA, key 4L75BC2Z4S for APNs+SIWA, all 6 Convex env vars on dev harmless-dolphin-642). web/ live on GitHub Pages https://subiixu.github.io/hamro-steps/ (invite/?code=XXXXXX, privacy/), privacy email bixustudio@gmail.com, policy approved. Left: TestFlight link in web/invite/index.html (TESTFLIGHT_URL) once TestFlight exists; iOS invite share text should use the Pages invite URL.
- ios-convex-client REDO 2 running (s_21a603): generation check before refresh; Keychain-delete failure on signOut. Then second opinion, merge, apply AppLaunch.services() swap (handoff Notes), set CONVEX_URL=https://harmless-dolphin-642.ap-southeast-2.convex.cloud and CONVEX_SITE_URL=https://harmless-dolphin-642.ap-southeast-2.convex.site in project.yml (dev deployment; all 6 env vars set, JWKS verified 15:40), run check-ios on main.

- ios-push: second opinion Blocking (unregister timeout, register/unregister race, tap during onboarding) → fixes sent to s_2d8f7e (same worker). Then merge (expect trivial project.yml merge vs client). Follow-up: Home focus-event hook for eventId.

- ios-store-prep RUNNING (s_9884cc): PrivacyInfo.xcprivacy + docs/app-store-preflight.md.
