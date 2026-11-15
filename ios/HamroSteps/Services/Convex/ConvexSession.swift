import Foundation

enum ConvexSessionError: Error, Hashable, Sendable {
    /// No session on this phone, or the backend revoked it (or it expired).
    /// The only case that signs the person out.
    case signedOut
}

/// A refresh that found the session replaced (signed out, or signed in
/// again) under it. `refresh()` starts over against the current session.
private enum RefreshSuperseded: Error {
    case superseded
}

/// The signed-in session: the refresh token lives in the Keychain (so the
/// session survives restarts and background launches), the access token only
/// in memory.
///
/// The access token is refreshed 2 minutes before it expires, on a timer and
/// on demand, and again whenever the backend says `invalid_token`. Refreshes
/// are coalesced: the backend rotates the refresh token on every use, so two
/// refreshes racing with the same token would kill the session.
actor ConvexSession {
    /// Refresh this long before the access token expires.
    static let refreshMargin: TimeInterval = 120
    /// After a refresh fails for a reason other than revocation (offline),
    /// the timer tries again this much later.
    static let retryDelay: TimeInterval = 30
    /// A token the SDK reports as rejected this soon after it was issued is
    /// handed back rather than refreshed again, so a backend that keeps
    /// rejecting can't drive a refresh loop.
    static let rejectedTokenGrace: TimeInterval = 10
    /// Backoff for retrying a Keychain write that failed: 1 s, doubling, up
    /// to this.
    static let maxWriteRetryDelay: TimeInterval = 30

    static let sessionKey = "session"
    static let userKey = "user"

    /// What the Keychain keeps under `sessionKey`.
    struct Stored: Codable, Hashable, Sendable {
        var refreshToken: String
        /// Epoch milliseconds.
        var refreshTokenExpiresAt: Double
        var userId: String
    }

    typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias TokenListener = @Sendable (String?) -> Void

    private let endpoints: any AuthEndpoints
    private let keychain: any KeychainStoring
    private let marker: any SignOutMarkerStoring
    private let now: @Sendable () -> Date
    private let sleep: Sleep
    private let writeRetrySleep: Sleep
    /// Test seam: awaited by each refresh task before it does anything, so a
    /// test can hold a queued refresh while the session changes.
    private let refreshWillStart: (@Sendable () async -> Void)?

    /// Cached copy of the Keychain item, once read.
    private var stored: Stored?
    private var accessToken: String?
    private var accessTokenExpiry: Date?
    /// When the current access token was issued.
    private var accessTokenIssuedAt: Date?
    private var refreshTask: Task<String, any Error>?
    private var timer: Task<Void, Never>?
    /// Told about every new access token, and `nil` when the session ends.
    private var listener: TokenListener?
    /// Bumped whenever the session starts or ends, so a refresh that finishes
    /// after a sign-out can't bring the old session back.
    private var generation = 0
    /// Set while `signOut` waits for `/auth/logout`. The Keychain still holds
    /// the session then, so nothing may load it or refresh with it.
    private var signingOut = false
    /// A session the Keychain hasn't taken yet (the write failed). The
    /// backend has already consumed the refresh token on disk, so until this
    /// lands a restart would present a dead token: keep retrying.
    private var pendingWrite: Stored?
    private var writeRetry: Task<Void, Never>?
    /// Retries removing a signed-out session from the Keychain while
    /// `marker` is set.
    private var clearRetry: Task<Void, Never>?

    init(
        endpoints: any AuthEndpoints,
        keychain: any KeychainStoring,
        marker: any SignOutMarkerStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        writeRetrySleep: Sleep? = nil,
        refreshWillStart: (@Sendable () async -> Void)? = nil
    ) {
        self.endpoints = endpoints
        self.keychain = keychain
        self.marker = marker
        self.now = now
        self.sleep = sleep
        self.writeRetrySleep = writeRetrySleep ?? sleep
        self.refreshWillStart = refreshWillStart
    }

    // MARK: State

    /// Whether this phone holds a session. Throws when the Keychain can't be
    /// read (locked), which is not the same as "no".
    func hasStoredSession() throws -> Bool {
        try loadStored() != nil
    }

    var userId: String? { (try? loadStored())?.userId }

    /// Changes on every sign-in, sign-out and forget. Work that spans several
    /// calls compares it before and after to know it's still the same session.
    var currentGeneration: Int { generation }

    /// True when the next call should refresh first: no access token in
    /// memory yet (a fresh launch), or within `refreshMargin` of expiry.
    var needsRefresh: Bool {
        guard accessToken != nil, let accessTokenExpiry else { return true }
        return accessTokenExpiry.timeIntervalSince(now()) <= Self.refreshMargin
    }

    func setListener(_ listener: @escaping TokenListener) {
        self.listener = listener
    }

    /// How long to wait before refreshing a token that expires at `expiry`.
    static func refreshDelay(expiry: Date, now: Date) -> TimeInterval {
        max(0, expiry.timeIntervalSince(now) - refreshMargin)
    }

    // MARK: Sign in and out

    /// `POST /auth/apple`, then keeps the new session.
    ///
    /// If an earlier sign-out still hasn't managed to clear the Keychain,
    /// the new session's write overwrites it; the sign-out marker stays set
    /// until that write lands.
    func signInWithApple(_ request: AppleSignInRequest) async throws -> AppleSignInResponse {
        let response = try await endpoints.signInWithApple(request)
        endSession()
        signingOut = false
        clearRetry?.cancel()
        clearRetry = nil
        keep(response.tokens)
        return response
    }

    /// `POST /auth/logout` (best effort: offline still signs out), then
    /// clears the Keychain. While the logout is in flight the session counts
    /// as gone: no refresh can start, and nothing reloads it from the
    /// Keychain.
    ///
    /// The sign-out marker is set first, so neither a restart mid-logout nor
    /// a Keychain that refuses the removal can bring the session (or the
    /// cached person) back. The removal is retried until it lands.
    func signOut() async {
        let token = (try? loadStored())?.refreshToken
        endSession()
        signingOut = true
        marker.set(true)
        let started = generation
        if let token {
            try? await endpoints.logout(refreshToken: token)
        }
        // A sign-in during the logout owns the session (and the Keychain) now.
        guard generation == started else { return }
        endSession()
        signingOut = false
        clearSignedOutStorage()
    }

    /// Clears the session without calling the backend: after the account was
    /// deleted there, its sessions are already gone.
    func forget() {
        endSession()
        invalidateStorage()
    }

    // MARK: Tokens

    /// A current access token, refreshing first when it's missing or within
    /// 2 minutes of expiry.
    func validAccessToken() async throws -> String {
        flushPendingWrite()
        if !needsRefresh, let accessToken { return accessToken }
        return try await refresh()
    }

    /// The Convex client says the server rejected its token (that is when the
    /// SDK calls `AuthProvider.loginFromCache`): get a new one however long
    /// the old one has left, unless it was issued moments ago.
    func refreshRejectedToken() async throws -> String {
        if let accessToken, let accessTokenIssuedAt,
           now().timeIntervalSince(accessTokenIssuedAt) < Self.rejectedTokenGrace {
            return accessToken
        }
        return try await refresh()
    }

    /// Refreshes now (or joins the refresh already running). Throws
    /// `ConvexSessionError.signedOut` when the backend revoked the session.
    @discardableResult
    func refresh() async throws -> String {
        while true {
            do {
                return try await joinOrStartRefresh()
            } catch RefreshSuperseded.superseded {
                // The session changed under that refresh: go again against
                // the one there is now (or find there is none).
                continue
            }
        }
    }

    private func joinOrStartRefresh() async throws -> String {
        if signingOut { throw ConvexSessionError.signedOut }
        if let refreshTask { return try await refreshTask.value }
        let started = generation
        let willStart = refreshWillStart
        let task = Task {
            await willStart?()
            return try await self.performRefresh(generation: started)
        }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value
    }

    private func performRefresh(generation started: Int) async throws -> String {
        // This task may start after a sign-in or sign-out replaced the
        // session it was queued for. Never touch the newer session's refresh
        // token from here: the backend rotates it on use.
        guard generation == started else { throw RefreshSuperseded.superseded }
        flushPendingWrite()
        guard let current = try loadStored() else { throw ConvexSessionError.signedOut }
        do {
            let tokens = try await endpoints.refresh(refreshToken: current.refreshToken)
            guard generation == started else {
                // Signed out (or in again) while this was in flight: end the
                // old session the backend just rotated too.
                let endpoints = endpoints
                Task { try? await endpoints.logout(refreshToken: tokens.refreshToken) }
                throw RefreshSuperseded.superseded
            }
            keep(tokens)
            listener?(tokens.accessToken)
            return tokens.accessToken
        } catch AuthEndpointError.invalidToken {
            guard generation == started else { throw RefreshSuperseded.superseded }
            endSession()
            invalidateStorage()
            listener?(nil)
            throw ConvexSessionError.signedOut
        }
    }

    private func keep(_ tokens: SessionTokens) {
        let next = Stored(refreshToken: tokens.refreshToken, refreshTokenExpiresAt: tokens.refreshTokenExpiresAt, userId: tokens.userId)
        stored = next
        accessToken = tokens.accessToken
        accessTokenExpiry = tokens.accessTokenExpiry
        accessTokenIssuedAt = now()
        // If the write fails, the in-memory copy works for this run and the
        // write is retried until it lands.
        pendingWrite = next
        flushPendingWrite()
        schedule(after: Self.refreshDelay(expiry: tokens.accessTokenExpiry, now: now()))
    }

    private func schedule(after delay: TimeInterval) {
        timer?.cancel()
        let generation = generation
        let sleep = sleep
        timer = Task { [weak self] in
            do { try await sleep(.milliseconds(Int64((delay * 1000).rounded()))) } catch { return }
            await self?.timerFired(generation: generation)
        }
    }

    private func timerFired(generation fired: Int) async {
        guard generation == fired, !Task.isCancelled else { return }
        do {
            try await refresh()
        } catch ConvexSessionError.signedOut {
            // Revoked: the listener already heard.
        } catch {
            // Offline or server trouble: keep the session, try again soon.
            if generation == fired { schedule(after: Self.retryDelay) }
        }
    }

    // MARK: Storage

    /// Whether a session is waiting to be written to the Keychain.
    var hasPendingWrite: Bool { pendingWrite != nil }

    /// Writes the pending session to the Keychain, if there is one. On
    /// failure (Keychain locked or otherwise unavailable) keeps it pending
    /// and makes sure a retry is scheduled.
    func flushPendingWrite() {
        guard let pending = pendingWrite else { return }
        do {
            try keychain.set(try JSONEncoder().encode(pending), for: Self.sessionKey)
            writeLanded()
            writeRetry?.cancel()
            writeRetry = nil
        } catch {
            scheduleWriteRetry()
        }
    }

    private func scheduleWriteRetry() {
        guard writeRetry == nil else { return }
        let generation = generation
        let sleep = writeRetrySleep
        writeRetry = Task { [weak self] in
            var delay: TimeInterval = 1
            while true {
                do { try await sleep(.milliseconds(Int64((delay * 1000).rounded()))) } catch { return }
                guard let self, await self.retryWrite(generation: generation) else { return }
                delay = min(delay * 2, ConvexSession.maxWriteRetryDelay)
            }
        }
    }

    /// One retry from the backoff loop. Returns whether to keep retrying.
    private func retryWrite(generation fired: Int) -> Bool {
        guard generation == fired, !Task.isCancelled, let pending = pendingWrite else { return false }
        do {
            try keychain.set(try JSONEncoder().encode(pending), for: Self.sessionKey)
            writeLanded()
            writeRetry = nil
            return false
        } catch {
            return true
        }
    }

    /// The new session is in the Keychain, over whatever a failed sign-out
    /// left there, so the sign-out marker has done its job.
    private func writeLanded() {
        pendingWrite = nil
        guard marker.isSet else { return }
        marker.set(false)
        clearRetry?.cancel()
        clearRetry = nil
        // The person cached for the old session; `cachedUser` ignores it
        // anyway when it's someone else.
        try? keychain.remove(Self.userKey)
    }

    private func loadStored() throws -> Stored? {
        if signingOut { return nil }
        if let stored { return stored }
        // Signed out, but the Keychain wouldn't let go of the session yet:
        // it doesn't count.
        guard clearSignedOutStorage() else { return nil }
        guard let data = try keychain.data(for: Self.sessionKey) else { return nil }
        stored = try? JSONDecoder().decode(Stored.self, from: data)
        return stored
    }

    /// Forgets the in-memory session and stops refreshing. Leaves the Keychain.
    private func endSession() {
        generation += 1
        timer?.cancel()
        timer = nil
        refreshTask = nil
        writeRetry?.cancel()
        writeRetry = nil
        pendingWrite = nil
        stored = nil
        accessToken = nil
        accessTokenExpiry = nil
        accessTokenIssuedAt = nil
    }

    /// The session in the Keychain is dead: mark it so (outside the
    /// Keychain, so it holds across restarts), then remove it.
    private func invalidateStorage() {
        marker.set(true)
        clearSignedOutStorage()
    }

    /// While the sign-out marker is set, removes the session and the cached
    /// person from the Keychain and clears the marker once both are gone. On
    /// failure keeps the marker and makes sure a retry is scheduled.
    /// Returns whether the Keychain is clean.
    @discardableResult
    private func clearSignedOutStorage() -> Bool {
        guard marker.isSet else { return true }
        do {
            try keychain.remove(Self.sessionKey)
            try keychain.remove(Self.userKey)
            marker.set(false)
            clearRetry?.cancel()
            clearRetry = nil
            return true
        } catch {
            scheduleClearRetry()
            return false
        }
    }

    private func scheduleClearRetry() {
        guard clearRetry == nil else { return }
        let sleep = writeRetrySleep
        clearRetry = Task { [weak self] in
            var delay: TimeInterval = 1
            while true {
                do { try await sleep(.milliseconds(Int64((delay * 1000).rounded()))) } catch { return }
                guard let self, await self.retryClear() else { return }
                delay = min(delay * 2, ConvexSession.maxWriteRetryDelay)
            }
        }
    }

    /// One retry from the clear backoff loop. Returns whether to keep
    /// retrying.
    private func retryClear() -> Bool {
        guard !Task.isCancelled else { return false }
        // A sign-in since owns the Keychain; its write clears the marker.
        guard stored == nil, marker.isSet else {
            clearRetry = nil
            return false
        }
        do {
            try keychain.remove(Self.sessionKey)
            try keychain.remove(Self.userKey)
            marker.set(false)
            clearRetry = nil
            return false
        } catch {
            return true
        }
    }

    // MARK: Last known user

    /// The person as `me()` last returned them, so a launch with no signal
    /// still opens signed in.
    func cachedUser() -> AppUser? {
        guard let current = try? loadStored(),
              let data = try? keychain.data(for: Self.userKey),
              let user = try? JSONDecoder().decode(AppUser.self, from: data),
              user.userId == current.userId
        else { return nil }
        return user
    }

    func cacheUser(_ user: AppUser) {
        guard (try? loadStored()) != nil, let data = try? JSONEncoder().encode(user) else { return }
        try? keychain.set(data, for: Self.userKey)
    }
}
