import Foundation
import Testing
@testable import HamroSteps

private struct Refused: Error {}

/// Wraps the mock; `react` and `setNotificationPrefs` wait until the test
/// lets each call through (and says whether it succeeds).
private actor GatedActivityService: ActivityService {
    let inner: MockActivityService
    private var waiting: [(label: String, gate: CheckedContinuation<Bool, Never>)] = []

    init(_ inner: MockActivityService) { self.inner = inner }

    /// Labels of calls waiting to be released, oldest first.
    var held: [String] { waiting.map(\.label) }

    /// Lets the oldest held call finish, succeeding or failing.
    func release(succeed: Bool) {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().gate.resume(returning: succeed)
    }

    private func hold(_ label: String) async throws {
        let succeed = await withCheckedContinuation { waiting.append((label, $0)) }
        if !succeed { throw Refused() }
    }

    func startWalk() async throws -> WalkStart { try await inner.startWalk() }
    func stopWalk() async throws { try await inner.stopWalk() }
    func setStatus(_ input: StatusInput) async throws { try await inner.setStatus(input) }
    func clearStatus() async throws { try await inner.clearStatus() }
    func feed(familyId: String) async throws -> [FeedEvent] { try await inner.feed(familyId: familyId) }
    func react(eventId: String, emoji: Reaction) async throws {
        try await hold("react \(emoji)")
        try await inner.react(eventId: eventId, emoji: emoji)
    }
    func notificationPrefs() async throws -> NotificationPrefs { try await inner.notificationPrefs() }
    func setNotificationPrefs(_ patch: NotificationPrefsPatch) async throws {
        try await hold("prefs")
        try await inner.setNotificationPrefs(patch)
    }
    func registerDevice(apnsToken: String, environment: APNsEnvironment) async throws {
        try await inner.registerDevice(apnsToken: apnsToken, environment: environment)
    }
    func unregisterDevice(apnsToken: String) async throws { try await inner.unregisterDevice(apnsToken: apnsToken) }
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<200 where !(await condition()) { try await Task.sleep(for: .milliseconds(5)) }
}

/// Review 1429 findings 1–3: overlapping saves and the daily walk limit.
@MainActor
struct ActivityOverlapTests {
    @Test func aSwitchIsLockedWhileItSavesSoFailuresCanNotRestoreAStaleValue() async throws {
        let service = GatedActivityService(MockActivityService(sampleFeed: false))
        let model = NotificationSettingsModel(service: service)
        await model.load()
        #expect(model.prefs.walkStarted)

        let off = Task { await model.set(.walkStarted, to: false) }
        try await waitUntil { await service.held.count == 1 }
        #expect(model.isSaving(.walkStarted))
        #expect(!model.prefs.walkStarted)
        // Toggling back while the first save is pending is ignored.
        await model.set(.walkStarted, to: true)
        #expect(await service.held.count == 1)
        // Another switch saves independently.
        let nudge = Task { await model.set(.eveningNudge, to: true) }
        try await waitUntil { await service.held.count == 2 }
        #expect(model.isSaving(.eveningNudge))

        await service.release(succeed: false)
        await off.value
        #expect(model.prefs.walkStarted)
        #expect(!model.isSaving(.walkStarted))
        #expect(model.saveFailed)
        #expect(try await service.inner.notificationPrefs().walkStarted)

        await service.release(succeed: true)
        await nudge.value
        #expect(model.prefs.eveningNudge)
        #expect(try await service.inner.notificationPrefs().eveningNudge)
    }

    @Test func aFailedReactionDoesNotUndoALaterOneThatSaved() async throws {
        let mock = MockActivityService(now: { activityTestNow })
        let service = GatedActivityService(mock)
        let model = FeedModel(service: service, familyId: MockActivityService.familyId, viewerId: MockActivityService.me.userId)
        await model.load()
        let event = try #require(model.events.first { $0.myReaction == nil })

        let heart = Task { await model.react(.heart, to: event.id) }
        try await waitUntil { await service.held.count == 1 }
        await model.react(.fire, to: event.id)
        #expect(model.events.first { $0.id == event.id }?.myReaction == .fire)
        // Serialised: fire isn't sent until heart has an answer.
        #expect(await service.held == ["react heart"])

        await service.release(succeed: false)
        try await waitUntil { await service.held == ["react fire"] }
        #expect(model.events.first { $0.id == event.id }?.myReaction == .fire)

        // A feed refresh mid-flight keeps the pending tap.
        await model.load()
        #expect(model.events.first { $0.id == event.id }?.myReaction == .fire)

        await service.release(succeed: true)
        await heart.value
        #expect(model.events.first { $0.id == event.id }?.myReaction == .fire)
        await model.load()
        #expect(model.events.first { $0.id == event.id }?.myReaction == .fire)
    }

    @Test func aRefusedReactionAfterASavedOneFallsBackToTheSavedOne() async throws {
        let service = GatedActivityService(MockActivityService(now: { activityTestNow }))
        let model = FeedModel(service: service, familyId: MockActivityService.familyId, viewerId: MockActivityService.me.userId)
        await model.load()
        let event = try #require(model.events.first { $0.myReaction == nil })

        let heart = Task { await model.react(.heart, to: event.id) }
        try await waitUntil { await service.held.count == 1 }
        await model.react(.fire, to: event.id)
        await service.release(succeed: true)
        try await waitUntil { await service.held == ["react fire"] }
        await service.release(succeed: false)
        await heart.value
        #expect(model.events.first { $0.id == event.id }?.myReaction == .heart)
        await model.load()
        #expect(model.events.first { $0.id == event.id }?.myReaction == .heart)
    }

    @Test func theWalkLimitNoticeExpiresAtNepalMidnight() async throws {
        // 23:50 in Nepal on Sat 14 Nov.
        let clock = ActivityTestClock(ISO8601DateFormatter().date(from: "2026-11-14T18:05:00Z")!)
        let service = MockActivityService(now: { clock.now }, walksStartedToday: 3, sampleFeed: false)
        let controller = WalkController(service: service, now: { clock.now })
        await controller.start()
        #expect(controller.notice == .limitReached)

        clock.advance(5 * 60)  // 23:55: still today.
        controller.sync(walkingSince: nil, walkEndsAt: nil)
        #expect(controller.notice == .limitReached)

        clock.advance(10 * 60)  // 00:05 on Sunday.
        #expect(controller.notice == nil)
        controller.sync(walkingSince: nil, walkEndsAt: nil)
        #expect(controller.notice == nil)
        await controller.start()
        #expect(controller.walk != nil)
        #expect(controller.notice == nil)
    }
}
