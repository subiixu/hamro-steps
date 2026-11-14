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
- 2026-11-14 15:55 · claude/claude-sonnet-5-5 medium · term s_9884cc40 · handoffs/briefs/2026-11-14-1610-ios-store-prep.md
- 2026-11-14 15:35 · claude/claude-opus-5-5 medium · term s_2d8f7e3e · handoffs/briefs/2026-11-14-1600-ios-push.md · isolate: /Users/subixu/.jarvis-worktrees/hamro-steps/ios-push · branch: jw/ios-push
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- Merge batch (session start 16:30): ios-convex-client (done, rebase-merge; fresh second opinion running) → apply AppLaunch.services() swap + CONVEX_URL/CONVEX_SITE_URL (harmless-dolphin-642 dev) in project.yml, check-ios on main. ios-push (done, fresh second opinion running; trivial project.yml merge). ios-store-prep (partial: checks timed out on stuck builds; rerunning).
- After merges: follow-ups from store-prep audit (ITSAppUsesNonExemptEncryption, privacy link in Me/Welcome, tinted icon alpha) + push Home focus-event hook for eventId → one small brief.
- Left for TestFlight: TESTFLIGHT_URL in web/invite/index.html once TestFlight exists.
- Context: PRD = docs/PRD.md; Convex dev deployment harmless-dolphin-642 (env set); web live at https://subiixu.github.io/hamro-steps/.
