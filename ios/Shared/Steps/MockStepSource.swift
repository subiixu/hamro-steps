import Foundation

/// A single recorded walk: `steps` taken at `date`.
struct StepSample: Hashable, Sendable {
    let date: Date
    let steps: Int
}

/// In-memory `StepSource` for tests and previews. Buckets its samples into
/// calendar days the same way the HealthKit statistics query does.
struct MockStepSource: StepSource {
    var samples: [StepSample]
    var isAvailable: Bool = true
    /// Simulated latency, so previews can show the loading state.
    var delay: Duration = .zero
    var failure: MockFailure?
    var alreadyRequested = true

    struct MockFailure: Error, Hashable, Sendable {}

    init(samples: [StepSample] = [], isAvailable: Bool = true, delay: Duration = .zero, failure: MockFailure? = nil) {
        self.samples = samples
        self.isAvailable = isAvailable
        self.delay = delay
        self.failure = failure
    }

    func requestAuthorization() async throws {
        if delay > .zero { try await Task.sleep(for: delay) }
    }

    func hasRequestedAuthorization() async -> Bool { alreadyRequested }

    func dailyStepTotals(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        var totals: [Date: Int] = [:]
        for sample in samples where sample.date >= start && sample.date < end {
            totals[calendar.startOfDay(for: sample.date), default: 0] += sample.steps
        }
        return totals
    }
}

extension MockStepSource {
    /// A believable week for previews and screenshots, ending at `now`.
    static func sampleWeek(now: Date = .now, calendar: Calendar = .current) -> MockStepSource {
        let perDay = [6_420, 9_870, 4_210, 11_305, 8_032, 12_640, 7_318]
        let today = calendar.startOfDay(for: now)
        let samples = perDay.enumerated().flatMap { index, steps -> [StepSample] in
            let offset = perDay.count - 1 - index
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
            // Two walks a day, morning and evening (today: morning only, so it
            // stays before `now` for most of the day).
            let morning = day.addingTimeInterval(8 * 3600)
            let evening = day.addingTimeInterval(18 * 3600)
            if offset == 0 { return [StepSample(date: min(morning, now.addingTimeInterval(-60)), steps: steps)] }
            return [StepSample(date: morning, steps: steps / 2), StepSample(date: evening, steps: steps - steps / 2)]
        }
        return MockStepSource(samples: samples)
    }
}
