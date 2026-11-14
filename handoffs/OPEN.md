# Open items

Jarvis reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Jarvis
stops, this file must hold everything a fresh session needs: the user may
clear Jarvis after a long idle.

Jarvis session: s_1910bb4f
Usage band: green (the 5-hour window has reset since the last reading (307 min ago), 23:20)

## Questions for the user
- manual test (redesign, largest text): Settings › Accessibility › Larger Text at max, then scroll Health how-to, goal presets, Family settings People + Remove, status expiry chips, Change name or goal, Delete account. Nothing cut off or unreachable? (second opinion on phase 2 flagged these as unchecked)
- manual test (live app, past Home): user confirmed onboarding → Home works on their phone (2026-11-14). Still unchecked: walk push to a 2nd phone, reactions, sign out.
- (T-35, T-36, T-37) TestFlight 0.1.0 (5) archived 2026-11-15 with the full redesign (supersedes 4) (build 3 failed upload: the build-2 project.yml fixes were never committed; now committed) (phase 1 Home redesign; other screens old style until phase 2). Upload from Xcode Organizer is the user's; then add family as testers.
- manual test (privacy link): on a phone, tap "Privacy policy" on Welcome and on Me → Safari opens the privacy page; check the Me row looks right (not seen on screen yet).
- manual test (web pages): open web/invite/index.html?code=K7M2QX and web/privacy/index.html in Safari; check dark mode; founders review the DRAFT privacy text + set real contact email and TestFlight URL.
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis

## To-do
- `handoffs/bin/jarvis send`/`read <id>` print the usage text instead of acting (seen 2026-11-14); use `ultron term send/read` meanwhile.
- TESTFLIGHT_URL in web/invite/index.html (and InviteMessage.installURL in the app) once the user has a public TestFlight link.
- Context: PRD = docs/PRD.md; Convex dev deployment harmless-dolphin-642 (env set); web live at https://subiixu.github.io/hamro-steps/.
