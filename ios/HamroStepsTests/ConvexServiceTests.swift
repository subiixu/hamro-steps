import Foundation
import Testing
@testable import HamroSteps

/// Error codes, fixtures for every backend return shape, and the two services
/// over the fake transport.
struct ConvexErrorTests {
    @Test(arguments: [
        ("not_authenticated", FamilyServiceError.notAuthenticated),
        ("invalid_code", .invalidCode),
        ("family_full", .familyFull),
        ("not_member", .notMember),
        ("not_organiser", .notOrganiser),
        ("invalid_goal", .invalidGoal),
        ("invalid_name", .invalidName),
        ("invalid_steps", .invalidSteps),
        ("invalid_day", .invalidDay),
        ("cannot_remove_self", .cannotRemoveSelf),
        ("invalid_token", .invalidToken),
    ])
    func convexErrorDataDecodes(code: String, expected: FamilyServiceError) {
        let error = ConvexCallError(convexData: #"{"code":"\#(code)"}"#)
        #expect(error == .convex(code: code))
        #expect(FamilyServiceError(convex: error) == expected)
    }

    @Test func oddErrorDataStillMaps() {
        #expect(ConvexCallError(convexData: #""family_full""#) == .convex(code: "family_full"))
        #expect(ConvexCallError(convexData: #"{"message":"x"}"#) == .convex(code: nil))
        #expect(FamilyServiceError(convex: ConvexCallError.convex(code: nil)) == .unavailable("server"))
        #expect(FamilyServiceError(convex: ConvexCallError.convex(code: "new_code")) == .unavailable("new_code"))
        #expect(FamilyServiceError(convex: ConvexCallError.server("boom")) == .unavailable("server"))
    }

    @Test func sessionAndHTTPErrorsMap() {
        #expect(FamilyServiceError(convex: ConvexSessionError.signedOut) == .notAuthenticated)
        #expect(FamilyServiceError(convex: AuthEndpointError.invalidToken) == .invalidToken)
        #expect(FamilyServiceError(convex: AuthEndpointError.network("x")) == .unavailable("network"))
        #expect(FamilyServiceError(convex: AuthEndpointError.appleUnavailable) == .unavailable("apple_unavailable"))
        #expect(FamilyServiceError(convex: KeychainError(status: -25308)) == .unavailable("keychain"))
    }

    @Test func httpErrorBodiesMap() {
        func error(_ status: Int, _ body: String) -> AuthEndpointError {
            URLSessionAuthEndpoints.error(status: status, body: Data(body.utf8))
        }
        #expect(error(401, #"{"code":"invalid_token"}"#) == .invalidToken)
        #expect(error(400, #"{"code":"invalid_request"}"#) == .invalidRequest)
        #expect(error(503, #"{"code":"apple_unavailable"}"#) == .appleUnavailable)
        #expect(error(401, "") == .invalidToken)
        #expect(error(502, "<html>") == .server(502))
    }

    @Test func authFailuresAreRetryable() {
        #expect(ConvexCallError.convex(code: "invalid_token").isAuthFailure)
        #expect(ConvexCallError.convex(code: "not_authenticated").isAuthFailure)
        #expect(!ConvexCallError.convex(code: "not_member").isAuthFailure)
        #expect(!ConvexCallError.server("x").isAuthFailure)
    }
}

struct ConvexFixtureTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func me() throws {
        let user = try decode(AppUser.self, Fixtures.me(name: nil))
        #expect(user == AppUser(userId: "user_1", name: nil, needsName: true, timezone: "Asia/Kathmandu", lastSyncedAt: nil))
    }

    @Test func familyView() throws {
        let family = try decode(FamilySummary.self, Fixtures.familyView)
        #expect(family.dailyGoal == 50000)
        #expect(family.memberCount == 1)
        #expect(family.isOrganiser == nil)
        #expect(family.position == nil)
    }

    @Test func myFamilies() throws {
        let families = try decode([FamilySummary].self, Fixtures.myFamilies)
        #expect(families.map(\.familyId) == ["fam_1", "fam_2"])
        #expect(families[0].isOrganiser == true)
        #expect(families[1].position == 4)
        #expect(families[1].isFull)
    }

    @Test func previewInvite() throws {
        let preview = try decode(InvitePreview.self, Fixtures.previewInvite)
        #expect(preview == InvitePreview(familyId: "fam_1", name: "Sharma Family", memberCount: 3, isFull: false, alreadyMember: false))
    }

    @Test func syncSteps() throws {
        let result = try decode(SyncStepsResult.self, Fixtures.syncSteps)
        #expect(result == SyncStepsResult(lastSyncedAt: 1_800_000_123_456, today: "2027-01-15"))
    }

    @Test func familyToday() throws {
        let today = try decode(FamilyToday.self, Fixtures.familyToday())
        #expect(today.percent == 42)
        #expect(today.members[0].steps == 12000)
        #expect(today.members[1].name == "")
        #expect(today.members[1].steps == nil)
        #expect(today.family.familyId == "fam_1")
    }

    @Test func familyWeek() throws {
        let week = try decode(FamilyWeek.self, Fixtures.familyWeek)
        #expect(week.days.map(\.isBeforeFamily) == [true, false, false])
        #expect(week.days[1].hit)
        #expect(week.days[2].isFuture)
    }

    @Test func nullDecodes() throws {
        _ = try decode(ConvexNull.self, "null")
    }

    @Test func authResponses() throws {
        let apple = try decode(AppleSignInResponse.self, Fixtures.appleResponse)
        #expect(apple.tokens.refreshToken == "r1")
        #expect(apple.tokens.accessTokenExpiry == Date(timeIntervalSince1970: 1_800_000_900))
        #expect(apple.needsName)
        #expect(apple.name == nil)
        let refreshed = try decode(SessionTokens.self, Fixtures.refreshResponse)
        #expect(refreshed.refreshToken == "r2")
        #expect(refreshed.userId == "user_1")
    }

    @Test func appleRequestBody() throws {
        var name = PersonNameComponents()
        name.givenName = " Sita "
        let request = AppleSignInRequest(identityToken: "id", authorizationCode: "", fullName: name, timezone: "Asia/Kathmandu")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        #expect(json?["identityToken"] as? String == "id")
        #expect(json?["authorizationCode"] == nil)
        #expect((json?["fullName"] as? [String: Any])?["givenName"] as? String == "Sita")
        #expect(json?["timezone"] as? String == "Asia/Kathmandu")
        let noName = AppleSignInRequest(identityToken: "id", authorizationCode: "c", fullName: PersonNameComponents(), timezone: nil)
        #expect(noName.fullName == nil)
    }

    @Test func configIgnoresPlaceholders() {
        #expect(ConvexConfig(info: ["ConvexURL": "https://placeholder.convex.cloud", "ConvexSiteURL": "https://placeholder.convex.site"]) == nil)
        #expect(ConvexConfig(info: ["ConvexURL": "$(CONVEX_URL)", "ConvexSiteURL": "$(CONVEX_SITE_URL)"]) == nil)
        #expect(ConvexConfig(info: [:]) == nil)
        let config = ConvexConfig(info: ["ConvexURL": "https://happy-otter-1.convex.cloud", "ConvexSiteURL": "https://happy-otter-1.convex.site"])
        #expect(config?.siteURL.absoluteString == "https://happy-otter-1.convex.site")
    }
}

struct ConvexFamilyServiceTests {
    @Test func callsCarryTheRightNamesAndArgs() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("families:createFamily", json: Fixtures.familyView)
        h.transport.respond("steps:syncSteps", json: Fixtures.syncSteps)
        h.transport.respond("families:updateFamily", json: Fixtures.familyView)
        _ = try await h.family.createFamily(name: "Sharma Family", dailyGoal: 50000)
        try await h.family.syncSteps(days: [StepDay(day: "2027-01-15", steps: 1234)])
        _ = try await h.family.updateFamily(familyId: "fam_1", name: "S", dailyGoal: 1000)
        let calls = h.transport.calls.filter { $0.name != "users:me" }
        #expect(calls == [
            .init(kind: "mutation", name: "families:createFamily", args: ["name": .string("Sharma Family"), "dailyGoal": .number(50000)]),
            .init(kind: "mutation", name: "steps:syncSteps", args: ["days": .array([.object(["day": .string("2027-01-15"), "steps": .number(1234)])])]),
            .init(kind: "mutation", name: "families:updateFamily", args: ["familyId": .string("fam_1"), "name": .string("S"), "dailyGoal": .number(1000)]),
        ])
    }

    @Test func everyMethodDecodesItsFixture() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        let t = h.transport
        t.respond("families:previewInvite", json: Fixtures.previewInvite)
        t.respond("families:joinFamily", json: Fixtures.familyView)
        t.respond("families:regenerateInviteCode", json: Fixtures.inviteCode)
        t.respond("families:removeMember", json: "null")
        t.respond("families:leaveFamily", json: "null")
        t.respond("families:myFamilies", json: Fixtures.myFamilies)
        t.respond("home:familyToday", json: Fixtures.familyToday())
        t.respond("home:familyWeek", json: Fixtures.familyWeek)

        #expect(try await h.family.previewInvite(code: "K7P2QX").name == "Sharma Family")
        #expect(try await h.family.joinFamily(code: "K7P2QX").familyId == "fam_1")
        #expect(try await h.family.regenerateInviteCode(familyId: "fam_1") == "Z9Y8X7")
        try await h.family.removeMember(familyId: "fam_1", userId: "user_2")
        try await h.family.leaveFamily(familyId: "fam_1")
        #expect(try await h.family.myFamilies().count == 2)
        #expect(try await h.family.familyToday(familyId: "fam_1").total == 21000)
        #expect(try await h.family.familyWeek(familyId: "fam_1").weekStart == "2027-01-11")
        #expect(t.calls.first { $0.name == "families:removeMember" }?.args == ["familyId": .string("fam_1"), "userId": .string("user_2")])
    }

    @Test(arguments: ["revoked", "skipped", "queued"])
    func deleteMyAccountSucceeds(result: String) async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("users:deleteMyAccount", json: Fixtures.deleteMyAccount(result))
        try await h.family.deleteMyAccount()
        #expect(h.transport.calls.last?.kind == "action")
    }

    @Test func backendErrorCodesComeThrough() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.fail("families:joinFamily", ConvexCallError(convexData: #"{"code":"family_full"}"#))
        await #expect(throws: FamilyServiceError.familyFull) { try await h.family.joinFamily(code: "K7P2QX") }
    }

    @Test func invalidTokenRefreshesAndRetriesOnce() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.fail("families:myFamilies", .convex(code: "invalid_token"))
        h.transport.respond("families:myFamilies", json: Fixtures.myFamilies)
        #expect(try await h.family.myFamilies().count == 2)
        #expect(await h.endpoints.refreshes == ["refresh-1"])
        #expect(h.transport.authenticatedTokens.last == "access-2")
    }

    @Test func secondInvalidTokenGivesUp() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.fail("families:myFamilies", .convex(code: "invalid_token"))
        h.transport.fail("families:myFamilies", .convex(code: "invalid_token"))
        await #expect(throws: FamilyServiceError.invalidToken) { try await h.family.myFamilies() }
        #expect(await h.endpoints.refreshes.count == 1)
        // Not signed out: the session is still there.
        #expect(try await h.session.hasStoredSession())
    }

    @Test func revokedDuringRetryIsNotAuthenticated() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        await h.endpoints.setRefreshResults([.failure(.invalidToken)])
        h.transport.fail("families:myFamilies", .convex(code: "not_authenticated"))
        await #expect(throws: FamilyServiceError.notAuthenticated) { try await h.family.myFamilies() }
        #expect(h.keychain.keys.isEmpty)
    }

    @Test func nearExpiryRefreshesBeforeTheCall() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.clock.advance(14 * 60)
        h.transport.respond("families:myFamilies", json: "[]")
        _ = try await h.family.myFamilies()
        #expect(await h.endpoints.refreshes == ["refresh-1"])
        #expect(h.transport.authenticatedTokens.last == "access-2")
    }

    @Test func offlineIsUnavailableNotSignedOut() async throws {
        let clock = SessionClock()
        let keychain = InMemoryKeychain()
        try await ConvexHarness(clock: clock, keychain: keychain).signIn()
        let restarted = await ConvexHarness(clock: clock, keychain: keychain)
        await restarted.endpoints.setRefreshResults([.failure(.network("offline"))])
        await #expect(throws: FamilyServiceError.unavailable("network")) { try await restarted.family.myFamilies() }
        #expect(try await restarted.session.hasStoredSession())
    }

    @Test func signedOutCallsAreNotAuthenticated() async throws {
        let h = await ConvexHarness()
        await #expect(throws: FamilyServiceError.notAuthenticated) { try await h.family.myFamilies() }
        #expect(h.transport.calls.isEmpty)
    }

    @Test func familyTodayUpdatesStreamAndResubscribeAfterInvalidToken() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        var iterator = h.family.familyTodayUpdates(familyId: "fam_1").makeAsyncIterator()

        try await waitFor { h.transport.subscriptions("home:familyToday").count == 1 }
        h.transport.subscriptions("home:familyToday")[0].yield(Fixtures.familyToday(total: 100))
        #expect(await iterator.next()?.total == 100)

        h.transport.subscriptions("home:familyToday")[0].finish(throwing: ConvexCallError.convex(code: "invalid_token"))
        try await waitFor { h.transport.subscriptions("home:familyToday").count == 2 }
        #expect(await h.endpoints.refreshes == ["refresh-1"])
        h.transport.subscriptions("home:familyToday")[1].yield(Fixtures.familyToday(total: 200))
        #expect(await iterator.next()?.total == 200)
        #expect(h.transport.calls.last { $0.kind == "subscribe" }?.args == ["familyId": .string("fam_1")])

        h.transport.subscriptions("home:familyToday")[1].finish(throwing: ConvexCallError.convex(code: "not_member"))
        #expect(await iterator.next() == nil)
    }
}

struct ConvexAuthServiceTests {
    @Test func signInStoresTheSessionAndReturnsMe() async throws {
        let h = await ConvexHarness()
        var name = PersonNameComponents()
        name.givenName = "Sita"
        name.familyName = "Sharma"
        h.transport.respond("users:me", json: Fixtures.me(name: nil))
        let user = try await h.auth.signInWithApple(identityToken: "id-token", authorizationCode: "auth-code", fullName: name, timeZone: "Asia/Kathmandu")
        #expect(user.needsName)
        let request = try #require(await h.endpoints.signIns.first)
        #expect(request.authorizationCode == "auth-code")
        #expect(request.fullName == .init(givenName: "Sita", familyName: "Sharma"))
        #expect(request.timezone == "Asia/Kathmandu")
        #expect(h.transport.authenticatedTokens == ["access-1"])
        #expect(h.keychain.keys == [ConvexSession.sessionKey, ConvexSession.userKey])
        #expect(await h.auth.currentUser == user)
    }

    @Test func rejectedAppleTokenIsInvalidToken() async throws {
        let h = await ConvexHarness()
        await h.endpoints.setSignInError(.invalidToken)
        await #expect(throws: FamilyServiceError.invalidToken) {
            try await h.auth.signInWithApple(identityToken: "bad", authorizationCode: "c", fullName: nil, timeZone: "UTC")
        }
        #expect(h.keychain.keys.isEmpty)
    }

    @Test func transientMeFailureAfterSignInKeepsTheSessionAndARetrySucceeds() async throws {
        let h = await ConvexHarness()
        h.transport.fail("users:me", .server("boom"))
        await #expect(throws: FamilyServiceError.unavailable("server")) {
            try await h.auth.signInWithApple(identityToken: "id", authorizationCode: "c", fullName: nil, timeZone: "UTC")
        }
        // The session stays: nothing logged out, the tokens still stored.
        #expect(await h.endpoints.logouts.isEmpty)
        #expect(try await h.session.hasStoredSession())
        #expect(h.keychain.keys.contains(ConvexSession.sessionKey))

        // The retry fetches the person on the same session.
        h.transport.respond("users:me", json: Fixtures.me(name: "Sita"))
        let user = try #require(await h.auth.currentUser)
        #expect(user.userId == "user_1")
        #expect(await h.endpoints.signIns.count == 1)
        #expect(await h.endpoints.refreshes.isEmpty)
        #expect(await h.session.cachedUser() == user)
    }

    @Test func revokedSessionOnMeAfterSignInLeavesNoSession() async throws {
        let h = await ConvexHarness()
        // The backend rejects the new token and the refresh is refused too.
        h.transport.fail("users:me", .convex(code: "invalid_token"))
        await h.endpoints.setRefreshResults([.failure(.invalidToken)])
        await #expect(throws: FamilyServiceError.notAuthenticated) {
            try await h.auth.signInWithApple(identityToken: "id", authorizationCode: "c", fullName: nil, timeZone: "UTC")
        }
        #expect(h.keychain.keys.isEmpty)
        #expect(try await h.session.hasStoredSession() == false)
    }

    @Test func restartOpensSignedInWithoutWaitingForTheNetwork() async throws {
        let clock = SessionClock()
        let keychain = InMemoryKeychain()
        let user = try await ConvexHarness(clock: clock, keychain: keychain).signIn()

        let restarted = await ConvexHarness(clock: clock, keychain: keychain)
        await restarted.endpoints.setRefreshResults([.failure(.network("offline"))])
        #expect(await restarted.auth.currentUser == user)
        await restarted.auth.userRefresh?.value
        #expect(try await restarted.session.hasStoredSession())
    }

    @Test func restartRefreshesThePersonBehindTheScenes() async throws {
        let clock = SessionClock()
        let keychain = InMemoryKeychain()
        try await ConvexHarness(clock: clock, keychain: keychain).signIn(name: nil)

        let restarted = await ConvexHarness(clock: clock, keychain: keychain)
        restarted.transport.respond("users:me", json: Fixtures.me(name: "Sita"))
        #expect(await restarted.auth.currentUser?.needsName == true)
        await restarted.auth.userRefresh?.value
        #expect(await restarted.session.cachedUser()?.name == "Sita")
        #expect(restarted.transport.authenticatedTokens == ["access-1"])
    }

    @Test func noSessionIsSignedOut() async throws {
        let h = await ConvexHarness()
        #expect(await h.auth.currentUser == nil)
        #expect(h.transport.calls.isEmpty)
    }

    @Test func updateNameSavesThenReadsMe() async throws {
        let h = await ConvexHarness()
        try await h.signIn(name: nil)
        h.transport.respond("users:updateProfile", json: "null")
        h.transport.respond("users:me", json: Fixtures.me(name: "Sita"))
        let user = try await h.auth.updateName("Sita")
        #expect(user.name == "Sita")
        #expect(!user.needsName)
        #expect(h.transport.calls.contains(.init(kind: "mutation", name: "users:updateProfile", args: ["name": .string("Sita")])))
    }

    @Test func signOutLogsOutAndClears() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        await h.auth.signOut()
        #expect(await h.endpoints.logouts == ["refresh-1"])
        #expect(h.keychain.keys.isEmpty)
        #expect(h.transport.cleared == 1)
        #expect(await h.auth.currentUser == nil)
    }

    @Test func deleteAccountForgetsLocally() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        try await h.auth.deleteAccount()
        #expect(await h.endpoints.logouts.isEmpty)
        #expect(h.keychain.keys.isEmpty)
        #expect(h.transport.cleared == 1)
    }
}
