# Second opinion: iOS: push permission, APNs token registration, tap routing
verdict: Blocking
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1600-ios-push.md
findings: 3
at: 2026-11-14T08:31:56Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, 7117c5df5e..de3f812f3d (isolated checkout) (1163 changed lines).

## Summary
The push wiring largely matches the brief, but cleanup can block sign-out indefinitely and the check-script changes introduce a locking race. The required iOS check also timed out, so I would not merge this revision yet.

## Findings
1. **Blocking** · `ios/HamroSteps/Push/PushRegistrar.swift:177`
   Why: The task-group timeout cancels the operation but waits for it to finish. If registerDevice or unregisterDevice ignores cancellation, sign-out, deletion, subsequent sign-in, and pending-sign-out recovery at launch can hang indefinitely. ActivityService provides no cancellation guarantee; the new timeout test covers only cancellation-aware Task.sleep.
   Fix: Establish and verify a bounded cancellation contract for device calls, while preserving account ordering. Add coverage for stalled calls and ensure cleanup cannot indefinitely prevent sign-out or launch recovery.
2. **Blocking** · `scripts/check-ios.sh`
   Why: The supplied verification for this revision timed out after 15 minutes. The brief requires a green iOS check, and the earlier passing result in the handoff does not resolve the latest failure.
   Fix: Identify whether the timeout occurred during lock acquisition, simulator startup, build, or tests, then obtain a passing check on the final revision and update the handoff.
3. **Should fix** · `scripts/check-ios.sh:21`
   Why: Stale-lock detection and removal are separate operations. Two waiting checks can both identify the old lock as stale; one can then delete the other's newly acquired lock, allowing simultaneous builds against the same derived-data directory. This shared script is also outside the brief's allowed files and missing from the handoff's file list.
   Fix: Exclude this script change from the push merge, or handle it separately with concurrency-safe lock recovery and an accurate handoff.
