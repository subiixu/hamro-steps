import Foundation
import HealthKit

/// Reads step count from HealthKit (read-only, `stepCount` only).
///
/// `HKHealthStore` is documented as thread-safe, hence `@unchecked Sendable`.
final class HealthKitStepSource: StepSource, @unchecked Sendable {
    private let store: HKHealthStore
    private let stepType = HKQuantityType(.stepCount)

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [stepType])
    }

    func hasRequestedAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [stepType])
        return status == .unnecessary
    }

    /// Wakes the app when new steps land in Health, at most hourly, even when
    /// it isn't running. Call once at launch (Apple requires registering the
    /// observer every launch). `onChange` must call `done` when it's finished,
    /// or HealthKit backs off and stops waking the app.
    func startBackgroundDelivery(onChange: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) {
        guard isAvailable else { return }
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { _, completionHandler, error in
            let finish = CompletionBox(completionHandler)
            if error != nil {
                finish.call()
                return
            }
            onChange { finish.call() }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { _, _ in }
    }

    /// One `HKStatisticsCollectionQuery`: cumulative sum in one-day buckets
    /// anchored at midnight in `calendar` (Nepal time for family sync), so
    /// DST days are respected. A denied read comes back as no data, not an error.
    func dailyStepTotals(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        guard isAvailable else { return [:] }
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)
        let type = stepType
        let store = store

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if Self.meansNoData(error) {
                        continuation.resume(returning: [:])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var totals: [Date: Int] = [:]
                collection?.enumerateStatistics(from: anchor, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        totals[calendar.startOfDay(for: statistics.startDate)] =
                            Int(sum.doubleValue(for: .count()).rounded())
                    }
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    private static func meansNoData(_ error: any Error) -> Bool {
        guard let hkError = error as? HKError else { return false }
        switch hkError.code {
        case .errorNoData, .errorAuthorizationNotDetermined, .errorAuthorizationDenied:
            return true
        default:
            return false
        }
    }
}

/// HealthKit's observer completion handler, carried across to the sync task.
/// HealthKit allows calling it from any thread; we call it exactly once.
private final class CompletionBox: @unchecked Sendable {
    private let handler: HKObserverQueryCompletionHandler
    private let lock = NSLock()
    private var called = false

    init(_ handler: @escaping HKObserverQueryCompletionHandler) {
        self.handler = handler
    }

    func call() {
        lock.lock()
        let first = !called
        called = true
        lock.unlock()
        if first { handler() }
    }
}
