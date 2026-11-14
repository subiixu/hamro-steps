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

    /// One `HKStatisticsCollectionQuery`: cumulative sum in one-day buckets
    /// anchored at local midnight, so DST days and the user's calendar are
    /// respected. A denied read comes back as no data, not an error.
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
