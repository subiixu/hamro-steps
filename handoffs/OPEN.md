# Open items

Jarvis reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Jarvis
stops, this file must hold everything a fresh session needs: the user may
clear Jarvis after a long idle.

Jarvis session: s_8bc24026
Usage band: amber (5h 72% used, 17:36)

## Questions for the user
- manual test (web pages): open web/invite/index.html?code=K7M2QX and web/privacy/index.html in Safari; check dark mode; founders review the DRAFT privacy text + set real contact email and TestFlight URL.
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
- 2026-11-14 17:33 · claude/claude-opus-5-5 high · term s_e77dfbba · handoffs/briefs/2026-11-14-1720-ios-convex-activity.md
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- ios-convex-activity RUNNING (s_e77dfb): ConvexActivityService + live swap + device-call cancellation contract (push review F1). After merge: manual test on a real iPhone (sign in with Apple, create family, push).
- check-ios.sh: stale-lock break is check-then-rm (two waiters can both break it; push review F3). Make it atomic (mv the lock aside before rm). Tiny brief, after activity merges.
- ios-store-fixes RUNNING (privacy link, encryption key, tinted icon alpha). Still to brief: push Home focus-event hook for eventId (PushRoute.family(id:eventId:)), after activity merges.
- Left for TestFlight: TESTFLIGHT_URL in web/invite/index.html once TestFlight exists.
- Context: PRD = docs/PRD.md; Convex dev deployment harmless-dolphin-642 (env set); web live at https://subiixu.github.io/hamro-steps/.
