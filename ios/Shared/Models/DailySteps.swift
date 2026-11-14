import Foundation

/// One calendar day's step total. `date` is the start of that day in the
/// calendar the totals were bucketed in.
struct DailySteps: Identifiable, Hashable, Sendable {
    let date: Date
    let steps: Int

    var id: Date { date }
}

/// What the Today screen (and later the widget) shows: the last N days,
/// oldest first, with today last.
struct StepSummary: Hashable, Sendable {
    let days: [DailySteps]

    var today: Int { days.last?.steps ?? 0 }
    var total: Int { days.reduce(0) { $0 + $1.steps } }

    /// HealthKit never says a read was denied; a denied read just returns no
    /// samples. A whole week of zeros is the hint we show the user.
    var isAllZero: Bool { days.allSatisfy { $0.steps == 0 } }
}
