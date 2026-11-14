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

    func signOut() async {
        await backend.signOut()
        defaults?.set(false, forKey: Self.signedInKey)
    }

    func deleteAccount() async throws {
        await backend.signOut()
        defaults?.set(false, forKey: Self.signedInKey)
    }
}
