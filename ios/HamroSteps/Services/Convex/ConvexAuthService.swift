import Foundation

/// `AuthService` against the Convex backend: Sign in with Apple through
/// `POST /auth/apple`, then the person from `users:me`.
///
/// The session survives restarts. A launch with no signal opens with the
/// last known person; only a revoked session signs out.
actor ConvexAuthService: AuthService {
    private let connection: ConvexConnection
    private var session: ConvexSession { connection.session }
    /// The background `me()` refresh started by `currentUser`, for tests.
    private(set) var userRefresh: Task<Void, Never>?

    init(connection: ConvexConnection) {
        self.connection = connection
    }

    var currentUser: AppUser? {
        get async {
            guard (try? await session.hasStoredSession()) == true else { return nil }
            if let cached = await session.cachedUser() {
                // Open straight away; bring the person up to date (and sign
                // the connection in) behind it.
                userRefresh = Task { _ = try? await self.fetchMe() }
                return cached
            }
            return try? await fetchMe()
        }
    }

    func signInWithApple(identityToken: String, authorizationCode: String, fullName: PersonNameComponents?, timeZone: String) async throws -> AppUser {
        guard !identityToken.isEmpty else { throw FamilyServiceError.invalidToken }
        let request = AppleSignInRequest(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName,
            timezone: timeZone
        )
        do {
            _ = try await session.signInWithApple(request)
        } catch {
            throw FamilyServiceError(convex: error)
        }
        await connection.sessionChanged()
        do {
            return try await fetchMe()
        } catch FamilyServiceError.notAuthenticated {
            // The backend refused the brand-new session even after a
            // refresh: it's revoked, so don't leave it behind.
            await signOut()
            throw FamilyServiceError.notAuthenticated
        } catch {
            // Offline or server trouble: the session is good, so keep it.
            // `/auth/apple` doesn't return enough for an `AppUser` (no
            // avatar colour), so throw the retryable error; the next
            // `currentUser` (or sign-in) fetches the person.
            throw error
        }
    }

    func updateName(_ name: String) async throws -> AppUser {
        let _: ConvexNull = try await connection.run {
            try await $0.mutation("users:updateProfile", args: ["name": .string(name)])
        }
        return try await fetchMe()
    }

    func signOut() async {
        await session.signOut()
        await connection.signedOut()
    }

    func deleteAccount() async throws {
        await session.forget()
        await connection.signedOut()
    }

    private func fetchMe() async throws -> AppUser {
        let user: AppUser = try await connection.run { try await $0.query("users:me", args: [:]) }
        await session.cacheUser(user)
        return user
    }
}
