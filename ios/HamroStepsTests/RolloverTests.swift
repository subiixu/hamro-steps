import Foundation
import Testing
@testable import HamroSteps

/// A clock tests can move forward, shared by the model and the mock backend.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) { current = date }

    var now: Date { lock.withLock { current } }
    func set(_ date: Date) { lock.withLock { current = date } }
    var read: @Sendable () -> Date { { [unowned self] in self.now } }
}

/// Home moving on to a new Nepal day and week (review finding 1).
@MainActor
struct HomeRolloverTests {
    private func loadedHome(at clock: TestClock) async throws -> (HomeModel, MockFamilyService) {
        let service = MockFamilyService.sample(signedIn: true, now: clock.read)
        let home = HomeModel(service: service, defaults: TestTime.defaults(), now: clock.read)
        await home.update(families: try await service.myFamilies())
        return (home, service)
    }

    @Test func nextRefreshIsAt1815UTC() {
        let morning = TestTime.date("UTC", 2026, 11, 14, 6)
        #expect(HomeModel.nextNepalMidnight(after: morning) == TestTime.date("UTC", 2026, 11, 14, 18, 15))
        let justAfter = TestTime.date("UTC", 2026, 11, 14, 18, 15)
        #expect(HomeModel.nextNepalMidnight(after: justAfter) == TestTime.date("UTC", 2026, 11, 15, 18, 15))
    }

    @Test func crossingNepalMidnightMovesTodayAndTheMarkers() async throws {
        // Fri 13 Nov, 23:45 in Nepal.
        let clock = TestClock(TestTime.date("UTC", 2026, 11, 13, 18))
        let (home, service) = try await loadedHome(at: clock)
        #expect(home.loadedDay == "2026-11-13")
        #expect(home.week.first { $0.day == "2026-11-14" }?.isFuture == true)

        // Same day: nothing is fetched again.
        let weekCalls = await service.calls.filter { $0 == "familyWeek" }.count
        await home.refreshIfDayChanged()
        #expect(await service.calls.filter { $0 == "familyWeek" }.count == weekCalls)

        // Sat 14 Nov, 00:05 in Nepal.
        clock.set(TestTime.date("UTC", 2026, 11, 13, 18, 20))
        await home.refreshIfDayChanged()
        #expect(home.loadedDay == "2026-11-14")
        #expect(home.today?.day == "2026-11-14")
        #expect(home.week.first { $0.day == "2026-11-14" }?.isFuture == false)
        #expect(home.week.first { $0.day == "2026-11-15" }?.isFuture == true)
        // Nobody has synced the new day yet.
        #expect(home.total == 0)
        #expect(home.members.allSatisfy { $0.steps == nil })
    }

    @Test func sundayIntoMondayStartsANewWeek() async throws {
        // Sun 15 Nov, 23:45 in Nepal.
        let clock = TestClock(TestTime.date("UTC", 2026, 11, 15, 18))
        let (home, _) = try await loadedHome(at: clock)
        #expect(home.week.map(\.day).first == "2026-11-09")
        #expect(home.week.allSatisfy { !$0.isFuture })

        // Mon 16 Nov, 00:05 in Nepal.
        clock.set(TestTime.date("UTC", 2026, 11, 15, 18, 20))
        await home.refreshIfDayChanged()
        #expect(home.week.map(\.day) == (16...22).map { String(format: "2026-11-%02d", $0) })
        #expect(home.week.first?.isFuture == false)
        #expect(home.week.dropFirst().allSatisfy { $0.isFuture })
    }

    @Test func liveUpdatesKeepComingAfterARolloverRefresh() async throws {
        let clock = TestClock(TestTime.date("UTC", 2026, 11, 13, 18))
        let (home, service) = try await loadedHome(at: clock)
        let listening = Task { await home.listen() }
        defer { listening.cancel() }
        try await Task.sleep(for: .milliseconds(20))

        clock.set(TestTime.date("UTC", 2026, 11, 13, 18, 20))
        await home.refresh()
        try await service.syncSteps(days: [StepDay(day: "2026-11-14", steps: 2_500)])
        for _ in 0..<100 where home.total != 2_500 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(home.total == 2_500)
        #expect(home.week.first { $0.day == "2026-11-14" }?.total == 2_500)
    }

    @Test func aLiveUpdateForANewDayReloadsTheWeek() async throws {
        let clock = TestClock(TestTime.date("UTC", 2026, 11, 15, 18))
        let (home, service) = try await loadedHome(at: clock)
        let listening = Task { await home.listen() }
        defer { listening.cancel() }
        try await Task.sleep(for: .milliseconds(20))

        // Midnight passes with no timer; the next live update is for Monday.
        clock.set(TestTime.date("UTC", 2026, 11, 15, 18, 20))
        try await service.syncSteps(days: [StepDay(day: "2026-11-16", steps: 700)])
        for _ in 0..<100 where home.loadedDay != "2026-11-16" { try await Task.sleep(for: .milliseconds(10)) }
        #expect(home.week.first?.day == "2026-11-16")
        #expect(home.week.first?.total == 700)
    }

    @Test func aSuccessfulSyncReloadsTheWeek() async throws {
        let clock = TestClock(TestTime.date("UTC", 2026, 11, 14, 6))
        let (home, service) = try await loadedHome(at: clock)
        let sync = StepSync(
            source: MockStepSource(samples: [StepSample(date: TestTime.date("UTC", 2026, 11, 12, 6), steps: 9_000)]),
            service: service, defaults: TestTime.defaults(), now: clock.read
        )
        sync.onSynced = { await home.reload() }
        let before = try #require(home.week.first { $0.day == "2026-11-12" }?.total)

        #expect(await sync.sync())
        // The late steps reached a closed day, and Home shows it.
        #expect(home.week.first { $0.day == "2026-11-12" }?.total == before + 9_000)
    }
}

/// The mock backend's closed days (review finding 5): frozen goals and late
/// corrections, as the Convex `closeDay` and `syncSteps` do.
struct MockClosedDayTests {
    private func day(_ week: FamilyWeek, _ day: String) throws -> FamilyWeekDay {
        try #require(week.days.first { $0.day == day })
    }

    @Test func changingTheGoalKeepsClosedDaysGoals() async throws {
        // Wed 11 Nov, midday in Nepal.
        let clock = TestClock(TestTime.date("Asia/Kathmandu", 2026, 11, 11, 12))
        let service = MockFamilyService.sample(signedIn: true, now: clock.read)
        let yesterday = try day(try await service.familyWeek(familyId: "f_thapa"), "2026-11-10")
        #expect(yesterday.goal == 50_000)
        #expect(yesterday.hit)

        _ = try await service.updateFamily(familyId: "f_thapa", name: "Thapa Family", dailyGoal: 60_000)
        var week = try await service.familyWeek(familyId: "f_thapa")
        #expect(try day(week, "2026-11-10").goal == 50_000)
        #expect(try day(week, "2026-11-10").hit)
        #expect(try day(week, "2026-11-11").goal == 60_000)

        // Today closes with the goal it had at midnight; a later change
        // only affects the new day.
        clock.set(TestTime.date("Asia/Kathmandu", 2026, 11, 12, 9))
        _ = try await service.updateFamily(familyId: "f_thapa", name: "Thapa Family", dailyGoal: 20_000)
        week = try await service.familyWeek(familyId: "f_thapa")
        #expect(try day(week, "2026-11-11").goal == 60_000)
        #expect(try day(week, "2026-11-12").goal == 20_000)
    }

    @Test func aLateSyncCorrectsAClosedDayButNotItsGoal() async throws {
        // Tue 10 Nov in Nepal: a new family of one, goal 10,000.
        let clock = TestClock(TestTime.date("Asia/Kathmandu", 2026, 11, 10, 9))
        let service = MockFamilyService.sample(signedIn: true, newUser: true, now: clock.read)
        let family = try await service.createFamily(name: "Solo", dailyGoal: 10_000)
        try await service.syncSteps(days: [StepDay(day: "2026-11-10", steps: 8_000)])

        // Wed: Tuesday closed short of the goal.
        clock.set(TestTime.date("Asia/Kathmandu", 2026, 11, 11, 9))
        _ = try await service.updateFamily(familyId: family.id, name: "Solo", dailyGoal: 15_000)
        var tuesday = try day(try await service.familyWeek(familyId: family.id), "2026-11-10")
        #expect(tuesday.total == 8_000)
        #expect(!tuesday.hit)

        // The phone catches up: Tuesday becomes a hit against its own goal.
        try await service.syncSteps(days: [StepDay(day: "2026-11-10", steps: 12_000), StepDay(day: "2026-11-11", steps: 0)])
        tuesday = try day(try await service.familyWeek(familyId: family.id), "2026-11-10")
        #expect(tuesday.total == 12_000)
        #expect(tuesday.goal == 10_000)
        #expect(tuesday.hit)
    }

    @Test func aLateSyncOnlyCountsWhereTheUserWasAMemberAtMidnight() async throws {
        let clock = TestClock(TestTime.date("Asia/Kathmandu", 2026, 11, 11, 12))
        let service = MockFamilyService.sample(signedIn: true, now: clock.read)
        // Seeded closed days: Priya counted in both her families.
        let thapaBefore = try day(try await service.familyWeek(familyId: "f_thapa"), "2026-11-10").total
        let cousinsBefore = try day(try await service.familyWeek(familyId: "f_cousins"), "2026-11-10").total
        let created = try await service.createFamily(name: "New Family", dailyGoal: 10_000)

        try await service.syncSteps(days: [StepDay(day: "2026-11-10", steps: 4_000)])
        #expect(try day(try await service.familyWeek(familyId: "f_thapa"), "2026-11-10").total == thapaBefore + 4_000)
        #expect(try day(try await service.familyWeek(familyId: "f_cousins"), "2026-11-10").total == cousinsBefore + 4_000)
        // A family created today has no Tuesday to adjust.
        let fresh = try day(try await service.familyWeek(familyId: created.id), "2026-11-10")
        #expect(fresh.isBeforeFamily)
        #expect(fresh.total == 0)
    }
}
