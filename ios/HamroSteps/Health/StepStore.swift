import Foundation
import Observation

/// Owns the user's own step numbers for the UI.
@MainActor
@Observable
final class StepStore {
    enum Phase: Equatable {
        case idle
        case connecting
        case loading
        case loaded(StepSummary)
        case unavailable
        case failed
    }

    static let windowDays = 7

    private(set) var phase: Phase = .idle
    /// Last good numbers, kept while a refresh is in flight.
    private(set) var summary: StepSummary?

    private let source: any StepSource
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(source: any StepSource, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { .now }) {
        self.source = source
        self.calendar = calendar
        self.now = now
    }

    /// The "Connect Apple Health" button: ask, then read whatever we're given.
    func connect() async {
        guard source.isAvailable else { phase = .unavailable; return }
        phase = .connecting
        // An error here (rare: missing entitlement, no Health on device) still
        // falls through to a read, which shows zeros with the hint.
        try? await source.requestAuthorization()
        await refresh()
    }

    func refresh() async {
        guard source.isAvailable else { phase = .unavailable; return }
        if summary == nil { phase = .loading }
        do {
            let result = try await StepHistory.load(days: Self.windowDays, from: source, now: now(), calendar: calendar)
            summary = result
            phase = .loaded(result)
        } catch is CancellationError {
            return
        } catch {
            phase = summary.map(Phase.loaded) ?? .failed
        }
    }
}
