# Open items

Jarvis reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Jarvis
stops, this file must hold everything a fresh session needs: the user may
clear Jarvis after a long idle.

Jarvis session: s_8bc24026
Usage band: amber (5h 72% used, 17:36)

## Questions for the user
- manual test (live app on iPhone): build to your phone from Xcode (Debug, no launch flags) → Sign in with Apple → name → create a family → invite code shows; sync steps; start a walk (push should reach a second account's phone); react to a feed event; Me → sign out. First run ever against the real dev backend.
- manual test (privacy link): on a phone, tap "Privacy policy" on Welcome and on Me → Safari opens the privacy page; check the Me row looks right (not seen on screen yet).
- manual test (web pages): open web/invite/index.html?code=K7M2QX and web/privacy/index.html in Safari; check dark mode; founders review the DRAFT privacy text + set real contact email and TestFlight URL.
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- READY TO SPAWN: handoffs/briefs/2026-11-14-1800-ios-cleanup.md (debug button, FeedActor decode, push tap focus, test watchdogs). Held until the user pins the project to claude-3 (momo@bloomdots.com.au): `ultron account use claude-3`; only the user can.
- check-ios.sh: stale-lock break is check-then-rm (two waiters can both break it; push review F3). Make it atomic (mv the lock aside before rm). Tiny brief, after activity merges.
- Left for TestFlight: TESTFLIGHT_URL in web/invite/index.html once TestFlight exists.
- Context: PRD = docs/PRD.md; Convex dev deployment harmless-dolphin-642 (env set); web live at https://subiixu.github.io/hamro-steps/.
