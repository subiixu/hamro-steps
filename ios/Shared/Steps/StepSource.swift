import Foundation

/// Anything that can supply step counts. The app uses `HealthKitStepSource`;
/// tests and previews use `MockStepSource`, so they never touch HealthKit.
protocol StepSource: Sendable {
    /// False where step data can't exist at all (HealthKit unavailable).
    var isAvailable: Bool { get }

    /// Asks for read access to step count. Succeeding says nothing about
    /// whether the user allowed it: HealthKit hides read denials.
    func requestAuthorization() async throws

    /// Summed steps per calendar day for days starting in `start..<end`,
    /// keyed by the start of each day. Days with no data may be missing.
    func dailyStepTotals(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int]
}

enum StepHistory {
    /// The `count` days ending with the day containing `now`, oldest first.
    /// Days missing from `totals` are zero; totals outside the window are
    /// ignored. Keys are normalised with `calendar.startOfDay`, so sources
    /// may key by any instant inside the day.
    static func lastDays(
        _ count: Int,
        endingAt now: Date,
        calendar: Calendar,
        totals: [Date: Int]
    ) -> [DailySteps] {
        guard count > 0 else { return [] }
        var byDay: [Date: Int] = [:]
        for (date, steps) in totals {
            byDay[calendar.startOfDay(for: date), default: 0] += max(0, steps)
        }
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailySteps(date: day, steps: byDay[day] ?? 0)
        }
    }

    /// Start of the first day in a `count`-day window ending today.
    static func windowStart(days count: Int, endingAt now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(max(count, 1) - 1), to: today) ?? today
    }

    /// Reads the last `count` days from `source` and fills the gaps.
    static func load(
        days count: Int,
        from source: any StepSource,
        now: Date,
        calendar: Calendar
    ) async throws -> StepSummary {
        let start = windowStart(days: count, endingAt: now, calendar: calendar)
        let totals = try await source.dailyStepTotals(from: start, to: now, calendar: calendar)
        return StepSummary(days: lastDays(count, endingAt: now, calendar: calendar, totals: totals))
    }
}
