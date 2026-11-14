# Second opinion: iOS cleanup after the live switch: debug button, FeedActor decode, push tap focus, test watchdogs
verdict: Has concerns
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1810-ios-cleanup.md
findings: 2
at: 2026-11-14T09:08:50Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, 9a67b9809c..8716ca6626 (shared checkout) (307 changed lines).

## Summary
The change largely meets the brief, but push focus and the already-cancelled test have race conditions worth fixing. I did not rerun checks in this read-only review.

## Findings
1. **Should fix** · `ios/HamroSteps/Features/Home/HomeView.swift:232`
   Why: Each focus starts an independent task. If event A needs a slow reload and a newer tap focuses event B, A can finish later and override B's scroll and highlight. The feed identity check doesn't prevent this within the same family, and selection can also change during the subsequent sleep.
   Fix: Cancel superseded focus work or use a request generation, and verify the request and selected family are still current after every suspension before scrolling or highlighting.
2. **Should fix** · `ios/HamroStepsTests/ConvexActivityServiceTests.swift:226`
   Why: The hanging-call assertion can run before the service's inner unstructured task reaches the transport. If the initial cancellation check regresses, the cancellation handler can complete the outer task immediately while the mutation is still scheduled, allowing this test to pass before the unwanted send occurs.
   Fix: Synchronize with completion of the underlying operation before checking recorded calls, using a bounded gate or completion signal so a delayed send reliably fails the test.
