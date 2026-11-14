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
- Convex client MERGED 7117c5d. Next (Jarvis, after main check ends): apply AppLaunch.services() swap from handoffs/merged/2026-11-14-1510-ios-convex-client.md Notes + CONVEX_URL=https://harmless-dolphin-642.ap-southeast-2.convex.cloud / CONVEX_SITE_URL=https://harmless-dolphin-642.ap-southeast-2.convex.site in ios/project.yml; check-ios on main.
- ios-push REDO 3 running (s_084e3552, jw/ios-push-2; Jarvis ported uncommitted work from old worktree ios-push, remove it after merge). Then fresh second opinion, merge.
- ios-store-prep partial: merge once `ultron check` on main (running, /tmp/check-main.log) is green.
- scripts/check-ios.sh hardening (small brief): lock dir left behind when a check is killed (trap doesn't run) blocks every later check for 15 min — write PID into the lock and break it when the PID is dead; also pass -collect-test-diagnostics never (failure diagnostics take ~10 min and blow the cap).
- After merges: follow-ups from store-prep audit (ITSAppUsesNonExemptEncryption, privacy link in Me/Welcome, tinted icon alpha) + push Home focus-event hook for eventId → one small brief.
- Left for TestFlight: TESTFLIGHT_URL in web/invite/index.html once TestFlight exists.
- Context: PRD = docs/PRD.md; Convex dev deployment harmless-dolphin-642 (env set); web live at https://subiixu.github.io/hamro-steps/.
