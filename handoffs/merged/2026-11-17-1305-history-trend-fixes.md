# Steps history iOS: two trend fixes from the second opinion
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-17-1305-history-trend-fixes.md
## What the user asked
T-44: fix the two "Should fix" findings from the second opinion on the History screen, so the trend lines can't misstate change. Add regression tests for both.

## What changed
- **Compare like with like** (`HistoryTrend.compute`): today is still left out of the daily average. When it is, the day exactly N days before today is now also left out of the earlier period. The comparison is now the finished days of this period against the same weekdays one period earlier (N−1 against N−1). When today isn't shown, or is the only day, nothing changes. Goal-hit count, counted days and best day are unchanged.
  - The day is dropped by its date, not by its position in the list, so a missing earlier day can't cause the wrong day to be dropped.
- **Keep recorded zero days** (Me tab): where your Health history starts now depends on which days Health actually returned an entry for, even an entry of 0 steps. It no longer depends on the first day with more than 0 steps.
  - `split(_:recorded:range:)` takes the set of Nepal days present in the raw `dailyStepTotals` dictionary.
  - Days before the first recorded day are still treated as "no data". From that day on, every day counts as data, zeros included. If no day is recorded, it's "no data".
  - A window where every entry is zero now shows the chart with zero bars and the trend card, not the no-steps sentence. Only an empty response gives "no data".
  - I checked `HealthKitStepSource.dailyStepTotals`: days with no samples are missing from the dictionary (`sumQuantity()` is nil), and days that have samples are present. The mock works the same way.

## Files
- ios/HamroSteps/Features/History/HistoryModel.swift — modified
- ios/HamroStepsTests/HistoryModelTests.swift — modified

(Both files are still untracked from the earlier History handoff. `HistoryView.swift` didn't need any change.)

## Checks run
`araniko check`: passed · 2 of 2 passed · 1m 29s
- `scripts/check-ios.sh` · passed · 1m 24s
- `scripts/check-backend.sh` · passed · 5.8 s

New and updated tests in `HistoryModelTests`:
- `sameWeeklyPatternIsAboutTheSame`: this period is six days of 10,000 plus today at 1,000. The earlier period is six days of 10,000 plus 1,000 on the matching weekday. The result is "About the same", with an average of 10,000.
- `withoutTodayThePreviousPeriodIsKeptWhole`: when today isn't shown, or is the only day, the earlier period is kept whole.
- `meKeepsLeadingRecordedZeroDays`: leading days that Health recorded as 0 steps are kept.
- `meTabWithRecordedZerosShowsTheChart`: an all-zero window that has entries loads, shows zero bars and has trend lines.
- `meTabWithAnEmptyResponseIsNoData`: an empty response gives the no-data sentence.
- `meSkipsDaysBeforeHealthHadSteps`: updated to the new `recorded:` signature.

Not checked: I didn't run the app in the simulator, and I didn't take screenshots.

## Libraries used
none touched

## Notes for Nayo
- No shared files were edited.
- Suggested commit, folded into the History commit or on its own: `iOS History: compare finished days with the same weekdays; keep Health days recorded as zero (T-44)`

## Checks (run by Araniko)
Passed · 2 of 2 · 1m 37s · 2026-11-17 13:01 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 1m 32s
- `scripts/check-backend.sh` · passed · 5.5 s

## Checks override
Merged anyway: both files were already committed with the History merge e363aff (2026-11-17 13:01)
