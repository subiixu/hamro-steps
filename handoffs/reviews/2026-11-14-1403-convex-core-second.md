# Second opinion: Convex backend, phase 1: schema, Apple sign-in sessions, families + invites, Nepal-day steps, Home queries, account deletion
verdict: Blocking
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1403-convex-core.md
findings: 3
at: 2026-11-14T05:35:06Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, e9bda04edc..2f15b8ac67 (shared checkout) (479 changed lines).

## Summary
Snapshot cleanup addresses the earlier finding, but the Apple retry queue can still lose unrevoked tokens or stop retrying permanently. Both TypeScript checks passed; test execution was blocked by the read-only sandbox’s restriction on temporary directories.

## Findings
1. **Blocking** · `backend/convex/users.ts:144`
   Why: After the final failed retry, the only remaining Apple token is deleted even though revocation never succeeded. A prolonged outage or incorrect Apple configuration therefore recreates the irreversible token loss this redo was meant to fix.
   Fix: Retain exhausted entries for recovery or manual retry, or continue retrying with capped backoff. Delete the token only after confirmed revocation, and update the exhaustion test accordingly.
2. **Should fix** · `backend/convex/users.ts:113`
   Why: Convex scheduled actions execute at most once. If this action encounters a platform failure or fails before recordRevokeAttempt commits, the queue row remains without another scheduled attempt; no cron recovers it.
   Fix: Add persistent retry timing and a recurring recovery job that reschedules overdue entries. Test recovery when an action fails before recording its result.
3. **Should fix** · `backend/convex/users.ts:121`
   Why: A skipped revoke is treated as success. If Apple environment variables are absent during a queued retry, revokeAppleToken returns skipped and the stored token is deleted without contacting Apple.
   Fix: Set succeeded only when the result is revoked. Preserve skipped queue entries for retry after configuration is restored, and add coverage for this case.
