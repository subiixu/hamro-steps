# Open items

Nayo reads this first, every session, and keeps it current. One line per
item; an item goes in when it opens and comes out when it's done. Don't
rebuild "what's pending" by searching the handoff folders. Before Nayo
stops, this file must hold everything a fresh session needs: the user may
clear Nayo after a long idle.

Nayo session: s_b175cbae
Usage band: green (the 5-hour window has reset since the last reading (2512 min ago), 12:39)

## Questions for the user
- manual test (redesign, largest text): Settings › Accessibility › Larger Text at max, then scroll Health how-to, goal presets, Family settings People + Remove, status expiry chips, Change name or goal, Delete account. Nothing cut off or unreachable? (second opinion on phase 2 flagged these as unchecked)
- manual test (live app, past Home): user confirmed onboarding → Home works on their phone (2026-11-14). Still unchecked: walk push to a 2nd phone, reactions, sign out.
- TestFlight 0.1.0 (7) archived 2026-11-15: redesign + Shared Stride icon + profile editing (photo, city, birthday) (supersedes 3–6). Uploaded to App Store Connect 2026-11-15 20:33 (xcodebuild -exportArchive with ASC API key WZVC3GLC68, issuer in ~/BIXUSTUDIO/DEV/ghosty/CONTEXT.md); testers added by the user.
- manual test (privacy link): on a phone, tap "Privacy policy" on Welcome and on Me → Safari opens the privacy page; check the Me row looks right (not seen on screen yet).
- manual test (web pages): open web/invite/index.html?code=K7M2QX and web/privacy/index.html in Safari; check dark mode; founders review the DRAFT privacy text + set real contact email and TestFlight URL.
- manual test (T-39 profile, needs a new build): Me › Edit profile: choose a photo from your library, take one with the camera, remove it; set Lives in + birthday, Save. On a 2nd phone, tap that person on Home: photo, city · their local time, birthday (no year). Backend is live on dev.
<!-- - <date> · <slug> · Q1 …  (batched from worker handoffs; remove when answered and passed back) -->

## Running workers
- 2026-11-17 12:42 · claude/claude-opus-5-5 high · term s_dad419a7 · handoffs/briefs/2026-11-17-1200-history-ios.md
<!-- `nayo spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `nayo merge` removes the line -->

## Waiting on Nayo

## To-do
- T-44 history: after both history handoffs merge, deploy backend to Convex dev (familyHistory), then build 8 for TestFlight.
- `handoffs/bin/nayo send`/`read <id>` print the usage text instead of acting (seen 2026-11-14); use `araniko term send/read` meanwhile.
- TESTFLIGHT_URL in web/invite/index.html (and InviteMessage.installURL in the app) once the user has a public TestFlight link.
- Context: PRD = docs/PRD.md; Convex dev deployment harmless-dolphin-642 (env set); web live at https://subiixu.github.io/hamro-steps/.
