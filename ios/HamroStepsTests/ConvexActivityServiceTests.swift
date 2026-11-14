import Foundation
import Testing
@testable import HamroSteps

/// `ConvexActivityService` over the fake transport: the arguments each call
/// sends, the backend's return shapes, error codes, and the device calls'
/// cancellation contract.
struct ConvexActivityServiceTests {
    // MARK: Arguments

    @Test func callsCarryTheRightNamesAndArgs() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        let t = h.transport
        t.respond("walks:startWalk", json: ActivityFixtures.walkStart)
        t.respond("walks:stopWalk", json: "null")
        t.respond("status:setStatus", json: ActivityFixtures.statusPreset)
        t.respond("status:setStatus", json: ActivityFixtures.statusText)
        t.respond("status:clearStatus", json: "null")
        t.respond("feed:feed", json: "[]")
        t.respond("feed:react", json: #"{"myReaction":"🔥"}"#)
        t.respond("notifications:notificationPrefs", json: ActivityFixtures.prefs)
        t.respond("notifications:setNotificationPrefs", json: ActivityFixtures.prefs)
        t.respond("notifications:registerDevice", json: "null")
        t.respond("notifications:unregisterDevice", json: "null")

        let a = h.services.activity
        _ = try await a.startWalk()
        try await a.stopWalk()
        try await a.setStatus(StatusInput(preset: .atWork, text: nil, expiresAt: nil))
        try await a.setStatus(StatusInput(preset: nil, text: "Making momos", expiresAt: 1_800_000_500_000))
        try await a.clearStatus()
        _ = try await a.feed(familyId: "fam_1")
        try await a.react(eventId: "evt_1", emoji: .fire)
        _ = try await a.notificationPrefs()
        try await a.setNotificationPrefs(NotificationPrefsPatch(.eveningNudge, true))
        try await a.registerDevice(apnsToken: "abc123", environment: .sandbox)
        try await a.unregisterDevice(apnsToken: "abc123")

        let calls = t.calls.filter { $0.name != "users:me" }
        #expect(calls == [
            .init(kind: "mutation", name: "walks:startWalk", args: [:]),
            .init(kind: "mutation", name: "walks:stopWalk", args: [:]),
            .init(kind: "mutation", name: "status:setStatus", args: ["preset": .string("at_work")]),
            .init(kind: "mutation", name: "status:setStatus", args: ["text": .string("Making momos"), "expiresAt": .number(1_800_000_500_000)]),
            .init(kind: "mutation", name: "status:clearStatus", args: [:]),
            .init(kind: "query", name: "feed:feed", args: ["familyId": .string("fam_1")]),
            .init(kind: "mutation", name: "feed:react", args: ["eventId": .string("evt_1"), "emoji": .string("🔥")]),
            .init(kind: "query", name: "notifications:notificationPrefs", args: [:]),
            .init(kind: "mutation", name: "notifications:setNotificationPrefs", args: ["eveningNudge": .bool(true)]),
            .init(kind: "mutation", name: "notifications:registerDevice", args: ["apnsToken": .string("abc123"), "environment": .string("sandbox")]),
            .init(kind: "mutation", name: "notifications:unregisterDevice", args: ["apnsToken": .string("abc123")]),
        ])
    }

    @Test func prefsPatchSendsOnlyTheSetFields() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("notifications:setNotificationPrefs", json: ActivityFixtures.prefs)
        try await h.services.activity.setNotificationPrefs(NotificationPrefsPatch(walkStarted: false, goalHit: true, reactions: nil, eveningNudge: false))
        #expect(h.transport.calls.last?.args == ["walkStarted": .bool(false), "goalHit": .bool(true), "eveningNudge": .bool(false)])
    }

    @Test func productionDevicesSayProduction() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("notifications:registerDevice", json: "null")
        try await h.services.activity.registerDevice(apnsToken: "ff00", environment: .production)
        #expect(h.transport.calls.last?.args["environment"] == .string("production"))
    }

    // MARK: Decoding

    @Test func startWalkDecodes() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("walks:startWalk", json: ActivityFixtures.walkStart)
        let walk = try await h.services.activity.startWalk()
        #expect(walk == WalkStart(walkId: "walk_1", startedAt: 1_800_000_000_000, endsAt: 1_800_007_200_000))
    }

    @Test func notificationPrefsDecode() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("notifications:notificationPrefs", json: ActivityFixtures.prefs)
        let prefs = try await h.services.activity.notificationPrefs()
        #expect(prefs == NotificationPrefs(walkStarted: true, goalHit: false, reactions: true, eveningNudge: true))
    }

    @Test func feedDecodes() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("feed:feed", json: ActivityFixtures.feed)
        let feed = try await h.services.activity.feed(familyId: "fam_1")
        #expect(feed.count == 4)

        let walk = feed[0]
        #expect(walk.id == "evt_1")
        #expect(walk.type == .walkStarted)
        #expect(walk.actor == FeedActor(userId: "user_1", name: "Sita", avatarColor: "#E07A5F"))
        #expect(walk.day == "2027-01-15")
        #expect(walk.createdAt == 1_800_000_000_000)
        #expect(walk.data == FeedEventData(walkId: "walk_1"))
        // The emoji outside the fixed set is dropped; the plain heart counts as ❤️.
        #expect(walk.reactions == [ReactionCount(emoji: .clap, count: 2), ReactionCount(emoji: .heart, count: 1)])
        #expect(walk.myReaction == .clap)

        // Someone who hasn't given a name yet: an empty name, like familyToday.
        #expect(feed[1].actor == FeedActor(userId: "user_2", name: "", avatarColor: "#3D405B"))
        #expect(feed[1].type == .member5k)
        #expect(feed[1].data == nil)
        #expect(feed[1].myReaction == nil)

        // A family milestone has no actor.
        #expect(feed[2].actor == nil)
        #expect(feed[2].type == .family100)
        #expect(feed[2].reactions.isEmpty)

        // A type this app doesn't know is kept, but not displayable.
        #expect(feed[3].type == .unknown)
        #expect(!feed[3].isDisplayable)
    }

    // MARK: Errors

    @Test(arguments: [
        ("already_walking", ActivityError.alreadyWalking),
        ("walk_limit_reached", .walkLimitReached),
        ("invalid_status", .invalidStatus),
        ("invalid_expiry", .invalidExpiry),
        ("invalid_emoji", .invalidEmoji),
        ("not_member", .notMember),
    ])
    func contractCodesAreActivityErrors(code: String, expected: ActivityError) async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.fail("walks:startWalk", ConvexCallError(convexData: #"{"code":"\#(code)"}"#))
        await #expect(throws: expected) { try await h.services.activity.startWalk() }
    }

    @Test func eachMethodMapsItsErrors() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        let t = h.transport
        let a = h.services.activity
        t.fail("walks:stopWalk", .convex(code: "not_member"))
        t.fail("status:setStatus", .convex(code: "invalid_expiry"))
        t.fail("status:clearStatus", .convex(code: "not_member"))
        t.fail("feed:feed", .convex(code: "not_member"))
        t.fail("feed:react", .convex(code: "invalid_emoji"))
        t.fail("notifications:notificationPrefs", .server("boom"))
        t.fail("notifications:setNotificationPrefs", .client("offline"))
        t.fail("notifications:registerDevice", .convex(code: "new_code"))
        t.fail("notifications:unregisterDevice", .server("boom"))

        await #expect(throws: ActivityError.notMember) { try await a.stopWalk() }
        await #expect(throws: ActivityError.invalidExpiry) {
            try await a.setStatus(StatusInput(preset: .resting, text: nil, expiresAt: 1))
        }
        await #expect(throws: ActivityError.notMember) { try await a.clearStatus() }
        await #expect(throws: ActivityError.notMember) { try await a.feed(familyId: "fam_9") }
        await #expect(throws: ActivityError.invalidEmoji) { try await a.react(eventId: "evt_1", emoji: .heart) }
        await #expect(throws: FamilyServiceError.unavailable("server")) { try await a.notificationPrefs() }
        await #expect(throws: FamilyServiceError.unavailable("client")) {
            try await a.setNotificationPrefs(NotificationPrefsPatch(.goalHit, false))
        }
        await #expect(throws: FamilyServiceError.unavailable("new_code")) {
            try await a.registerDevice(apnsToken: "abc", environment: .sandbox)
        }
        await #expect(throws: FamilyServiceError.unavailable("server")) { try await a.unregisterDevice(apnsToken: "abc") }
    }

    @Test func signedOutIsNotAuthenticated() async throws {
        let h = await ConvexHarness()
        await #expect(throws: FamilyServiceError.notAuthenticated) { try await h.services.activity.startWalk() }
        #expect(h.transport.calls.isEmpty)
    }

    @Test func invalidTokenRefreshesAndRetriesOnce() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.fail("feed:feed", .convex(code: "invalid_token"))
        h.transport.respond("feed:feed", json: ActivityFixtures.feed)
        #expect(try await h.services.activity.feed(familyId: "fam_1").count == 4)
        #expect(await h.endpoints.refreshes == ["refresh-1"])
    }

    // MARK: Cancellation (device calls)

    @Test func registerDeviceReturnsPromptlyWhenCancelled() async throws {
        let h = await HangingHarness()
        let task = Task { try await h.activity.registerDevice(apnsToken: "abc", environment: .sandbox) }
        await h.waitUntilHanging()
        let elapsed = try await Self.cancelAndTime(task)
        #expect(elapsed < .milliseconds(100))
        await h.release()
    }

    @Test func unregisterDeviceReturnsPromptlyWhenCancelled() async throws {
        let h = await HangingHarness()
        let task = Task { try await h.activity.unregisterDevice(apnsToken: "abc") }
        await h.waitUntilHanging()
        let elapsed = try await Self.cancelAndTime(task)
        #expect(elapsed < .milliseconds(100))
        await h.release()
    }

    @Test func alreadyCancelledDeviceCallSendsNothing() async throws {
        let h = await HangingHarness()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await h.activity.unregisterDevice(apnsToken: "abc")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!h.transport.calls.contains { $0.name == "notifications:unregisterDevice" })
    }

    @Test func deviceCallsStillReturnTheirResultAndErrors() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("notifications:registerDevice", json: "null")
        h.transport.fail("notifications:unregisterDevice", .convex(code: "not_authenticated"))
        await h.endpoints.setRefreshResults([.failure(.invalidToken)])
        try await h.services.activity.registerDevice(apnsToken: "abc", environment: .sandbox)
        await #expect(throws: FamilyServiceError.notAuthenticated) { try await h.services.activity.unregisterDevice(apnsToken: "abc") }
    }

    /// Cancels `task` and measures how long it takes to come back. It must
    /// come back with `CancellationError`.
    private static func cancelAndTime(_ task: Task<Void, any Error>) async throws -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        let result = await task.result
        let elapsed = clock.now - start
        #expect(throws: CancellationError.self) { try result.get() }
        return elapsed
    }
}

/// A signed-in connection whose device calls never answer, cancelled or not,
/// until `release()`.
private struct HangingHarness {
    let base: ConvexHarness
    let transport: HangingTransport
    let activity: ConvexActivityService

    init() async {
        base = await ConvexHarness()
        _ = try? await base.signIn()
        transport = HangingTransport(base: base.transport, hanging: ["notifications:registerDevice", "notifications:unregisterDevice"])
        activity = ConvexActivityService(connection: ConvexConnection(transport: transport, session: base.session))
    }

    func waitUntilHanging() async {
        while await transport.gate.waiting == 0 { await Task.yield() }
    }

    func release() async { await transport.gate.open() }
}

/// `FakeTransport`, except the `hanging` functions wait on `gate`, ignoring
/// cancellation, the way a stuck network call would.
private final class HangingTransport: ConvexTransport, @unchecked Sendable {
    let base: FakeTransport
    let hanging: Set<String>
    let gate = TestGate()

    init(base: FakeTransport, hanging: Set<String>) {
        self.base = base
        self.hanging = hanging
    }

    var calls: [FakeTransport.Call] { base.calls }

    func query<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        try await base.query(name, args: args)
    }

    func mutation<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        if hanging.contains(name) {
            await gate.wait()
            throw ConvexCallError.client("released")
        }
        return try await base.mutation(name, args: args)
    }

    func action<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        try await base.action(name, args: args)
    }

    func subscribe<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg], as type: T.Type) -> AsyncThrowingStream<T, any Error> {
        base.subscribe(name, args: args, as: type)
    }

    func authenticate() async throws { try await base.authenticate() }
    func clearAuthentication() async { await base.clearAuthentication() }
}

/// The activity functions' return shapes, as the Convex client hands them over.
private enum ActivityFixtures {
    static let walkStart = #"{"walkId":"walk_1","startedAt":1800000000000,"endsAt":1800007200000.0}"#

    static let statusPreset = #"{"preset":"at_work","text":null,"expiresAt":1800086400000}"#
    static let statusText = #"{"preset":null,"text":"Making momos","expiresAt":1800000500000}"#

    static let prefs = #"{"walkStarted":true,"goalHit":false,"reactions":true,"eveningNudge":true}"#

    static let feed = """
    [
     {"id":"evt_1","type":"walk_started","actor":{"userId":"user_1","name":"Sita","avatarColor":"#E07A5F"},
      "day":"2027-01-15","createdAt":1800000000000,"data":{"walkId":"walk_1"},
      "reactions":[{"emoji":"👏","count":2.0},{"emoji":"❤","count":1},{"emoji":"🦄","count":5}],"myReaction":"👏"},
     {"id":"evt_2","type":"member_5k","actor":{"userId":"user_2","name":null,"avatarColor":"#3D405B"},
      "day":"2027-01-15","createdAt":1799990000000,"reactions":[],"myReaction":null},
     {"id":"evt_3","type":"family_100","actor":null,"day":"2027-01-14","createdAt":1799900000000,"reactions":[],"myReaction":null},
     {"id":"evt_4","type":"family_streak_7","actor":null,"day":"2027-01-14","createdAt":1799890000000,"reactions":[],"myReaction":null}
    ]
    """
}
