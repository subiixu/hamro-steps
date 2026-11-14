import Foundation
@testable import HamroSteps

// Fakes for the Convex layer: no network, no system Keychain, no real time.

/// Keychain in a dictionary. `failure` makes every call throw (locked);
/// `removeFailure` makes only deletes throw.
final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var _failure: KeychainError?
    private var _removeFailure: KeychainError?

    var failure: KeychainError? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    var removeFailure: KeychainError? {
        get { lock.withLock { _removeFailure } }
        set { lock.withLock { _removeFailure = newValue } }
    }

    func data(for key: String) throws -> Data? {
        try lock.withLock {
            if let _failure { throw _failure }
            return items[key]
        }
    }

    func set(_ data: Data, for key: String) throws {
        try lock.withLock {
            if let _failure { throw _failure }
            items[key] = data
        }
    }

    func remove(_ key: String) throws {
        try lock.withLock {
            if let failure = _failure ?? _removeFailure { throw failure }
            items[key] = nil
        }
    }

    var keys: Set<String> { lock.withLock { Set(items.keys) } }
    func raw(_ key: String) -> String? { lock.withLock { items[key].map { String(decoding: $0, as: UTF8.self) } } }
}

/// The sign-out marker in memory. Pass the same one (with the same
/// keychain) to simulate an app restart.
final class InMemorySignOutMarker: SignOutMarkerStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set(_ value: Bool) { lock.withLock { self.value = value } }
}

/// Holds whoever calls `wait()` until `open()`; stays open after.
actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { waiters.count }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// A clock the test moves by hand.
final class SessionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_800_000_000)) { _now = now }

    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now += seconds } }
    /// Epoch milliseconds `seconds` from now, as the backend sends expiry.
    func ms(in seconds: TimeInterval) -> Double { (now.timeIntervalSince1970 + seconds) * 1000 }
}

/// Records each requested sleep and holds it until the test releases it.
actor TestSleeper {
    private(set) var requested: [Duration] = []
    private var waiting: [CheckedContinuation<Void, any Error>] = []

    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
        try await withCheckedThrowingContinuation { waiting.append($0) }
    }

    /// Lets the oldest pending sleep finish.
    func releaseNext() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }

    var pending: Int { waiting.count }
}

/// The `/auth/*` endpoints. Each refresh hands out the next numbered token
/// pair unless `refreshResults` has something queued.
actor FakeAuthEndpoints: AuthEndpoints {
    let clock: SessionClock
    var accessLifetime: TimeInterval = 15 * 60
    private(set) var signIns: [AppleSignInRequest] = []
    private(set) var refreshes: [String] = []
    private(set) var logouts: [String] = []
    var refreshResults: [Result<Void, AuthEndpointError>] = []
    var logoutError: AuthEndpointError?
    var signInError: AuthEndpointError?
    /// When set, refreshes wait for `openGate()`.
    private var gateClosed = false
    private var gated: [CheckedContinuation<Void, Never>] = []
    private var counter = 0
    /// When set, logouts wait for `openLogoutGate()`.
    private var logoutGateClosed = false
    private var logoutGated: [CheckedContinuation<Void, Never>] = []

    init(clock: SessionClock) { self.clock = clock }

    func setRefreshResults(_ results: [Result<Void, AuthEndpointError>]) { refreshResults = results }
    func setLogoutError(_ error: AuthEndpointError?) { logoutError = error }
    func setSignInError(_ error: AuthEndpointError?) { signInError = error }
    func closeGate() { gateClosed = true }
    func openGate() {
        gateClosed = false
        gated.forEach { $0.resume() }
        gated = []
    }

    func closeLogoutGate() { logoutGateClosed = true }
    func openLogoutGate() {
        logoutGateClosed = false
        logoutGated.forEach { $0.resume() }
        logoutGated = []
    }

    func tokens() -> SessionTokens {
        counter += 1
        return SessionTokens(
            accessToken: "access-\(counter)",
            accessTokenExpiresAt: clock.ms(in: accessLifetime),
            refreshToken: "refresh-\(counter)",
            refreshTokenExpiresAt: clock.ms(in: 30 * 24 * 3600),
            userId: "user_1"
        )
    }

    func signInWithApple(_ request: AppleSignInRequest) async throws -> AppleSignInResponse {
        signIns.append(request)
        if let signInError { throw signInError }
        return AppleSignInResponse(tokens: tokens(), isNewUser: true, name: nil, needsName: true)
    }

    func refresh(refreshToken: String) async throws -> SessionTokens {
        refreshes.append(refreshToken)
        if gateClosed { await withCheckedContinuation { gated.append($0) } }
        if !refreshResults.isEmpty, case .failure(let error) = refreshResults.removeFirst() {
            throw error
        }
        return tokens()
    }

    func logout(refreshToken: String) async throws {
        logouts.append(refreshToken)
        if logoutGateClosed { await withCheckedContinuation { logoutGated.append($0) } }
        if let logoutError { throw logoutError }
    }
}

/// Collects what the session tells the Convex client.
final class TokenLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _tokens: [String?] = []
    var tokens: [String?] { lock.withLock { _tokens } }
    func record(_ token: String?) { lock.withLock { _tokens.append(token) } }
}

/// The Convex client: answers from JSON fixtures per function, in order, and
/// signs in the way the real `ConvexSessionAuthProvider` does.
final class FakeTransport: ConvexTransport, @unchecked Sendable {
    struct Call: Hashable {
        var kind: String
        var name: String
        var args: [String: ConvexArg]
    }

    let session: ConvexSession
    private let lock = NSLock()
    private var responses: [String: [Result<String, ConvexCallError>]] = [:]
    private var _calls: [Call] = []
    private var _authenticatedTokens: [String] = []
    private var _cleared = 0
    private var _subscriptions: [String: [AsyncThrowingStream<String, any Error>.Continuation]] = [:]

    init(session: ConvexSession) { self.session = session }

    /// Queues an answer for `name`: JSON text, or an error.
    func respond(_ name: String, json: String) { add(name, .success(json)) }
    func fail(_ name: String, _ error: ConvexCallError) { add(name, .failure(error)) }
    private func add(_ name: String, _ result: Result<String, ConvexCallError>) {
        lock.withLock { responses[name, default: []].append(result) }
    }

    var calls: [Call] { lock.withLock { _calls } }
    var authenticatedTokens: [String] { lock.withLock { _authenticatedTokens } }
    var cleared: Int { lock.withLock { _cleared } }
    func subscriptions(_ name: String) -> [AsyncThrowingStream<String, any Error>.Continuation] {
        lock.withLock { _subscriptions[name] ?? [] }
    }

    private func answer<T: Decodable>(_ kind: String, _ name: String, _ args: [String: ConvexArg]) throws -> T {
        let result: Result<String, ConvexCallError>? = lock.withLock {
            _calls.append(Call(kind: kind, name: name, args: args))
            guard var queue = responses[name], !queue.isEmpty else { return nil }
            let first = queue.removeFirst()
            responses[name] = queue
            return first
        }
        guard let result else { throw ConvexCallError.client("no fixture for \(name)") }
        return try JSONDecoder().decode(T.self, from: Data(try result.get().utf8))
    }

    func query<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        try answer("query", name, args)
    }

    func mutation<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        try answer("mutation", name, args)
    }

    func action<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        try answer("action", name, args)
    }

    /// Feed it with `subscriptions(name).last?.yield(json)`.
    func subscribe<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg], as type: T.Type) -> AsyncThrowingStream<T, any Error> {
        let (raw, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        lock.withLock {
            _calls.append(Call(kind: "subscribe", name: name, args: args))
            _subscriptions[name, default: []].append(continuation)
        }
        return AsyncThrowingStream { output in
            let task = Task {
                do {
                    for try await json in raw {
                        output.yield(try JSONDecoder().decode(T.self, from: Data(json.utf8)))
                    }
                    output.finish()
                } catch {
                    output.finish(throwing: error)
                }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }

    func authenticate() async throws {
        let token = try await session.validAccessToken()
        lock.withLock { _authenticatedTokens.append(token) }
    }

    func clearAuthentication() async {
        lock.withLock { _cleared += 1 }
    }
}

/// One set of fakes wired like `ConvexServices.live`.
struct ConvexHarness {
    let clock: SessionClock
    let keychain: InMemoryKeychain
    let marker: InMemorySignOutMarker
    let endpoints: FakeAuthEndpoints
    let sleeper: TestSleeper
    /// Drives the Keychain write and removal retries.
    let storageSleeper: TestSleeper
    let session: ConvexSession
    let transport: FakeTransport
    let services: ConvexServices
    let tokenLog = TokenLog()

    /// Pass the same `keychain`, `marker` (and `clock`) to simulate an app
    /// restart.
    init(clock: SessionClock = SessionClock(), keychain: InMemoryKeychain = InMemoryKeychain(), marker: InMemorySignOutMarker = InMemorySignOutMarker()) async {
        self.clock = clock
        self.keychain = keychain
        self.marker = marker
        endpoints = FakeAuthEndpoints(clock: clock)
        let sleeper = TestSleeper()
        self.sleeper = sleeper
        let storageSleeper = TestSleeper()
        self.storageSleeper = storageSleeper
        session = ConvexSession(
            endpoints: endpoints,
            keychain: keychain,
            marker: marker,
            now: { [clock] in clock.now },
            sleep: { try await sleeper.sleep($0) },
            writeRetrySleep: { try await storageSleeper.sleep($0) }
        )
        transport = FakeTransport(session: session)
        services = ConvexServices(connection: ConvexConnection(transport: transport, session: session))
        let log = tokenLog
        await session.setListener { log.record($0) }
    }

    var auth: ConvexAuthService { services.auth }
    var family: ConvexFamilyService { services.family }

    /// Signs in through the auth service with a `me()` fixture.
    @discardableResult
    func signIn(name: String? = "Sita") async throws -> AppUser {
        transport.respond("users:me", json: Fixtures.me(name: name))
        return try await auth.signInWithApple(identityToken: "id-token", authorizationCode: "auth-code", fullName: nil, timeZone: "Asia/Kathmandu")
    }
}

/// Backend return shapes, as the Convex client hands them over. Numbers
/// sometimes carry a `.0`: Convex numbers are floats.
enum Fixtures {
    static func me(name: String? = "Sita") -> String {
        let nameJSON = name.map { "\"\($0)\"" } ?? "null"
        return """
        {"userId":"user_1","name":\(nameJSON),"needsName":\(name == nil),"avatarColor":"#E07A5F","timezone":"Asia/Kathmandu","lastSyncedAt":null}
        """
    }

    static let familyView = """
    {"familyId":"fam_1","name":"Sharma Family","dailyGoal":50000.0,"inviteCode":"K7P2QX","organiserId":"user_1","memberCount":1.0,"isFull":false}
    """

    static let previewInvite = """
    {"familyId":"fam_1","name":"Sharma Family","memberCount":3,"isFull":false,"alreadyMember":false}
    """

    static let myFamilies = """
    [{"familyId":"fam_1","name":"Sharma Family","dailyGoal":50000,"inviteCode":"K7P2QX","organiserId":"user_1","memberCount":3,"isFull":false,"isOrganiser":true,"position":0},
     {"familyId":"fam_2","name":"Thapa","dailyGoal":30000,"inviteCode":"M3N8RT","organiserId":"user_9","memberCount":8,"isFull":true,"isOrganiser":false,"position":4.0}]
    """

    static let inviteCode = #"{"inviteCode":"Z9Y8X7"}"#

    static let syncSteps = #"{"lastSyncedAt":1800000123456,"today":"2027-01-15"}"#

    static func familyToday(total: Int = 21000) -> String {
        """
        {"family":\(familyView),"day":"2027-01-15","goal":50000,"total":\(total),"percent":42,
         "members":[
          {"userId":"user_1","name":"Sita","avatarColor":"#E07A5F","position":0,"isOrganiser":true,"steps":12000.0,"lastSyncedAt":1800000000000,"status":null},
          {"userId":"user_2","name":null,"avatarColor":"#3D405B","position":1,"isOrganiser":false,"steps":null,"lastSyncedAt":null,"status":null}
         ]}
        """
    }

    static let familyWeek = """
    {"today":"2027-01-15","weekStart":"2027-01-11","startsAt":1799951400000,
     "days":[{"day":"2027-01-11","total":0,"goal":50000,"hit":false,"isFuture":false,"isBeforeFamily":true},
             {"day":"2027-01-15","total":52000,"goal":50000,"hit":true,"isFuture":false,"isBeforeFamily":false},
             {"day":"2027-01-16","total":0,"goal":50000,"hit":false,"isFuture":true,"isBeforeFamily":false}]}
    """

    static func deleteMyAccount(_ result: String) -> String { #"{"appleRevoke":"\#(result)"}"# }

    static let appleResponse = """
    {"accessToken":"a.b.c","accessTokenExpiresAt":1800000900000,"refreshToken":"r1","refreshTokenExpiresAt":1802592000000,"userId":"user_1","isNewUser":true,"name":null,"needsName":true}
    """

    static let refreshResponse = """
    {"accessToken":"a.b.d","accessTokenExpiresAt":1800001800000,"refreshToken":"r2","refreshTokenExpiresAt":1802592900000,"userId":"user_1"}
    """
}
