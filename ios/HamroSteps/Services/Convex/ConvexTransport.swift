import Foundation

/// A Convex function argument. Our own type rather than the SDK's
/// `ConvexEncodable` so calls are `Sendable` and tests can compare them.
/// Numbers are always sent as floats: the SDK encodes Swift `Int` as a Convex
/// int64, which the backend's `v.number()` validators reject.
enum ConvexArg: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ConvexArg])
    case object([String: ConvexArg])
    /// JSON `null`, e.g. `birthday: null` to clear it.
    case null

    static func int(_ value: Int) -> ConvexArg { .number(Double(value)) }
}

/// What a Convex call failed with, before it becomes a `FamilyServiceError`.
enum ConvexCallError: Error, Hashable, Sendable {
    /// Our function threw `ConvexError({code})`. `code` is `nil` when the data
    /// had no code.
    case convex(code: String?)
    /// The function failed some other way (a bug, a server error).
    case server(String)
    /// The client couldn't send the call or read its result.
    case client(String)

    /// From the `data` the SDK hands over: the error's JSON, normally
    /// `{"code":"family_full"}`.
    init(convexData data: String) {
        struct Body: Decodable { let code: String }
        let bytes = Data(data.utf8)
        if let body = try? JSONDecoder().decode(Body.self, from: bytes) {
            self = .convex(code: body.code)
        } else if let code = try? JSONDecoder().decode(String.self, from: bytes) {
            self = .convex(code: code)
        } else {
            self = .convex(code: nil)
        }
    }

    var code: String? {
        if case .convex(let code) = self { return code }
        return nil
    }

    /// The access token was rejected: refresh and try once more.
    var isAuthFailure: Bool {
        code == "invalid_token" || code == "not_authenticated"
    }
}

/// The calls the services make on the Convex client: a seam so tests run
/// against a fake. Function names are `"module:function"`. Implementations
/// throw `ConvexCallError` for call failures.
protocol ConvexTransport: Sendable {
    func query<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T
    func mutation<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T
    func action<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg]) async throws -> T
    /// The query's current value, then every change, until the caller stops
    /// listening or the query throws.
    func subscribe<T: Decodable & Sendable>(_ name: String, args: [String: ConvexArg], as type: T.Type) -> AsyncThrowingStream<T, any Error>
    /// Signs the connection in with the session's current access token,
    /// waiting until the client has it. Throws what the session threw (for
    /// example `ConvexSessionError.signedOut`).
    func authenticate() async throws
    /// Back to an anonymous connection.
    func clearAuthentication() async
}

/// Decodes `null` (functions that return nothing).
struct ConvexNull: Decodable, Hashable, Sendable {
    init() {}
    init(from decoder: any Decoder) throws {}
}
