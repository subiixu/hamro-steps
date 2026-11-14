import Foundation

// The backend's session endpoints (`convex/http.ts`): POST JSON, errors are
// `{code}` with 400 `invalid_request`, 401 `invalid_token`, 503
// `apple_unavailable`. Times are epoch milliseconds.

/// `POST /auth/apple` body.
struct AppleSignInRequest: Encodable, Hashable, Sendable {
    struct FullName: Encodable, Hashable, Sendable {
        var givenName: String?
        var familyName: String?
    }

    var identityToken: String
    var authorizationCode: String?
    var fullName: FullName?
    var timezone: String?

    init(identityToken: String, authorizationCode: String?, fullName: PersonNameComponents?, timezone: String?) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode.flatMap { $0.isEmpty ? nil : $0 }
        let given = Self.clean(fullName?.givenName)
        let family = Self.clean(fullName?.familyName)
        self.fullName = (given == nil && family == nil) ? nil : FullName(givenName: given, familyName: family)
        self.timezone = timezone.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func clean(_ part: String?) -> String? {
        guard let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// `POST /auth/apple` response.
struct AppleSignInResponse: Decodable, Hashable, Sendable {
    var tokens: SessionTokens
    var isNewUser: Bool
    var name: String?
    var needsName: Bool

    private enum CodingKeys: String, CodingKey { case isNewUser, name, needsName }

    init(tokens: SessionTokens, isNewUser: Bool, name: String?, needsName: Bool) {
        self.tokens = tokens
        self.isNewUser = isNewUser
        self.name = name
        self.needsName = needsName
    }

    init(from decoder: any Decoder) throws {
        tokens = try SessionTokens(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isNewUser = try c.decode(Bool.self, forKey: .isNewUser)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        needsName = try c.decode(Bool.self, forKey: .needsName)
    }
}

/// `POST /auth/refresh` response, and the token half of `/auth/apple`.
struct SessionTokens: Codable, Hashable, Sendable {
    var accessToken: String
    /// Epoch milliseconds.
    var accessTokenExpiresAt: Double
    var refreshToken: String
    /// Epoch milliseconds.
    var refreshTokenExpiresAt: Double
    var userId: String

    var accessTokenExpiry: Date { Date(timeIntervalSince1970: accessTokenExpiresAt / 1000) }
}

enum AuthEndpointError: Error, Hashable, Sendable {
    /// 401: the Apple token, or the refresh token, is no good. For a refresh
    /// this means the session was revoked (or has expired).
    case invalidToken
    /// 400.
    case invalidRequest
    /// 503: Apple's servers couldn't be reached from the backend.
    case appleUnavailable
    /// No answer: offline, timed out.
    case network(String)
    /// Any other status.
    case server(Int)
}

/// The three session endpoints. A protocol so tests fake the server.
protocol AuthEndpoints: Sendable {
    func signInWithApple(_ request: AppleSignInRequest) async throws -> AppleSignInResponse
    /// The old refresh token is dead once this returns.
    func refresh(refreshToken: String) async throws -> SessionTokens
    func logout(refreshToken: String) async throws
}

/// `AuthEndpoints` over URLSession, against `CONVEX_SITE_URL`.
struct URLSessionAuthEndpoints: AuthEndpoints {
    var siteURL: URL
    var session: URLSession = .shared
    /// Short, so a cold launch with no signal doesn't hang on a spinner.
    var timeout: TimeInterval = 15

    func signInWithApple(_ request: AppleSignInRequest) async throws -> AppleSignInResponse {
        try decode(try await post("auth/apple", body: request))
    }

    func refresh(refreshToken: String) async throws -> SessionTokens {
        try decode(try await post("auth/refresh", body: ["refreshToken": refreshToken]))
    }

    func logout(refreshToken: String) async throws {
        _ = try await post("auth/logout", body: ["refreshToken": refreshToken])
    }

    private func post(_ path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: siteURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthEndpointError.network(String(describing: error))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        throw Self.error(status: status, body: data)
    }

    /// The backend's `{code}` wins over the status, so a new status code for a
    /// known error still maps right.
    static func error(status: Int, body: Data) -> AuthEndpointError {
        struct Body: Decodable { let code: String }
        switch (try? JSONDecoder().decode(Body.self, from: body))?.code {
        case "invalid_token": return .invalidToken
        case "invalid_request": return .invalidRequest
        case "apple_unavailable": return .appleUnavailable
        default: break
        }
        switch status {
        case 401: return .invalidToken
        case 400: return .invalidRequest
        case 503: return .appleUnavailable
        default: return .server(status)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AuthEndpointError.server(200)
        }
    }
}
