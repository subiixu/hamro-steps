import Foundation

/// The transport and the session together, shared by `ConvexAuthService` and
/// `ConvexFamilyService`. Every call makes sure the connection is signed in
/// with a fresh token first, and when the backend still answers
/// `invalid_token` (or `not_authenticated`), refreshes and tries once more.
actor ConvexConnection {
    nonisolated let transport: any ConvexTransport
    nonisolated let session: ConvexSession

    /// Whether `transport` has been handed this session's token.
    private var isAuthenticated = false

    init(transport: any ConvexTransport, session: ConvexSession) {
        self.transport = transport
        self.session = session
    }

    /// Runs one call. Errors come out as `FamilyServiceError`.
    func run<T: Sendable>(_ call: @Sendable (any ConvexTransport) async throws -> T) async throws -> T {
        do {
            try await ensureAuthenticated()
            do {
                return try await call(transport)
            } catch let error as ConvexCallError where error.isAuthFailure {
                try await reauthenticate()
                return try await call(transport)
            }
        } catch {
            throw FamilyServiceError(convex: error)
        }
    }

    /// Signs the transport in when it isn't yet, or when the access token is
    /// within 2 minutes of expiry (the refresh happens on the way).
    func ensureAuthenticated() async throws {
        if isAuthenticated, await !session.needsRefresh { return }
        isAuthenticated = false
        try await transport.authenticate()
        isAuthenticated = true
    }

    /// After the backend rejected the token: a new one, whatever the clock says.
    func reauthenticate() async throws {
        isAuthenticated = false
        try await session.refresh()
        try await transport.authenticate()
        isAuthenticated = true
    }

    /// A new session began (sign-in): the next call hands its token over.
    func sessionChanged() {
        isAuthenticated = false
    }

    /// The session ended: back to an anonymous connection.
    func signedOut() async {
        isAuthenticated = false
        await transport.clearAuthentication()
    }

    /// A live query as a plain stream. A rejected token gets one refresh and
    /// a fresh subscription; any other failure, or a sign-out, ends the stream.
    nonisolated func updates<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg], as type: T.Type) -> AsyncStream<T> {
        AsyncStream { continuation in
            let task = Task {
                var retried = false
                while !Task.isCancelled {
                    do {
                        try await self.ensureAuthenticated()
                        for try await value in self.transport.subscribe(name, args: args, as: T.self) {
                            retried = false
                            continuation.yield(value)
                        }
                        break
                    } catch let error as ConvexCallError where error.isAuthFailure && !retried {
                        retried = true
                        do { try await self.reauthenticate() } catch { break }
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension FamilyServiceError {
    /// Any failure from the Convex layer, in the app's terms. Only a missing
    /// or revoked session becomes `notAuthenticated` (which signs out);
    /// trouble reaching the backend is `unavailable`.
    init(convex error: any Error) {
        switch error {
        case let error as FamilyServiceError:
            self = error
        case let error as ConvexCallError:
            switch error {
            case .convex(let code?): self = FamilyServiceError(code: code)
            case .convex(nil), .server: self = .unavailable("server")
            case .client: self = .unavailable("client")
            }
        case ConvexSessionError.signedOut:
            self = .notAuthenticated
        case let error as AuthEndpointError:
            switch error {
            case .invalidToken: self = .invalidToken
            case .invalidRequest: self = .unavailable("invalid_request")
            case .appleUnavailable: self = .unavailable("apple_unavailable")
            case .network: self = .unavailable("network")
            case .server: self = .unavailable("server")
            }
        case is KeychainError:
            self = .unavailable("keychain")
        case is CancellationError:
            self = .unavailable("cancelled")
        default:
            self = .unavailable("unknown")
        }
    }
}
