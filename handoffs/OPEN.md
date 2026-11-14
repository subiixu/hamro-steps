# Open items

Jarvis reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Jarvis
stops, this file must hold everything a fresh session needs: the user may
clear Jarvis after a long idle.

Jarvis session: s_70936213
Usage band: green (the 5-hour window has reset since the last reading (23 min ago), 18:36)

## Questions for the user
- manual test (live app, past Home): user confirmed onboarding → Home works on their phone (2026-11-14). Still unchecked: walk push to a 2nd phone, reactions, sign out.
- (T-31) TestFlight 0.1.0 (2): build 1 rejected (iPad orientations, missing NSHealthUpdateUsageDescription); fixed in project.yml. Build 2 archived from HEAD (without the uncommitted light-mode edits, by the user's choice); UPLOADED 20:24 (warnings only: Mac/Vision healthkit). Next: user adds family as testers.
- Uncommitted iOS edits (15 files, 20:15–20:17, light mode only + Home/Me/WalkButton/InviteCode/Card/colours) came from outside Jarvis; user kept them out of TestFlight. Ask what to do with them.
- manual test (privacy link): on a phone, tap "Privacy policy" on Welcome and on Me → Safari opens the privacy page; check the Me row looks right (not seen on screen yet).
- manual test (web pages): open web/invite/index.html?code=K7M2QX and web/privacy/index.html in Safari; check dark mode; founders review the DRAFT privacy text + set real contact email and TestFlight URL.
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- TESTFLIGHT_URL in web/invite/index.html (and InviteMessage.installURL in the app) once the user has a public TestFlight link.
- Context: PRD = docs/PRD.md; Convex dev deployment harmless-dolphin-642 (env set); web live at https://subiixu.github.io/hamro-steps/.
