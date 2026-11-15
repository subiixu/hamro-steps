import Foundation

/// In-memory sign-in for this phase (no backend yet). Signs in as the mock
/// backend's sample user. Remembers "signed in" in `defaults` so the
/// simulator stays signed in across launches.
actor MockAuthService: AuthService {
    static let preview = MockAuthService(backend: MockFamilyService.preview, defaults: nil)

    /// Whether the simulator was signed in when the app last ran. The app
    /// builds the mock backend with this, so a relaunch stays signed in.
    static let signedInKey = "mock.signedIn"

    private let backend: MockFamilyService
    private let defaults: UserDefaults?
    /// What the last sign-in received, for tests.
    private(set) var lastSignIn: (identityToken: String, authorizationCode: String, fullName: PersonNameComponents?, timeZone: String)?

    init(backend: MockFamilyService, defaults: UserDefaults?) {
        self.backend = backend
        self.defaults = defaults
    }

    var currentUser: AppUser? {
        get async { await backend.currentUser }
    }

    func signInWithApple(identityToken: String, authorizationCode: String, fullName: PersonNameComponents?, timeZone: String) async throws -> AppUser {
        guard !identityToken.isEmpty, !authorizationCode.isEmpty else {
            throw FamilyServiceError.invalidToken
        }
        lastSignIn = (identityToken, authorizationCode, fullName, timeZone)
        let user = await backend.signIn(fullName: fullName, timeZone: timeZone)
        defaults?.set(true, forKey: Self.signedInKey)
        return user
    }

    func updateName(_ name: String) async throws -> AppUser {
        try await backend.updateMyName(name)
    }

    func updateProfile(_ profile: ProfileUpdate) async throws -> AppUser {
        try await backend.updateMyProfile(profile)
    }

    func setPhoto(jpeg: Data, userId: String) async throws -> AppUser {
        try await requireSignedIn(userId)
        return try await backend.setMyPhoto(jpeg: jpeg)
    }

    func removePhoto(userId: String) async throws -> AppUser {
        try await requireSignedIn(userId)
        return try await backend.removeMyPhoto()
    }

    /// Mirrors the server's `not_authorized` check, as a cancellation.
    private func requireSignedIn(_ userId: String) async throws {
        guard let signedIn = await backend.currentUser else { throw FamilyServiceError.notAuthenticated }
        guard signedIn.id == userId else { throw CancellationError() }
    }

    func updateTimeZone(_ identifier: String) async throws {
        try await backend.updateMyTimeZone(identifier)
    }

    func signOut() async {
        await backend.signOut()
        defaults?.set(false, forKey: Self.signedInKey)
    }

    func deleteAccount() async throws {
        await backend.signOut()
        defaults?.set(false, forKey: Self.signedInKey)
    }
}
