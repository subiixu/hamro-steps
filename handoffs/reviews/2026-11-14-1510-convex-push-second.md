# Second opinion: Convex backend 2c: APNs push, devices, notification prefs, evening nudge (contract F15–F16)
verdict: Blocking
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-1510-convex-push.md
findings: 2
at: 2026-11-14T06:11:30Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, ace0973cdb..e6a08706e0 (shared checkout) (1487 changed lines).

## Summary
Evening nudges violate the current contract’s once-per-person rule. Typechecks passed; the test rerun was blocked by sandbox restrictions on temporary files.

## Findings
1. **Blocking** · `backend/convex/notifications.ts:114`
   Why: The current Notifications contract requires one evening nudge per person, about their family furthest from its goal. This loop sends a separate notification for every under-goal family, including across pagination boundaries.
   Fix: Select each opted-in user’s lowest-progress family and deduplicate delivery across pages for that Nepal day. Add tests covering shared members and families on different pages.
2. **Should fix** · `backend/convex/push.ts:18`
   Why: Registration permits unlimited devices, but delivery reads only the oldest 20. Once a user has 20 valid registrations, newly registered phones silently receive no notifications.
   Fix: Deliver to all registered devices using bounded batches, or enforce a registration limit with an explicit policy for retiring older devices.
