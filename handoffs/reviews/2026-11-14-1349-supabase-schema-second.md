# Second opinion: Supabase schema: families, invites, daily steps, goals, streaks, cheers, with RLS and pgTAP tests
verdict: Blocking
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1349-supabase-schema.md
findings: 1
at: 2026-11-14T04:52:18Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, c646eebb6d..345ecb6829 (shared checkout) (1591 changed lines).

## Summary
The change largely satisfies the brief, but concurrent departures can leave a family without an owner. Fix that race before merging; reset-based checks were not rerun during this read-only review.

## Findings
1. **Blocking** · `supabase/migrations/20261114134000_initial_schema.sql:244`
   Why: Ownership transfer is not serialized. If the owner leaves while the selected successor is being deleted in another transaction, the successor's trigger can still see the uncommitted owner and skip promotion. The owner's UPDATE then waits for that deletion and affects zero rows. Both transactions can commit with remaining members all having role='member', preventing anyone from editing settings or regenerating invites.
   Fix: Serialize membership changes per family before choosing a successor, including removals caused by account deletion. Recheck membership after acquiring the lock, and add a two-session regression test for concurrent owner/successor departures.
