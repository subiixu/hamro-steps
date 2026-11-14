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
- 2026-11-14 14:17 · claude/claude-opus-5-5 high · term s_19e7b9bf · handoffs/briefs/2026-11-14-1415-convex-core.md
- 2026-11-14 14:06 · codex/gpt-6-astra high · term s_9dd4f84f · handoffs/briefs/2026-11-14-1440-app-icon.md
- 2026-11-14 14:06 · claude/claude-opus-5-5 high · term s_b2eb48e6 · handoffs/briefs/2026-11-14-1440-ios-activity-ui.md · isolate: /Users/subixu/.jarvis-worktrees/hamro-steps/ios-activity-ui · branch: jw/ios-activity-ui
- 2026-11-14 14:03 · claude/claude-opus-5-5 high · term s_e5c84894 · handoffs/briefs/2026-11-14-1425-ios-home-mock.md
<!-- `jarvis spawn` adds: - <date HH:MM> · claude/claude-opus-5-5 high · term <id> · handoffs/briefs/<file>.md -->
<!-- `jarvis merge` removes the line -->

## Waiting on Jarvis
- ios-home-mock partial (all built, 4.5k lines, checks green): second opinion running → merge; screenshots worker s_08faa7 runs in parallel.

## To-do
- PRD = docs/PRD.md (backend Convex, invites code-first for pilot). Tasks T-4…T-10. Supabase work dropped (archived ~/.jarvis-archive/hamro-steps/).
- Backend phase 2 — spawn the moment convex-core merges (--after it), implementing docs/contract-activity.md: walks (F9–F11), status (F12), feed auto-events + 5 reactions (F13–F14), APNs action + device tokens + per-type mutes + evening nudge (F15–F16). T-7…T-10. APNs key/env = user supplies; never to free models.
- iOS phase 3 (after convex-core AND ios-home-mock merge): wire ConvexMobile (convex-swift SPM, Jarvis approves) + auth endpoints, replace mock service; background delivery sync.
- iOS phase 4 (after ios-home-mock + ios-activity-ui merge; real service after backend phase 2): place activity components into Home/member rows/Me, push registration + routing.
- Host web/ (invite + privacy) somewhere — user picks host; TestFlight URL + privacy email placeholders to fill.
- App icon (codex) → Jarvis installs design/app-icon into ios AppIcon.appiconset after merge.
- User setup before device testing: Apple Developer team id + SIWA capability, Convex project (user creates/logs in), APNs key, privacy policy URL before TestFlight.
