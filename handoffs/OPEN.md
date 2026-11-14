# Open items

Jarvis reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Jarvis
stops, this file must hold everything a fresh session needs: the user may
clear Jarvis after a long idle.

Jarvis session: s_8bc24026
Usage band: amber (5h 59% used, 16:30)

## Questions for the user
- manual test (web pages): open web/invite/index.html?code=K7M2QX and web/privacy/index.html in Safari; check dark mode; founders review the DRAFT privacy text + set real contact email and TestFlight URL.
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
- 2026-11-14 16:40 · claude/claude-opus-5-5 high · term s_084e3552 · handoffs/briefs/2026-11-14-1600-ios-push.md · isolate: /Users/subixu/.jarvis-worktrees/hamro-steps/ios-push-2 · branch: jw/ios-push-2
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- NEXT BRIEF after push merges (opus high, isolate no): ConvexActivityService (backend activity/push functions) + AppLaunch.services() live swap (handoff snippet in handoffs/merged/2026-11-14-1510-ios-convex-client.md is stale: AppServices now also needs activity + now). CONVEX URLs already set in project.yml (dev harmless-dolphin-642).
- ios-push REDO 3 running (s_084e3552, jw/ios-push-2; Jarvis ported uncommitted work from old worktree ios-push, remove it after merge). Then fresh second opinion, merge.
- After merges: follow-ups from store-prep audit (ITSAppUsesNonExemptEncryption, privacy link in Me/Welcome, tinted icon alpha) + push Home focus-event hook for eventId → one small brief.
- Left for TestFlight: TESTFLIGHT_URL in web/invite/index.html once TestFlight exists.
- Context: PRD = docs/PRD.md; Convex dev deployment harmless-dolphin-642 (env set); web live at https://subiixu.github.io/hamro-steps/.
