import Combine
import Foundation
@preconcurrency import ConvexMobile

/// Hands the session's access token to `ConvexClientWithAuth`. By the time
/// the client asks, the session already exists (`/auth/apple` ran first, or
/// the Keychain had it), so neither call shows any UI.
///
/// - `login` is how we install the token (`LiveConvexTransport.authenticate`):
///   the current one, refreshed first only when it's near expiry.
/// - `loginFromCache` is what the SDK calls when the server rejected the
///   token it holds (its `fetchToken(forceRefresh: true)`), so it always
///   refreshes, however long the rejected token had left.
final class ConvexSessionAuthProvider: AuthProvider, Sendable {
    typealias T = String

    let session: ConvexSession

    init(session: ConvexSession) {
        self.session = session
    }

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        await session.setListener(onIdToken)
        return try await session.validAccessToken()
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        await session.setListener(onIdToken)
        return try await session.refreshRejectedToken()
    }

    /// The session ends in `ConvexSession.signOut`; the client only drops the token.
    func logout() async throws {}

    func extractIdToken(from authResult: String) -> String { authResult }
}

/// `ConvexTransport` over the Convex Swift SDK.
///
/// `@unchecked Sendable`: the SDK's client isn't annotated, but its calls go
/// to the thread-safe Rust core and it serialises auth changes itself.
final class LiveConvexTransport: ConvexTransport, @unchecked Sendable {
    private let client: ConvexClientWithAuth<String>

    init(deploymentURL: URL, session: ConvexSession) {
        client = ConvexClientWithAuth(
            deploymentUrl: deploymentURL.absoluteString,
            authProvider: ConvexSessionAuthProvider(session: session)
        )
    }

    func query<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        // The SDK has no one-shot query: take the subscription's first value.
        for try await value in subscribe(name, args: args, as: T.self) {
            return value
        }
        try Task.checkCancellation()
        throw ConvexCallError.client("\(name) returned no value")
    }

    func mutation<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        do {
            return try await client.mutation(name, with: Self.encode(args))
        } catch {
            throw Self.callError(error)
        }
    }

    func action<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T {
        do {
            return try await client.action(name, with: Self.encode(args))
        } catch {
            throw Self.callError(error)
        }
    }

    func subscribe<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg], as type: T.Type) -> AsyncThrowingStream<T, any Error> {
        AsyncThrowingStream { continuation in
            let cancellable = client.subscribe(to: name, with: Self.encode(args), yielding: T.self)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            continuation.finish(throwing: Self.callError(error))
                        } else {
                            continuation.finish()
                        }
                    },
                    receiveValue: { continuation.yield($0) }
                )
            let box = CancellableBox(cancellable)
            continuation.onTermination = { _ in box.cancel() }
        }
    }

    func authenticate() async throws {
        // `login`, not `loginFromCache`: the provider keeps `loginFromCache`
        // for the SDK's forced refresh after a rejected token.
        if case .failure(let error) = await client.login() {
            throw error
        }
    }

    func clearAuthentication() async {
        await client.logout()
    }

    // MARK: Encoding

    static func encode(_ args: [String: ConvexArg]) -> [String: ConvexEncodable?] {
        args.mapValues { encode($0) }
    }

    private static func encode(_ arg: ConvexArg) -> ConvexEncodable? {
        switch arg {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .array(let values): values.map { encode($0) } as [ConvexEncodable?]
        case .object(let values): values.mapValues { encode($0) } as [String: ConvexEncodable?]
        }
    }

    static func callError(_ error: any Error) -> ConvexCallError {
        if let error = error as? ConvexCallError { return error }
        guard let error = error as? ClientError else {
            return .client(String(describing: error))
        }
        switch error {
        case .ConvexError(let data): return ConvexCallError(convexData: data)
        case .ServerError(let message): return .server(message)
        case .InternalError(let message): return .client(message)
        }
    }
}

/// Lets the stream's termination handler, which must be `Sendable`, cancel
/// the Combine subscription.
private final class CancellableBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellable: AnyCancellable?

    init(_ cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        lock.withLock {
            cancellable?.cancel()
            cancellable = nil
        }
    }
}
