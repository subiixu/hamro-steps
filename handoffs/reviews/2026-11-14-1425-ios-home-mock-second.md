# Second opinion: iOS phase 2: PRD onboarding, family setup and Home, against a mock backend service
verdict: Blocking
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1425-ios-home-mock.md
findings: 6
at: 2026-11-14T05:24:44Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, 2a781aa338..f764512699 (shared checkout) (4537 changed lines, cut at 150 KB).

## Summary
Most requested flows are implemented, but I would not merge yet. Nepal-day rollover, accessibility layout, and Health status have correctness gaps, and the required simulator verification is unfinished.

## Findings
1. **Blocking** · `ios/HamroSteps/Features/Home/HomeModel.swift:119`
   Why: Live updates only patch today's existing week entry. After Nepal midnight, future flags remain stale; after Monday midnight, Home keeps the previous week's dates entirely. Foreground handling only syncs steps, so an unsuccessful sync can also leave yesterday's progress displayed.
   Fix: Refresh today's data and the full week on foreground and Nepal-day changes. Refresh historical markers after seven-day syncs too. Add tests crossing midnight and Sunday into Monday.
2. **Should fix** · `ios/HamroSteps/Features/Setup/FamilySetupView.swift:199`
   Why: The goal remains in a horizontal row between two fixed-width buttons, while its Dynamic Type text uses fixedSize(). Accessibility sizes and larger allowed goals exceed an iPhone's available width, pushing content or controls off-screen.
   Fix: Use a stacked or width-adaptive layout for the goal and adjustment controls. Verify accessibility sizes with both 50,000 and 1,000,000.
3. **Should fix** · `ios/HamroSteps/Features/Me/MeView.swift:67`
   Why: healthRequested only establishes that another permission sheet is unnecessary. A person who denied or revoked step access still sees green 'Connected'. Apple's [request-status API](https://developer.apple.com/documentation/healthkit/hkhealthstore/getrequeststatusforauthorization(toshare:read:completion:)) does not establish readable access.
   Fix: Show neutral permission-requested or no-data wording, and base positive step-reading status on actual readable data. Keep permission recovery guidance visible.
4. **Should fix** · `ios/HamroSteps/Sync/StepSync.swift:63`
   Why: The positive-step requirement discards explicitly returned zero totals as well as absent data. A valid zero-valued response cannot update lastSyncedAt or replace previously uploaded positive totals with zero.
   Fix: Distinguish missing readable data from explicitly returned zero totals. Permit the latter to sync, and test correcting an existing positive value to zero.
5. **Should fix** · `ios/HamroSteps/Services/MockFamilyService.swift:236`
   Why: Historical days use the family's current goal, so changing the goal retroactively changes earlier hit markers despite the settings screen promising otherwise. Seeded closedTotals also ignore later step corrections, unlike the documented backend contract.
   Fix: Preserve each closed day's goal and adjust its total for late syncs using the backend's membership rules. Add tests for goal changes and late corrections.
6. **Should fix** · `handoffs/2026-11-14-1425-ios-home-mock.md:50`
   Why: None of the required screenshots were captured, and no screen was inspected in a running simulator. Passing unit tests does not satisfy the brief's explicit visual and accessibility acceptance criteria.
   Fix: Inspect and capture all listed screens, including Home in light, dark, and accessibility text sizes; fix discovered issues before completing the phase.
