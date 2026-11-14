import Foundation
import Testing
@testable import HamroSteps

/// A clock the tests move by hand.
final class ActivityTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = activityTestNow) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

private struct Offline: Error {}

struct MockWalkTests {
    @Test func startEndsTwoHoursLaterAndPostsToTheFeed() async throws {
        let clock = ActivityTestClock()
        let service = MockActivityService(now: { clock.now }, sampleFeed: false)
        let start = try await service.startWalk()
        #expect(start.startedAt == ActivityTime.millis(activityTestNow))
        #expect(start.endsAt - start.startedAt == 2 * 3600 * 1000)
        let feed = try await service.feed(familyId: MockActivityService.familyId)
        #expect(feed.map(\.type) == [.walkStarted])
        #expect(feed.first?.data?.walkId == start.walkId)
        #expect(feed.first?.actor == MockActivityService.me)
    }

    @Test func secondStartWhileWalkingIsRefused() async throws {
        let service = MockActivityService(now: { activityTestNow }, sampleFeed: false)
        _ = try await service.startWalk()
        await #expect(throws: ActivityError.alreadyWalking) { try await service.startWalk() }
    }

    @Test func walkStopsByItselfAfterTwoHours() async throws {
        let clock = ActivityTestClock()
        let service = MockActivityService(now: { clock.now }, sampleFeed: false)
        _ = try await service.startWalk()
        clock.advance(2 * 3600 - 1)
        #expect(await service.currentWalk() != nil)
        clock.advance(1)
        #expect(await service.currentWalk() == nil)
        _ = try await service.startWalk()
    }

    @Test func threeWalksPerNepalDay() async throws {
        let clock = ActivityTestClock()
        let service = MockActivityService(now: { clock.now }, sampleFeed: false)
        for _ in 0..<3 {
            _ = try await service.startWalk()
            try await service.stopWalk()
            clock.advance(60)
        }
        await #expect(throws: ActivityError.walkLimitReached) { try await service.startWalk() }
        // 10:03 → 00:00 the next Nepal day.
        clock.advance(14 * 3600 - 3 * 60)
        _ = try await service.startWalk()
    }

    @Test func stopIsANoOpWhenNotWalking() async throws {
        let service = MockActivityService(now: { activityTestNow }, sampleFeed: false)
        try await service.stopWalk()
        #expect(await service.currentWalk() == nil)
    }
}

struct MockStatusTests {
    @Test func defaultsTo24HoursAndExpires() async throws {
        let clock = ActivityTestClock()
        let service = MockActivityService(now: { clock.now }, sampleFeed: false)
        try await service.setStatus(StatusInput(preset: .commuting))
        let status = try #require(await service.currentStatus())
        #expect(status.preset == .commuting)
        #expect(status.expiresAt == ActivityTime.millis(activityTestNow.addingTimeInterval(24 * 3600)))
        clock.advance(24 * 3600)
        #expect(await service.currentStatus() == nil)
    }

    @Test func rejectsWhatTheServerRejects() async throws {
        let service = MockActivityService(now: { activityTestNow }, sampleFeed: false)
        await #expect(throws: ActivityError.invalidStatus) {
            try await service.setStatus(StatusInput(preset: .atWork, text: "Also this"))
        }
        await #expect(throws: ActivityError.invalidExpiry) {
            try await service.setStatus(StatusInput(preset: .atWork, expiresAt: ActivityTime.millis(activityTestNow) - 1))
        }
        try await service.setStatus(StatusInput(text: "Visiting Pokhara"))
        try await service.clearStatus()
        #expect(await service.currentStatus() == nil)
    }
}

struct MockFeedAndReactionTests {
    let service = MockActivityService(now: { activityTestNow })

    private func event(_ id: String) async throws -> FeedEvent {
        try #require(try await service.feed(familyId: MockActivityService.familyId).first { $0.id == id })
    }

    @Test func lastThreeNepalDaysNewestFirst() async throws {
        let feed = try await service.feed(familyId: MockActivityService.familyId)
        #expect(!feed.isEmpty)
        #expect(!feed.contains { $0.id == "e-old" })
        #expect(feed.map(\.createdAt) == feed.map(\.createdAt).sorted(by: >))
        await #expect(throws: ActivityError.notMember) { try await service.feed(familyId: "someone-else") }
    }

    @Test func reactAddsThenTheSameEmojiRemoves() async throws {
        let before = try await event("e1")
        #expect(before.myReaction == nil)
        try await service.react(eventId: "e1", emoji: .fire)
        let added = try await event("e1")
        #expect(added.myReaction == .fire)
        #expect(added.count(for: .fire) == before.count(for: .fire) + 1)
        try await service.react(eventId: "e1", emoji: .fire)
        let removed = try await event("e1")
        #expect(removed.myReaction == nil)
        #expect(removed.reactions == before.reactions)
    }

    @Test func aDifferentEmojiReplacesMine() async throws {
        let before = try await event("e3")
        #expect(before.myReaction == .heart)
        try await service.react(eventId: "e3", emoji: .clap)
        let after = try await event("e3")
        #expect(after.myReaction == .clap)
        #expect(after.count(for: .heart) == before.count(for: .heart) - 1)
        #expect(after.count(for: .clap) == before.count(for: .clap) + 1)
    }

    @Test func unknownEventIsRefused() async {
        await #expect(throws: ActivityError.notMember) { try await service.react(eventId: "nope", emoji: .clap) }
    }
}

struct MockNotificationTests {
    @Test func prefsAndDevices() async throws {
        let service = MockActivityService(sampleFeed: false)
        #expect(try await service.notificationPrefs() == .defaults)
        try await service.setNotificationPrefs(NotificationPrefsPatch(eveningNudge: true))
        #expect(try await service.notificationPrefs().eveningNudge)
        #expect(try await service.notificationPrefs().walkStarted)
        try await service.registerDevice(apnsToken: "abc123", environment: .sandbox)
        #expect(await service.registeredDevices() == ["abc123": .sandbox])
        try await service.unregisterDevice(apnsToken: "abc123")
        #expect(await service.registeredDevices().isEmpty)
    }
}

@MainActor
struct ActivityModelBehaviourTests {
    @Test func walkControllerShowsTheLimitKindly() async {
        let service = MockActivityService(now: { activityTestNow }, walksStartedToday: 3, sampleFeed: false)
        let controller = WalkController(service: service)
        await controller.start()
        #expect(controller.walk == nil)
        #expect(controller.notice == .limitReached)
        #expect(!controller.isWorking)
    }

    @Test func walkControllerStartsAndStops() async {
        let service = MockActivityService(now: { activityTestNow }, sampleFeed: false)
        let controller = WalkController(service: service)
        await controller.start()
        #expect(controller.walk == ActiveWalk(startedAt: activityTestNow, endsAt: activityTestNow.addingTimeInterval(7200)))
        await controller.stop()
        #expect(controller.walk == nil)
        await service.failNextCall(with: Offline())
        await controller.start()
        #expect(controller.notice == .failed)
    }

    @Test func walkControllerSyncsFromFamilyToday() {
        let controller = WalkController(service: MockActivityService(sampleFeed: false))
        let since = ActivityTime.millis(activityTestNow)
        controller.sync(walkingSince: since, walkEndsAt: since + 7_200_000)
        #expect(controller.walk?.endsAt == activityTestNow.addingTimeInterval(7200))
        controller.sync(walkingSince: nil, walkEndsAt: nil)
        #expect(controller.walk == nil)
    }

    @Test func feedReactionRevertsWhenTheServerFails() async throws {
        let service = MockActivityService(now: { activityTestNow })
        let model = FeedModel(service: service, familyId: MockActivityService.familyId, viewerId: MockActivityService.me.userId)
        await model.load()
        #expect(model.phase == .loaded)
        let before = try #require(model.events.first)
        await service.failNextCall(with: Offline())
        await model.react(.laugh, to: before.id)
        #expect(model.events.first == before)
        await model.react(.laugh, to: before.id)
        #expect(model.events.first?.myReaction == .laugh)
    }

    @Test func notificationSwitchMovesBackWhenSavingFails() async throws {
        let service = MockActivityService(sampleFeed: false)
        let model = NotificationSettingsModel(service: service)
        await model.load()
        await service.failNextCall(with: Offline())
        await model.set(.walkStarted, to: false)
        #expect(model.prefs.walkStarted)
        #expect(model.saveFailed)
        await model.set(.eveningNudge, to: true)
        #expect(model.prefs.eveningNudge)
        #expect(try await service.notificationPrefs().eveningNudge)
    }
}

struct ActivityFormattingTests {
    let us = Locale(identifier: "en_US")
    let kathmandu = ActivityTime.nepal

    /// Times use a narrow no-break space before AM/PM.
    private func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ") }

    static let elapsedCases: [(TimeInterval, String)] = [
        (0, "Just started"), (59, "Just started"), (60, "1 min"), (750, "12 min"),
        (3599, "59 min"), (3600, "1 hr"), (3900, "1 hr 5 min"), (7200, "2 hr"), (-30, "Just started"),
    ]

    @Test(arguments: elapsedCases)
    func elapsed(_ seconds: TimeInterval, _ expected: String) {
        #expect(ActivityFormat.elapsed(seconds) == expected)
    }

    @Test func walkingForAndAutoStop() {
        let walk = ActiveWalk(startedAt: activityTestNow, endsAt: activityTestNow.addingTimeInterval(7200))
        #expect(ActivityFormat.walkingFor(walk, now: activityTestNow.addingTimeInterval(30)) == "Just started")
        #expect(ActivityFormat.walkingFor(walk, now: activityTestNow.addingTimeInterval(65 * 60)) == "Walking for 1 hr 5 min")
        #expect(plain(ActivityFormat.autoStop(walk, locale: us, timeZone: kathmandu)) == "Stops by itself at 12:00 PM")
        #expect(ActivityFormat.timeOfDay(walk.endsAt, locale: Locale(identifier: "en_GB"), timeZone: kathmandu) == "12:00")
    }

    @Test func walkIsOverAtItsEndTime() {
        let walk = ActiveWalk(startedAt: activityTestNow, endsAt: activityTestNow.addingTimeInterval(7200))
        #expect(!walk.isOver(at: activityTestNow.addingTimeInterval(7199)))
        #expect(walk.isOver(at: activityTestNow.addingTimeInterval(7200)))
    }

    @Test func statusUntil() {
        let now = activityTestNow
        #expect(plain(ActivityFormat.statusUntil(now.addingTimeInterval(11 * 3600), now: now, locale: us, timeZone: kathmandu)) == "Until 9:00 PM")
        #expect(plain(ActivityFormat.statusUntil(now.addingTimeInterval(24 * 3600), now: now, locale: us, timeZone: kathmandu)) == "Until tomorrow, 10:00 AM")
        #expect(plain(ActivityFormat.statusUntil(now.addingTimeInterval(3 * 24 * 3600), now: now, locale: us, timeZone: kathmandu)) == "Until Tue, 10:00 AM")
    }

    @Test func relativeFeedTime() {
        let now = activityTestNow
        #expect(ActivityFormat.relative(now.addingTimeInterval(-20), now: now, locale: us) == "Just now")
        #expect(ActivityFormat.relative(now.addingTimeInterval(-5 * 60), now: now, locale: us).contains("5 min"))
    }
}
