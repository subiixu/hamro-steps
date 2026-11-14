# Second opinion: iOS: walk button + badge, status picker, feed + reactions, notification settings (standalone, mock service)
verdict: Has concerns
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1429-ios-activity-ui.md
findings: 3
at: 2026-11-14T05:32:29Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, ff5f0e5cf2..0a0fc49b06 (isolated checkout) (2883 changed lines).

## Summary
The change largely fulfills the standalone-component brief, but overlapping saves and a stale walk-limit notice can leave incorrect UI state. Build checks were not rerun during this read-only review.

## Findings
1. **Should fix** · `ios/HamroSteps/Features/Activity/NotificationSettingsView.swift:37`
   Why: Overlapping saves can restore an unconfirmed value. Starting with notifications enabled, toggle off then on while both requests are pending. If both fail in order, the final rollback sets the switch off although notifications remain enabled on the service.
   Fix: Serialize saves per notification kind and disable that switch while saving, or maintain confirmed state and queue subsequent changes. Add a test covering overlapping failures.
2. **Should fix** · `ios/HamroSteps/Features/Activity/FeedList.swift:39`
   Why: A failed reaction request unconditionally restores its entire earlier event snapshot. If someone taps heart then fire before either request finishes, a failed heart request erases the optimistic fire selection even when fire saves successfully. The UI remains inconsistent until reloaded.
   Fix: Serialize reactions per event or reconcile pending operations against confirmed state. Coordinate feed refreshes with pending reactions, and test a failed request followed by a successful overlapping request.
3. **Should fix** · `ios/HamroSteps/Features/Activity/WalkButton.swift:121`
   Why: Once the controller receives walk_limit_reached, the button stays disabled for that controller's lifetime. Nothing clears the notice at Nepal midnight, and sync() only clears alreadyWalking. Returning the next day can therefore leave walking unavailable despite the daily allowance resetting.
   Fix: Expire the limit notice when the Nepal day changes, including after foregrounding, or allow a retry that lets the service enforce the limit. Add a controller test spanning Nepal midnight.
