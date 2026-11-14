import Foundation
import Testing
@testable import HamroSteps

/// Nepal-day bucketing (Asia/Kathmandu, UTC+5:45; midnight there is 18:15
/// UTC) and the `syncSteps` payload, wherever the phone is.
struct NepalDayTests {
    @Test func boundaryIsAt1815UTC() {
        let before = TestTime.date("UTC", 2026, 11, 13, 18, 14)
        let after = TestTime.date("UTC", 2026, 11, 13, 18, 15)
        #expect(NepalDay.string(for: before) == "2026-11-13")
        #expect(NepalDay.string(for: after) == "2026-11-14")
        #expect(NepalDay.start(of: "2026-11-14") == after)
    }

    @Test func weekIsMondayToSundayInNepal() {
        // Sunday 15 Nov 2026, 23:00 in Nepal.
        let date = TestTime.date("Asia/Kathmandu", 2026, 11, 15, 23)
        #expect(NepalDay.week(containing: date) == (9...15).map { String(format: "2026-11-%02d", $0) })
    }

    @Test func samplesEitherSideOfNepalMidnightLandInDifferentDays() async throws {
        let source = MockStepSource(samples: [
            StepSample(date: TestTime.date("UTC", 2026, 11, 13, 18, 10), steps: 1_000), // Nepal 13th, 23:55
            StepSample(date: TestTime.date("UTC", 2026, 11, 13, 18, 20), steps: 250),   // Nepal 14th, 00:05
        ])
        let now = TestTime.date("UTC", 2026, 11, 14, 6)
        let start = StepHistory.windowStart(days: 7, endingAt: now, calendar: NepalDay.calendar)
        let totals = try await source.dailyStepTotals(from: start, to: now, calendar: NepalDay.calendar)
        let payload = StepSync.payload(totals: totals, now: now)
        #expect(payload.suffix(2) == [StepDay(day: "2026-11-13", steps: 1_000), StepDay(day: "2026-11-14", steps: 250)])
    }

    @Test func phoneInSydneyEarlyMorningIsStillTheNepalEvening() async throws {
        // Sat 15 Nov, 03:00 in Sydney (AEDT) = Fri 14 Nov, 21:45 in Nepal.
        let now = TestTime.date("Australia/Sydney", 2026, 11, 15, 3)
        let source = MockStepSource(samples: [
            StepSample(date: TestTime.date("Australia/Sydney", 2026, 11, 15, 1), steps: 400),   // Nepal 14th 19:45
            StepSample(date: TestTime.date("Australia/Sydney", 2026, 11, 14, 22), steps: 3_000), // Nepal 14th 16:45
            StepSample(date: TestTime.date("Australia/Sydney", 2026, 11, 14, 4), steps: 900),    // Nepal 13th 22:45
        ])
        let payload = try await syncPayload(source, now: now)
        #expect(payload.last == StepDay(day: "2026-11-14", steps: 3_400))
        #expect(payload[payload.count - 2] == StepDay(day: "2026-11-13", steps: 900))
    }

    @Test func phoneInNewYorkEveningIsAlreadyTomorrowInNepal() async throws {
        // Fri 14 Nov, 20:00 in New York (EST) = Sat 15 Nov, 06:45 in Nepal.
        let now = TestTime.date("America/New_York", 2026, 11, 14, 20)
        let source = MockStepSource(samples: [
            StepSample(date: TestTime.date("America/New_York", 2026, 11, 14, 19), steps: 1_200), // Nepal 15th 05:45
            StepSample(date: TestTime.date("America/New_York", 2026, 11, 14, 13), steps: 6_000), // Nepal 14th 23:45
        ])
        let payload = try await syncPayload(source, now: now)
        #expect(payload.last == StepDay(day: "2026-11-15", steps: 1_200))
        #expect(payload[payload.count - 2] == StepDay(day: "2026-11-14", steps: 6_000))
    }

    @Test func payloadIsSevenDaysOldestFirstTodayLastClamped() {
        let now = TestTime.date("UTC", 2026, 11, 14, 6) // Nepal 14th, 11:45
        let today = NepalDay.start(of: "2026-11-14")!
        let payload = StepSync.payload(totals: [today: 250_000, today.addingTimeInterval(-86_400 * 3): -5], now: now)
        #expect(payload.map(\.day) == (8...14).map { String(format: "2026-11-%02d", $0) })
        #expect(payload.last?.steps == FamilyRules.stepsRange.upperBound)
        #expect(payload.allSatisfy { $0.steps >= 0 })
    }

    private func syncPayload(_ source: MockStepSource, now: Date) async throws -> [StepDay] {
        let start = StepHistory.windowStart(days: StepSync.windowDays, endingAt: now, calendar: NepalDay.calendar)
        let totals = try await source.dailyStepTotals(from: start, to: now, calendar: NepalDay.calendar)
        return StepSync.payload(totals: totals, now: now)
    }
}

@MainActor
struct StepSyncTests {
    @Test func syncSendsTheWeekAndRecordsTheTime() async throws {
        let now = TestTime.date("UTC", 2026, 11, 14, 6)
        let service = MockFamilyService.sample(signedIn: true, now: { now })
        let source = MockStepSource(samples: [StepSample(date: now.addingTimeInterval(-3600), steps: 4_321)])
        let defaults = TestTime.defaults()
        let sync = StepSync(source: source, service: service, defaults: defaults, now: { now })

        #expect(await sync.sync())

        let sent = await service.lastSyncedDays
        #expect(sent.count == 7)
        #expect(sent.last == StepDay(day: "2026-11-14", steps: 4_321))
        #expect(sync.lastSyncedAt == now)
        // Kept across launches.
        #expect(StepSync(source: source, service: service, defaults: defaults).lastSyncedAt == now)
        // And the family sees it straight away.
        let today = try await service.familyToday(familyId: "f_thapa")
        #expect(today.members.first { $0.userId == MockFamilyService.sampleUserId }?.steps == 4_321)
    }

    @Test func aWeekWithNoStepsIsNotSent() async {
        let service = MockFamilyService.sample(signedIn: true)
        let sync = StepSync(source: MockStepSource(), service: service, defaults: TestTime.defaults())
        #expect(await sync.sync() == false)
        #expect(await service.calls.contains("syncSteps") == false)
        #expect(sync.lastSyncedAt == nil)
    }

    @Test func aCorrectionDownToZeroIsSent() async throws {
        let now = TestTime.date("UTC", 2026, 11, 14, 6)
        let service = MockFamilyService.sample(signedIn: true, now: { now })
        let earlier = now.addingTimeInterval(-3600)
        let first = StepSync(
            source: MockStepSource(samples: [StepSample(date: earlier, steps: 4_000)]),
            service: service, defaults: TestTime.defaults(), now: { now }
        )
        #expect(await first.sync())

        // Health now returns the day explicitly as 0 (steps deleted in Health).
        let later = now.addingTimeInterval(60)
        let corrected = StepSync(
            source: MockStepSource(samples: [StepSample(date: earlier, steps: 0)]),
            service: service, defaults: TestTime.defaults(), now: { later }
        )
        #expect(await corrected.sync())
        #expect(corrected.lastSyncedAt == later)
        #expect(await service.lastSyncedDays.last == StepDay(day: "2026-11-14", steps: 0))
        let today = try await service.familyToday(familyId: "f_thapa")
        #expect(today.members.first { $0.userId == MockFamilyService.sampleUserId }?.steps == 0)
    }

    @Test func hasDataCountsOnlyDaysHealthReturned() {
        let now = TestTime.date("UTC", 2026, 11, 14, 6)
        #expect(StepSync.hasData([:], from: now.addingTimeInterval(-86_400), to: now) == false)
        #expect(StepSync.hasData([now.addingTimeInterval(-60): 0], from: now.addingTimeInterval(-86_400), to: now))
        // A key outside the window doesn't count.
        #expect(StepSync.hasData([now.addingTimeInterval(-10 * 86_400): 50], from: now.addingTimeInterval(-86_400), to: now) == false)
    }

    @Test func signedOutSyncFailsQuietly() async {
        let service = MockFamilyService.sample(signedIn: false)
        let source = MockStepSource(samples: [StepSample(date: .now.addingTimeInterval(-60), steps: 10)])
        let sync = StepSync(source: source, service: service, defaults: TestTime.defaults())
        #expect(await sync.sync() == false)
        #expect(sync.lastSyncedAt == nil)
    }
}
