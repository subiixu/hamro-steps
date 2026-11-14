import Foundation
import Testing
@testable import HamroSteps

/// Like the Convex `familyToday({day})` query: the live subscription only
/// ever delivers the Nepal day it was opened on.
private final class PinnedFamilyService: FamilyService {
    let inner: MockFamilyService
    let clock: TestClock

    init(_ inner: MockFamilyService, clock: TestClock) {
        self.inner = inner
        self.clock = clock
    }

    func createFamily(name: String, dailyGoal: Int) async throws -> FamilySummary {
        try await inner.createFamily(name: name, dailyGoal: dailyGoal)
    }
    func previewInvite(code: String) async throws -> InvitePreview { try await inner.previewInvite(code: code) }
    func joinFamily(code: String) async throws -> FamilySummary { try await inner.joinFamily(code: code) }
    func regenerateInviteCode(familyId: String) async throws -> String {
        try await inner.regenerateInviteCode(familyId: familyId)
    }
    func removeMember(familyId: String, userId: String) async throws {
        try await inner.removeMember(familyId: familyId, userId: userId)
    }
    func updateFamily(familyId: String, name: String, dailyGoal: Int) async throws -> FamilySummary {
        try await inner.updateFamily(familyId: familyId, name: name, dailyGoal: dailyGoal)
    }
    func leaveFamily(familyId: String) async throws { try await inner.leaveFamily(familyId: familyId) }
    func myFamilies() async throws -> [FamilySummary] { try await inner.myFamilies() }
    func syncSteps(days: [StepDay]) async throws -> SyncStepsResult { try await inner.syncSteps(days: days) }
    func deleteMyAccount() async throws { try await inner.deleteMyAccount() }
    func familyToday(familyId: String) async throws -> FamilyToday { try await inner.familyToday(familyId: familyId) }
    func familyWeek(familyId: String) async throws -> FamilyWeek { try await inner.familyWeek(familyId: familyId) }

    func familyTodayUpdates(familyId: String) -> AsyncStream<FamilyToday> {
        let pinned = NepalDay.string(for: clock.now)
        let source = inner.familyTodayUpdates(familyId: familyId)
        return AsyncStream { continuation in
            let task = Task {
                for await update in source where update.day == pinned { continuation.yield(update) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Records each midnight wait the model asks for, then waits until cancelled.
private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [Duration] = []
    var recorded: [Duration] { lock.withLock { waits } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            lock.withLock { waits.append(duration) }
            try await Task.sleep(for: .seconds(3_600))
        }
    }
}

@MainActor
struct HomeDayWatchTests {
    /// Review 1545 finding 2: after a sync, Home re-opens the subscription.
    @Test func aSyncAcrossMidnightReopensTheLiveSubscription() async throws {
        // Fri 13 Nov, 23:45 in Nepal.
        let clock = TestClock(TestTime.date("UTC", 2026, 11, 13, 18))
        let mock = MockFamilyService.sample(signedIn: true, now: clock.read)
        let service = PinnedFamilyService(mock, clock: clock)
        let home = HomeModel(service: service, defaults: TestTime.defaults(), now: clock.read)
        await home.update(families: try await service.myFamilies())
        let listening = Task { await home.listen() }
        defer { listening.cancel() }
        try await Task.sleep(for: .milliseconds(20))

        // Midnight passes; the first sync of Saturday loads the new day.
        clock.set(TestTime.date("UTC", 2026, 11, 13, 18, 20))
        let sync = StepSync(
            source: MockStepSource(samples: [StepSample(date: TestTime.date("UTC", 2026, 11, 13, 18, 18), steps: 1_000)]),
            service: service, defaults: TestTime.defaults(), now: clock.read
        )
        sync.onSynced = { await home.syncFinished() }
        #expect(await sync.sync())
        #expect(home.loadedDay == "2026-11-14")
        await home.refreshIfDayChanged()
        try await Task.sleep(for: .milliseconds(20))

        // A live update for Saturday still reaches Home.
        _ = try await mock.syncSteps(days: [StepDay(day: "2026-11-14", steps: 2_500)])
        for _ in 0..<100 where home.total != 2_500 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(home.total == 2_500)
    }

    /// Review 1545 finding 3: a clock change re-measures the midnight wait.
    @Test func aTimeChangeWithinTheDayReschedulesMidnight() async throws {
        // Sat 14 Nov, 11:45 in Nepal: midnight is 12h15m away.
        let clock = TestClock(TestTime.date("UTC", 2026, 11, 14, 6))
        let service = MockFamilyService.sample(signedIn: true, now: clock.read)
        let recorder = SleepRecorder()
        let home = HomeModel(service: service, defaults: TestTime.defaults(), now: clock.read, sleep: recorder.sleep)
        await home.update(families: try await service.myFamilies())
        let (changes, signal) = AsyncStream<Void>.makeStream()
        let watching = Task { await home.watchDayChanges(timeChanges: changes) }
        defer { watching.cancel() }

        for _ in 0..<100 where recorder.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let firstWait: Duration = .seconds(44_101)  // 12h15m + 1s
        #expect(recorder.recorded == [firstWait])

        // The clock jumps to 22:45 Nepal time, still Saturday.
        clock.set(TestTime.date("UTC", 2026, 11, 14, 17))
        signal.yield()
        for _ in 0..<100 where recorder.recorded.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        let revisedWait: Duration = .seconds(4_501)  // 1h15m + 1s
        #expect(recorder.recorded.last == revisedWait)
        #expect(home.loadedDay == "2026-11-14")
    }
}
