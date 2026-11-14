# Second opinion: iOS fix: Nepal-day rollover on Home, zero-step sync, mock closed-day goals
verdict: Blocking
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1545-ios-home-logic-fix.md
findings: 3
at: 2026-11-14T05:38:00Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, 71ae982df1..5c225388f4 (shared checkout) (759 changed lines).

## Summary
The main fixes and tests are present, but closed-day membership cleanup and rollover scheduling still have correctness gaps. I would fix these before merging.

## Findings
1. **Blocking** · `ios/HamroSteps/Services/MockFamilyService.swift:227`
   Why: Leaving or removing a member never deletes their closed-day contributions. Their historical steps remain counted, and this loop continues applying late corrections to families they have left. Account deletion also leaves those contributions behind, contrary to the backend contract.
   Fix: Remove the user's contributions from every affected closed day in drop(), preserving frozen goals. Test leaving, removal and account deletion, including a subsequent late sync.
2. **Should fix** · `ios/HamroSteps/App/HamroStepsApp.swift:32`
   Why: A successful sync reloads data without reopening the live subscription, despite the brief requiring both. If this reload advances loadedDay just after midnight, refreshIfDayChanged() subsequently skips refreshing, leaving a day-pinned subscription on yesterday.
   Fix: Call home.refresh() after sync and test rollover with a service whose subscription remains pinned to the day it opened.
3. **Should fix** · `ios/HamroSteps/Features/Home/HomeModel.swift:186`
   Why: Significant clock changes check the current day but never reschedule the sleeping midnight task. Moving the clock forward within the same Nepal day leaves the original elapsed-time delay intact, so Home can miss the new midnight by hours.
   Fix: Cancel and recompute the midnight wait on every significant-time notification. Add a test that advances the clock within the same day and verifies the revised deadline.
