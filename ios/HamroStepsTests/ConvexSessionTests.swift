import Foundation
import Security
import Testing
@testable import HamroSteps

/// The session: Keychain persistence, refresh timing, coalescing, revocation.
struct ConvexSessionTests {
    private func signedIn(_ h: ConvexHarness) async throws {
        _ = try await h.session.signInWithApple(AppleSignInRequest(identityToken: "id", authorizationCode: "code", fullName: nil, timezone: nil))
    }

    // MARK: Timing

    @Test func refreshIsScheduledTwoMinutesBeforeExpiry() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(ConvexSession.refreshDelay(expiry: now + 15 * 60, now: now) == 13 * 60)
        #expect(ConvexSession.refreshDelay(expiry: now + 120, now: now) == 0)
        #expect(ConvexSession.refreshDelay(expiry: now - 60, now: now) == 0)
    }

    @Test func accessTokenIsReusedUntilTwoMinutesBeforeExpiry() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        // 15-minute token: fine at 12:59 elapsed (2:01 left).
        h.clock.advance(12 * 60 + 59)
        #expect(try await h.session.validAccessToken() == "access-1")
        #expect(await h.endpoints.refreshes.isEmpty)
        // At 13:00 elapsed (2:00 left) it refreshes.
        h.clock.advance(1)
        #expect(await h.session.needsRefresh)
        #expect(try await h.session.validAccessToken() == "access-2")
        #expect(await h.endpoints.refreshes == ["refresh-1"])
    }

    @Test func timerRefreshesAndPushesTheNewToken() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        try await waitFor { await h.sleeper.pending == 1 }
        #expect(await h.sleeper.requested == [.seconds(13 * 60)])

        h.clock.advance(13 * 60)
        await h.sleeper.releaseNext()
        try await waitFor { h.tokenLog.tokens == ["access-2"] }
        #expect(await h.endpoints.refreshes == ["refresh-1"])
        // And the next one is scheduled from the new token.
        try await waitFor { await h.sleeper.requested.count == 2 }
        #expect(await h.sleeper.requested.last == .seconds(13 * 60))
    }

    @Test func timerRetriesLaterWhenOffline() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.endpoints.setRefreshResults([.failure(.network("offline"))])
        try await waitFor { await h.sleeper.pending == 1 }
        await h.sleeper.releaseNext()
        try await waitFor { await h.sleeper.requested.count == 2 }
        #expect(await h.sleeper.requested.last == .seconds(30))
        #expect(try await h.session.hasStoredSession())
        #expect(h.tokenLog.tokens.isEmpty)
    }

    // MARK: Keychain

    @Test func onlyTheRefreshTokenIsStored() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        let stored = try #require(h.keychain.raw(ConvexSession.sessionKey))
        #expect(stored.contains("refresh-1"))
        #expect(!stored.contains("access-1"))
    }

    @Test func sessionSurvivesARestart() async throws {
        let clock = SessionClock()
        let keychain = InMemoryKeychain()
        let first = await ConvexHarness(clock: clock, keychain: keychain)
        try await signedIn(first)

        // New process: no access token in memory, the Keychain still has the session.
        let second = await ConvexHarness(clock: clock, keychain: keychain)
        _ = await second.endpoints.tokens() // its next pair is number 2
        #expect(try await second.session.hasStoredSession())
        #expect(await second.session.needsRefresh)
        #expect(try await second.session.validAccessToken() == "access-2")
        #expect(await second.endpoints.refreshes == ["refresh-1"])
        // The rotated refresh token replaced the old one.
        let stored = try #require(keychain.raw(ConvexSession.sessionKey))
        #expect(stored.contains("refresh-2"))
        #expect(!stored.contains("refresh-1"))
        #expect(await second.session.userId == "user_1")
    }

    @Test func lockedKeychainIsNotSignedOut() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        let restarted = await ConvexHarness(clock: h.clock, keychain: h.keychain)
        h.keychain.failure = KeychainError(status: errSecInteractionNotAllowed)
        await #expect(throws: KeychainError.self) { try await restarted.session.hasStoredSession() }
        await #expect(throws: KeychainError.self) { try await restarted.session.validAccessToken() }
    }

    // MARK: Refresh

    @Test func concurrentRefreshesShareOneCall() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        h.clock.advance(14 * 60) // all three callers need a new token
        await h.endpoints.closeGate()
        async let a = h.session.refresh()
        async let b = h.session.refresh()
        async let c = h.session.validAccessToken()
        try await waitFor { await h.endpoints.refreshes.count == 1 }
        await h.endpoints.openGate()
        let tokens = try await [a, b, c]
        #expect(tokens == ["access-2", "access-2", "access-2"])
        #expect(await h.endpoints.refreshes == ["refresh-1"])
    }

    @Test func revokedSessionSignsOut() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.endpoints.setRefreshResults([.failure(.invalidToken)])
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.refresh() }
        #expect(try await !h.session.hasStoredSession())
        #expect(h.keychain.keys.isEmpty)
        #expect(h.tokenLog.tokens == [nil])
    }

    @Test func offlineRefreshKeepsTheSession() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.endpoints.setRefreshResults([.failure(.network("offline")), .failure(.server(500))])
        await #expect(throws: AuthEndpointError.network("offline")) { try await h.session.refresh() }
        await #expect(throws: AuthEndpointError.server(500)) { try await h.session.refresh() }
        #expect(try await h.session.hasStoredSession())
        #expect(h.tokenLog.tokens.isEmpty)
        #expect(try await h.session.refresh() == "access-2")
    }

    @Test func noSessionMeansSignedOut() async throws {
        let h = await ConvexHarness()
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.validAccessToken() }
        #expect(await h.endpoints.refreshes.isEmpty)
    }

    // MARK: Sign out

    @Test func signOutCallsLogoutThenClearsTheKeychain() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.session.cacheUser(AppUser(userId: "user_1", name: "Sita", needsName: false))
        await h.session.signOut()
        #expect(await h.endpoints.logouts == ["refresh-1"])
        #expect(h.keychain.keys.isEmpty)
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.validAccessToken() }
    }

    @Test func signOutWorksOffline() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.endpoints.setLogoutError(.network("offline"))
        await h.session.signOut()
        #expect(h.keychain.keys.isEmpty)
    }

    @Test func forgetDoesNotCallTheBackend() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.session.forget()
        #expect(await h.endpoints.logouts.isEmpty)
        #expect(h.keychain.keys.isEmpty)
    }

    @Test func refreshFinishingAfterSignOutIsDropped() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.endpoints.closeGate()
        let refresh = Task { try await h.session.refresh() }
        try await waitFor { await h.endpoints.refreshes.count == 1 }
        await h.session.forget()
        await h.endpoints.openGate()
        await #expect(throws: ConvexSessionError.signedOut) { try await refresh.value }
        #expect(h.keychain.keys.isEmpty)
        // The token pair the backend rotated to is logged out too.
        try await waitFor { await h.endpoints.logouts == ["refresh-2"] }
    }

    // MARK: Sign out racing a refresh

    @Test func nothingRefreshesWhileLogoutIsInFlight() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.endpoints.closeLogoutGate()
        let signOut = Task { await h.session.signOut() }
        try await waitFor { await h.endpoints.logouts == ["refresh-1"] }

        // The Keychain still holds the session, but a background call can't
        // load it or refresh with it.
        #expect(h.keychain.keys.contains(ConvexSession.sessionKey))
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.refresh() }
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.validAccessToken() }
        #expect(try await h.session.hasStoredSession() == false)
        #expect(await h.endpoints.refreshes.isEmpty)

        await h.endpoints.openLogoutGate()
        await signOut.value
        #expect(h.keychain.keys.isEmpty)
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.validAccessToken() }
        #expect(await h.endpoints.refreshes.isEmpty)
    }

    @Test func refreshInFlightWhenSignOutStartsIsDropped() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.endpoints.closeGate()
        await h.endpoints.closeLogoutGate()
        let refresh = Task { try await h.session.refresh() }
        try await waitFor { await h.endpoints.refreshes.count == 1 }
        let signOut = Task { await h.session.signOut() }
        try await waitFor { await h.endpoints.logouts.count == 1 }

        // The refresh lands mid-logout: it must not bring the session back.
        await h.endpoints.openGate()
        await #expect(throws: ConvexSessionError.signedOut) { try await refresh.value }
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.validAccessToken() }

        await h.endpoints.openLogoutGate()
        await signOut.value
        #expect(h.keychain.keys.isEmpty)
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.validAccessToken() }
        try await waitFor { await Set(h.endpoints.logouts) == ["refresh-1", "refresh-2"] }
        #expect(await h.endpoints.refreshes == ["refresh-1"])
    }

    @Test func signInDuringLogoutKeepsTheNewSession() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        await h.endpoints.closeLogoutGate()
        let signOut = Task { await h.session.signOut() }
        try await waitFor { await h.endpoints.logouts.count == 1 }
        try await signedIn(h)
        await h.endpoints.openLogoutGate()
        await signOut.value
        #expect(try #require(h.keychain.raw(ConvexSession.sessionKey)).contains("refresh-2"))
        #expect(try await h.session.validAccessToken() == "access-2")
    }

    // MARK: Failed Keychain write of a rotated token

    @Test func failedWriteOfRotatedTokenIsRetriedAndSurvivesARestart() async throws {
        let clock = SessionClock()
        let keychain = InMemoryKeychain()
        let endpoints = FakeAuthEndpoints(clock: clock)
        let sleeper = TestSleeper()
        let writeSleeper = TestSleeper()
        let session = ConvexSession(
            endpoints: endpoints, keychain: keychain, marker: InMemorySignOutMarker(), now: { clock.now },
            sleep: { try await sleeper.sleep($0) },
            writeRetrySleep: { try await writeSleeper.sleep($0) }
        )
        _ = try await session.signInWithApple(AppleSignInRequest(identityToken: "id", authorizationCode: "code", fullName: nil, timezone: nil))

        // The backend rotates refresh-1 to refresh-2, but the Keychain write fails.
        keychain.failure = KeychainError(status: errSecInteractionNotAllowed)
        #expect(try await session.refresh() == "access-2")
        #expect(await session.hasPendingWrite)

        // Still failing on the first retry: back off and try again.
        try await waitFor { await writeSleeper.pending == 1 }
        await writeSleeper.releaseNext()
        try await waitFor { await writeSleeper.requested.count == 2 }
        #expect(await writeSleeper.requested == [.seconds(1), .seconds(2)])
        #expect(await session.hasPendingWrite)

        // The Keychain recovers: the next retry lands the rotated token.
        keychain.failure = nil
        #expect(try #require(keychain.raw(ConvexSession.sessionKey)).contains("refresh-1"))
        await writeSleeper.releaseNext()
        try await waitFor { await !session.hasPendingWrite }
        #expect(try #require(keychain.raw(ConvexSession.sessionKey)).contains("refresh-2"))

        // A restart presents the live token, not the consumed one.
        let restarted = await ConvexHarness(clock: clock, keychain: keychain)
        _ = try await restarted.session.validAccessToken()
        #expect(await restarted.endpoints.refreshes == ["refresh-2"])
    }

    @Test func pendingWriteLandsOnTheNextCall() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        h.keychain.failure = KeychainError(status: errSecInteractionNotAllowed)
        _ = try await h.session.refresh()
        #expect(await h.session.hasPendingWrite)
        h.keychain.failure = nil
        #expect(try await h.session.validAccessToken() == "access-2")
        #expect(await !h.session.hasPendingWrite)
        #expect(try #require(h.keychain.raw(ConvexSession.sessionKey)).contains("refresh-2"))
    }

    @Test func signOutDropsAPendingWrite() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        h.keychain.failure = KeychainError(status: errSecInteractionNotAllowed)
        _ = try await h.session.refresh()
        h.keychain.failure = nil
        await h.session.forget()
        #expect(await !h.session.hasPendingWrite)
        #expect(h.keychain.keys.isEmpty)
    }

    // MARK: Redo 2: a queued refresh after the session changed

    /// A session whose refresh tasks wait at `gate` before they start.
    private func gatedSession(_ gate: TestGate) -> (ConvexSession, FakeAuthEndpoints, InMemoryKeychain) {
        let clock = SessionClock()
        let keychain = InMemoryKeychain()
        let endpoints = FakeAuthEndpoints(clock: clock)
        let sleeper = TestSleeper()
        let session = ConvexSession(
            endpoints: endpoints, keychain: keychain, marker: InMemorySignOutMarker(), now: { clock.now },
            sleep: { try await sleeper.sleep($0) },
            refreshWillStart: { await gate.wait() }
        )
        return (session, endpoints, keychain)
    }

    private let appleRequest = AppleSignInRequest(identityToken: "id", authorizationCode: "code", fullName: nil, timezone: nil)

    @Test func queuedRefreshStartingAfterASignInLeavesTheNewSessionAlone() async throws {
        let gate = TestGate()
        let (session, endpoints, keychain) = gatedSession(gate)
        _ = try await session.signInWithApple(appleRequest)

        // The refresh is queued for the first session but hasn't started...
        let refresh = Task { try await session.refresh() }
        try await waitFor { await gate.waiting == 1 }
        // ...when a second sign-in replaces that session.
        _ = try await session.signInWithApple(appleRequest)
        await gate.open()

        // The queued task never touches refresh-2 on behalf of the old
        // session: the refresh runs once, for the new session, and nothing
        // is logged out.
        #expect(try await refresh.value == "access-3")
        #expect(await endpoints.refreshes == ["refresh-2"])
        #expect(await endpoints.logouts.isEmpty)
        #expect(try await session.validAccessToken() == "access-3")
        #expect(try #require(keychain.raw(ConvexSession.sessionKey)).contains("refresh-3"))
    }

    @Test func queuedRefreshStartingAfterASignOutNeverCallsTheBackend() async throws {
        let gate = TestGate()
        let (session, endpoints, keychain) = gatedSession(gate)
        _ = try await session.signInWithApple(appleRequest)

        let refresh = Task { try await session.refresh() }
        try await waitFor { await gate.waiting == 1 }
        await session.signOut()
        await gate.open()

        await #expect(throws: ConvexSessionError.signedOut) { try await refresh.value }
        #expect(await endpoints.refreshes.isEmpty)
        #expect(await endpoints.logouts == ["refresh-1"])
        #expect(keychain.keys.isEmpty)
    }

    // MARK: Redo 2: the Keychain won't delete the session

    @Test func failedRemovalWithOfflineLogoutStaysSignedOutThroughRestartsAndRecovers() async throws {
        let h = await ConvexHarness()
        let user = try await h.signIn()
        #expect(await h.session.cachedUser() == user)

        // Offline, and the Keychain refuses the delete.
        await h.endpoints.setLogoutError(.network("offline"))
        h.keychain.removeFailure = KeychainError(status: errSecInteractionNotAllowed)
        await h.auth.signOut()

        // The session is still on disk, and its refresh token is still live
        // on the backend, but nothing may use it.
        #expect(h.keychain.keys.contains(ConvexSession.sessionKey))
        #expect(h.marker.isSet)
        #expect(try await h.session.hasStoredSession() == false)
        #expect(await h.session.userId == nil)
        #expect(await h.session.cachedUser() == nil)
        #expect(await h.auth.currentUser == nil)
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.validAccessToken() }
        await #expect(throws: ConvexSessionError.signedOut) { try await h.session.refresh() }
        await #expect(throws: FamilyServiceError.notAuthenticated) { try await h.family.myFamilies() }

        // A restart while the Keychain still refuses: still signed out.
        let restarted = await ConvexHarness(clock: h.clock, keychain: h.keychain, marker: h.marker)
        #expect(try await restarted.session.hasStoredSession() == false)
        #expect(await restarted.auth.currentUser == nil)
        #expect(await restarted.session.cachedUser() == nil)
        await #expect(throws: ConvexSessionError.signedOut) { try await restarted.session.validAccessToken() }
        #expect(await h.endpoints.refreshes.isEmpty)
        #expect(await restarted.endpoints.refreshes.isEmpty)

        // The removal is retried with backoff.
        try await waitFor { await h.storageSleeper.pending == 1 }
        await h.storageSleeper.releaseNext()
        try await waitFor { await h.storageSleeper.requested.count == 2 }
        #expect(await h.storageSleeper.requested == [.seconds(1), .seconds(2)])
        #expect(h.keychain.keys.contains(ConvexSession.sessionKey))

        // The Keychain recovers: the next retry clears it and the marker.
        h.keychain.removeFailure = nil
        await h.storageSleeper.releaseNext()
        try await waitFor { h.keychain.keys.isEmpty }
        #expect(!h.marker.isSet)

        // And a restart after that is plainly signed out.
        let again = await ConvexHarness(clock: h.clock, keychain: h.keychain, marker: h.marker)
        #expect(try await again.session.hasStoredSession() == false)
        #expect(await again.auth.currentUser == nil)
    }

    @Test func restartMidLogoutDoesNotRestoreTheSession() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        await h.endpoints.closeLogoutGate()
        let signOut = Task { await h.session.signOut() }
        try await waitFor { await h.endpoints.logouts.count == 1 }

        // The app is killed here: the Keychain still holds everything.
        let restarted = await ConvexHarness(clock: h.clock, keychain: h.keychain, marker: h.marker)
        #expect(try await restarted.session.hasStoredSession() == false)
        #expect(await restarted.auth.currentUser == nil)
        #expect(h.keychain.keys.isEmpty)
        await h.endpoints.openLogoutGate()
        await signOut.value
    }

    @Test func signInAfterAFailedRemovalTakesOverTheKeychain() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.keychain.removeFailure = KeychainError(status: errSecInteractionNotAllowed)
        await h.session.forget()
        #expect(h.marker.isSet)
        try await waitFor { await h.storageSleeper.pending == 1 }
        #expect(try await h.session.hasStoredSession() == false)

        // Deletes still fail, but writes work: the new session overwrites
        // the old one and the marker clears.
        try await signedIn(h)
        #expect(!h.marker.isSet)
        #expect(try await h.session.hasStoredSession())
        #expect(try #require(h.keychain.raw(ConvexSession.sessionKey)).contains("refresh-2"))

        // The cancelled removal retry wakes up and leaves the new session be.
        await h.storageSleeper.releaseNext()
        try await Task.sleep(for: .milliseconds(50))
        #expect(try #require(h.keychain.raw(ConvexSession.sessionKey)).contains("refresh-2"))

        // A restart picks up the new session.
        let restarted = await ConvexHarness(clock: h.clock, keychain: h.keychain, marker: h.marker)
        _ = try await restarted.session.validAccessToken()
        #expect(await restarted.endpoints.refreshes == ["refresh-2"])
    }

    // MARK: SDK re-authentication

    @Test func providerLoginInstallsTheCurrentToken() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        let provider = ConvexSessionAuthProvider(session: h.session)
        #expect(try await provider.login(onIdToken: { _ in }) == "access-1")
        #expect(await h.endpoints.refreshes.isEmpty)
    }

    @Test func providerLoginFromCacheRefreshesARejectedUnexpiredToken() async throws {
        let h = await ConvexHarness()
        try await signedIn(h)
        let pushed = TokenLog()
        let provider = ConvexSessionAuthProvider(session: h.session)
        // The token has 14+ minutes left, but the server rejected it.
        h.clock.advance(30)
        #expect(await !h.session.needsRefresh)
        #expect(try await provider.loginFromCache(onIdToken: { pushed.record($0) }) == "access-2")
        #expect(await h.endpoints.refreshes == ["refresh-1"])
        #expect(pushed.tokens == ["access-2"])

        // Rejected again moments later: no refresh loop, the new token comes back.
        h.clock.advance(1)
        #expect(try await provider.loginFromCache(onIdToken: { _ in }) == "access-2")
        #expect(await h.endpoints.refreshes == ["refresh-1"])

        // Past the grace period, a rejection refreshes again.
        h.clock.advance(ConvexSession.rejectedTokenGrace)
        #expect(try await provider.loginFromCache(onIdToken: { _ in }) == "access-3")
    }
}

/// Polls `condition` (yielding between tries) for up to about 2 seconds.
func waitFor(_ condition: @Sendable () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<400 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}
