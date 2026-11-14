import Foundation
import Observation

/// Sends this phone's steps to the family (PRD F4, F5): HealthKit totals
/// bucketed by Nepal day, today plus the 6 days before, oldest first.
/// Runs on foreground, pull-to-refresh and HealthKit background delivery.
@MainActor
@Observable
final class StepSync {
    nonisolated static let windowDays = 7
    private static let lastSyncedKey = "stepSync.lastSyncedAt"

    /// When this phone last sent steps successfully (kept across launches).
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false
    /// Whether the Health permission sheet has been shown.
    private(set) var healthRequested = false

    /// Runs after each successful sync, so Home reloads the week: a late
    /// correction can change a closed day's marker.
    @ObservationIgnored var onSynced: (@MainActor () async -> Void)?

    let source: any StepSource
    private let service: any FamilyService
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    init(source: any StepSource, service: any FamilyService, defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { .now }) {
        self.source = source
        self.service = service
        self.defaults = defaults
        self.now = now
        let stored = defaults.double(forKey: Self.lastSyncedKey)
        lastSyncedAt = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    var isHealthAvailable: Bool { source.isAvailable }

    func refreshHealthStatus() async {
        healthRequested = await source.hasRequestedAuthorization()
    }

    /// The Health permission screen: ask, then sync whatever we're allowed.
    func connectHealth() async {
        // An error here (rare: no Health on device) still falls through to a
        // sync, which simply finds nothing to send.
        try? await source.requestAuthorization()
        await refreshHealthStatus()
        await sync()
    }

    /// Reads the last 7 Nepal days and sends them. Returns whether anything
    /// was sent. When Health returns no data at all for the week, nothing is
    /// sent: that almost always means Health access is off, and the family
    /// should keep seeing "not synced yet" rather than a zero. A day Health
    /// does return, even as 0, is real data and is sent, so a total corrected
    /// down to 0 replaces the old value.
    @discardableResult
    func sync() async -> Bool {
        guard source.isAvailable, !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        let date = now()
        let calendar = NepalDay.calendar
        do {
            let start = StepHistory.windowStart(days: Self.windowDays, endingAt: date, calendar: calendar)
            let totals = try await source.dailyStepTotals(from: start, to: date, calendar: calendar)
            guard Self.hasData(totals, from: start, to: date) else { return false }
            let days = Self.payload(totals: totals, now: date)
            try await service.syncSteps(days: days)
            lastSyncedAt = date
            defaults.set(date.timeIntervalSince1970, forKey: Self.lastSyncedKey)
            await onSynced?()
            return true
        } catch {
            return false
        }
    }

    /// Whether Health returned any day in the window, zero-valued included.
    /// Sources leave out days with no samples, so an empty window means "no
    /// data", not "zero steps".
    nonisolated static func hasData(_ totals: [Date: Int], from start: Date, to end: Date) -> Bool {
        totals.keys.contains { $0 >= start && $0 <= end }
    }

    /// 7 Nepal days, oldest first and today last; days without data are 0;
    /// steps clamped to what the backend accepts.
    nonisolated static func payload(totals: [Date: Int], now: Date) -> [StepDay] {
        StepHistory.lastDays(windowDays, endingAt: now, calendar: NepalDay.calendar, totals: totals).map {
            StepDay(
                day: NepalDay.string(for: $0.date),
                steps: min(max($0.steps, FamilyRules.stepsRange.lowerBound), FamilyRules.stepsRange.upperBound)
            )
        }
    }

    /// Forget this phone's sync record (sign out, account deleted).
    func reset() {
        lastSyncedAt = nil
        defaults.removeObject(forKey: Self.lastSyncedKey)
    }
}
