# Second opinion: iOS: ConvexActivityService + switch the app to the live Convex services
verdict: Has concerns
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1745-ios-convex-activity.md
findings: 2
at: 2026-11-14T08:46:42Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, fadeb9221d..e52d970ada (shared checkout) (639 changed lines).

## Summary
The implementation matches the brief and backend contracts and appears mergeable. The cancellation tests have two gaps; I did not rerun builds in this read-only review.

## Findings
1. **Should fix** · `ios/HamroStepsTests/ConvexActivityServiceTests.swift:235`
   Why: The 100 ms assertion runs only after task.result returns. If cancellation regresses, the transport remains blocked and these tests hang indefinitely instead of reporting a failure.
   Fix: Add an independent watchdog that releases the hanging transport after the deadline, then verify the call completed with CancellationError within 100 ms. Bound waitUntilHanging as well.
2. **Minor** · `ios/HamroStepsTests/ConvexActivityServiceTests.swift:216`
   Why: The assertion that an already-cancelled call sends nothing cannot detect a device mutation: HangingTransport never records its hanging calls in base.calls.
   Fix: Record hanging mutation entries separately and assert none occurred, or use the recording FakeTransport with an immediate response for this test.
