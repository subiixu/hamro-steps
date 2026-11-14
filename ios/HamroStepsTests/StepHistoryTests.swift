import Foundation
import Testing
@testable import HamroSteps

/// Daily-bucket aggregation over `MockStepSource`: 7 days, missing days zero.
struct StepHistoryTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func sevenDaysOldestFirstWithMissingDaysAsZero() async throws {
        let cal = calendar("Australia/Sydney")
        let now = date(cal, 2026, 11, 14, 15, 30) // Saturday afternoon
        let source = MockStepSource(samples: [
            StepSample(date: date(cal, 2026, 11, 6, 12), steps: 9_999),   // 8 days ago: outside
            StepSample(date: date(cal, 2026, 11, 8, 7), steps: 1_000),    // first day of window
            StepSample(date: date(cal, 2026, 11, 8, 23, 59), steps: 500), // same day, late
            StepSample(date: date(cal, 2026, 11, 10, 0, 0), steps: 4_200),// exactly midnight
            StepSample(date: date(cal, 2026, 11, 12, 18), steps: 8_000),
            StepSample(date: date(cal, 2026, 11, 14, 9), steps: 3_100),   // today, before now
            StepSample(date: date(cal, 2026, 11, 14, 17), steps: 700),    // today, after now: not yet
        ])

        let summary = try await StepHistory.load(days: 7, from: source, now: now, calendar: cal)

        #expect(summary.days.count == 7)
        #expect(summary.days.map(\.date) == (8...14).map { date(cal, 2026, 11, $0) })
        #expect(summary.days.map(\.steps) == [1_500, 0, 4_200, 0, 8_000, 0, 3_100])
        #expect(summary.today == 3_100)
        #expect(summary.total == 16_800)
        #expect(!summary.isAllZero)
    }

    @Test func emptySourceGivesSevenZeroDays() async throws {
        let cal = calendar("Asia/Kathmandu")
        let now = date(cal, 2026, 1, 3, 8)
        let summary = try await StepHistory.load(days: 7, from: MockStepSource(), now: now, calendar: cal)

        #expect(summary.days.count == 7)
        #expect(summary.days.allSatisfy { $0.steps == 0 })
        #expect(summary.days.first?.date == date(cal, 2025, 12, 28)) // crosses the year
        #expect(summary.isAllZero)
    }

    @Test func daylightSavingWeekStillHasSevenDistinctMidnights() async throws {
        let cal = calendar("America/New_York")
        let now = date(cal, 2026, 3, 10, 12) // DST began Sunday 8 March
        let source = MockStepSource(samples: (4...10).map {
            StepSample(date: date(cal, 2026, 3, $0, 10), steps: $0 * 100)
        })

        let summary = try await StepHistory.load(days: 7, from: source, now: now, calendar: cal)

        #expect(summary.days.map(\.steps) == (4...10).map { $0 * 100 })
        #expect(Set(summary.days.map(\.date)).count == 7)
        #expect(summary.days.allSatisfy { cal.startOfDay(for: $0.date) == $0.date })
    }

    @Test func totalsKeyedInsideTheDayAreNormalisedAndNegativesIgnored() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 6, 2, 20)
        let days = StepHistory.lastDays(2, endingAt: now, calendar: cal, totals: [
            date(cal, 2026, 6, 1, 13): 2_000,
            date(cal, 2026, 6, 2, 0): 50,
            date(cal, 2026, 6, 2, 9): -10,
            date(cal, 2026, 5, 20): 7_777,
        ])
        #expect(days == [
            DailySteps(date: date(cal, 2026, 6, 1), steps: 2_000),
            DailySteps(date: date(cal, 2026, 6, 2), steps: 50),
        ])
    }
}

@MainActor
struct StepStoreTests {
    private nonisolated static let fixedNow = Date(timeIntervalSince1970: 1_794_000_000)

    @Test func refreshLoadsTheWeek() async {
        let store = StepStore(source: MockStepSource.sampleWeek(now: Self.fixedNow), now: { Self.fixedNow })
        await store.refresh()
        guard case .loaded(let summary) = store.phase else {
            Issue.record("expected loaded, got \(store.phase)"); return
        }
        #expect(summary.days.count == StepStore.windowDays)
        #expect(summary.today == 7_318)
    }

    @Test func connectWithNoDataShowsZerosNotAnError() async {
        let store = StepStore(source: MockStepSource(), now: { Self.fixedNow })
        await store.connect()
        guard case .loaded(let summary) = store.phase else {
            Issue.record("expected loaded, got \(store.phase)"); return
        }
        #expect(summary.isAllZero)
    }

    @Test func unavailableSource() async {
        let store = StepStore(source: MockStepSource(isAvailable: false))
        await store.refresh()
        #expect(store.phase == .unavailable)
    }

    @Test func failedReadWithoutEarlierDataIsFailed() async {
        let store = StepStore(source: MockStepSource(failure: .init()))
        await store.refresh()
        #expect(store.phase == .failed)
    }
}
