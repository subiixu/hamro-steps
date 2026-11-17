# Second opinion: Steps history iOS: History screen (Family + Me) with trends
verdict: Has concerns
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-17-1253-history-ios.md
findings: 2
at: 2026-11-17T03:56:32Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, 8cbb69c6f0..7d33c1fc6f (shared checkout) (876 changed lines).

## Summary
The screen and service wiring fit the brief, but two data-handling choices can misstate the trends. Reported checks passed; I did not rerun tests during this read-only review.

## Findings
1. **Should fix** · `ios/HamroSteps/Features/History/HistoryModel.swift:63`
   Why: Today is excluded from the current average while all N previous days are included. This differs from the requested selected-period average and can report growth for identical weekly patterns: six 10,000-step days plus a 1,000-step today versus the same previous week produces roughly “Up 15%”.
   Fix: Compute trends over the selected N days as specified. If excluding unfinished days is retained, compare equivalent completed periods and clearly label that behavior; add a regression test with identical weekly patterns.
2. **Should fix** · `ios/HamroSteps/Features/History/HistoryModel.swift:283`
   Why: The first positive total is treated as the start of Health data, but StepSource distinguishes an explicitly recorded zero from missing data. Valid leading zero-step days disappear, inflating averages, and an entirely zero-valued window incorrectly becomes a missing-access/data message.
   Fix: Preserve data presence from the raw totals dictionary when determining where Health history starts. Retain explicitly recorded zero days and test both leading zeros and an all-zero window separately from an empty response.
