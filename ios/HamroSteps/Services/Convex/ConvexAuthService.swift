import Foundation

/// `AuthService` against the Convex backend: Sign in with Apple through
/// `POST /auth/apple`, then the person from `users:me`.
///
/// The session survives restarts. A launch with no signal opens with the
/// last known person; only a revoked session signs out.
actor ConvexAuthService: AuthService {
    private let connection: ConvexConnection
    private let uploader: any PhotoUploading
    private var session: ConvexSession { connection.session }
    /// The background `me()` refresh started by `currentUser`, for tests.
    private(set) var userRefresh: Task<Void, Never>?

    init(connection: ConvexConnection, uploader: any PhotoUploading = URLSessionPhotoUploader()) {
        self.connection = connection
        self.uploader = uploader
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

    func updateProfile(_ profile: ProfileUpdate) async throws -> AppUser {
        let args: [String: ConvexArg] = [
            "name": .string(FamilyRules.cleanName(profile.name)),
            "city": .string(FamilyRules.cleanCity(profile.city)),
            "birthday": profile.birthday.map { .string($0) } ?? .null,
        ]
        let _: ConvexNull = try await connection.run { try await $0.mutation("users:updateProfile", args: args) }
        return try await fetchMe()
    }

    /// The upload can take a while. If the person signs out (or another
    /// account signs in) meanwhile, the photo must not land on whoever is
    /// signed in by then, so each step checks it's still the same session.
    /// `userId` is the account the photo was picked for; the server refuses
    /// it (`not_authorized`) when another account's token sends it, which
    /// also covers an auth retry that runs as the next account.
    func setPhoto(jpeg: Data, userId: String) async throws -> AppUser {
        let generation = await session.currentGeneration
        guard await session.userId != nil else { throw FamilyServiceError.notAuthenticated }
        try await ensureSameSession(generation: generation, userId: userId)
        let address: String = try await connection.run { try await $0.mutation("users:generateAvatarUploadUrl", args: [:]) }
        guard let url = URL(string: address) else { throw FamilyServiceError.unavailable("upload_url") }
        let storageId = try await uploader.upload(jpeg, to: url)
        try await ensureSameSession(generation: generation, userId: userId)
        try await refusingOtherAccounts {
            let _: ConvexNull = try await connection.run {
                try await $0.mutation("users:setAvatar", args: ["storageId": .string(storageId), "userId": .string(userId)])
            }
        }
        try await ensureSameSession(generation: generation, userId: userId)
        return try await fetchMe()
    }

    /// Throws `CancellationError` when the session that started some work has
    /// ended or been replaced since.
    private func ensureSameSession(generation: Int, userId: String) async throws {
        let stillStored = (try? await session.hasStoredSession()) ?? false
        guard await session.currentGeneration == generation,
              await session.userId == userId,
              stillStored
        else { throw CancellationError() }
    }

    func removePhoto(userId: String) async throws -> AppUser {
        let generation = await session.currentGeneration
        try await ensureSameSession(generation: generation, userId: userId)
        try await refusingOtherAccounts {
            let _: ConvexNull = try await connection.run {
                try await $0.mutation("users:removeAvatar", args: ["userId": .string(userId)])
            }
        }
        try await ensureSameSession(generation: generation, userId: userId)
        return try await fetchMe()
    }

    /// The server's `not_authorized` here means the photo change was meant
    /// for an account that's no longer signed in: a cancellation, not an
    /// error to show.
    private func refusingOtherAccounts(_ work: () async throws -> Void) async throws {
        do {
            try await work()
        } catch FamilyServiceError.unavailable("not_authorized") {
            throw CancellationError()
        }
    }

    func updateTimeZone(_ identifier: String) async throws {
        let _: ConvexNull = try await connection.run {
            try await $0.mutation("users:updateProfile", args: ["timezone": .string(identifier)])
        }
        _ = try await fetchMe()
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

/// Sends photo bytes to a Convex storage upload URL; returns the `storageId`.
protocol PhotoUploading: Sendable {
    func upload(_ jpeg: Data, to url: URL) async throws -> String
}

/// The real upload: one `POST` with the JPEG as the body. Failures come out
/// as `FamilyServiceError.unavailable`, which the screen shows as "try again".
struct URLSessionPhotoUploader: PhotoUploading {
    var session: URLSession = .shared

    func upload(_ jpeg: Data, to url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: jpeg)
        } catch {
            throw FamilyServiceError.unavailable("upload_failed")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FamilyServiceError.unavailable("upload_failed")
        }
        return try Self.storageId(from: data)
    }

    /// Convex answers `{"storageId": "..."}`.
    static func storageId(from data: Data) throws -> String {
        struct Body: Decodable { let storageId: String }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), !body.storageId.isEmpty else {
            throw FamilyServiceError.unavailable("upload_failed")
        }
        return body.storageId
    }
}
