import Foundation
import Observation

/// Who is signed in, which families they're in, and so which screen comes
/// next: Welcome → (first name) → Health → create or join → Home.
@MainActor
@Observable
final class SessionStore {
    enum Route: Equatable {
        case launching
        case welcome
        case askName
        case health
        case setup
        case main
    }

    private static let healthDoneKey = "healthOnboardingDone"

    private(set) var user: AppUser?
    private(set) var families: [FamilySummary] = []
    private(set) var isStarted = false
    /// The Health screen is shown once, whatever the person picked.
    private(set) var healthOnboardingDone: Bool

    private let auth: any AuthService
    private let service: any FamilyService
    private let defaults: UserDefaults

    init(auth: any AuthService, service: any FamilyService, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.service = service
        self.defaults = defaults
        healthOnboardingDone = defaults.bool(forKey: Self.healthDoneKey)
    }

    var route: Route {
        guard isStarted else { return .launching }
        guard let user else { return .welcome }
        if user.needsName { return .askName }
        if !healthOnboardingDone { return .health }
        if families.isEmpty { return .setup }
        return .main
    }

    func start() async {
        user = await auth.currentUser
        if user != nil { await refreshFamilies() }
        isStarted = true
    }

    func signIn(identityToken: String, authorizationCode: String, fullName: PersonNameComponents?) async throws {
        let signedIn = try await auth.signInWithApple(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName,
            timeZone: TimeZone.current.identifier
        )
        user = signedIn
        await refreshFamilies()
    }

    func saveName(_ name: String) async throws {
        user = try await auth.updateName(FamilyRules.cleanName(name))
    }

    func finishHealthOnboarding() {
        healthOnboardingDone = true
        defaults.set(true, forKey: Self.healthDoneKey)
    }

    func refreshFamilies() async {
        do {
            families = try await service.myFamilies()
        } catch FamilyServiceError.notAuthenticated {
            user = nil
            families = []
        } catch {
            // Keep what we had; Home shows its own retry.
        }
    }

    func signOut() async {
        await auth.signOut()
        user = nil
        families = []
    }

    /// Two-step confirmed in the UI. Deletes everything on the backend first;
    /// only then forgets the local session. On failure the person stays
    /// signed in and nothing is lost.
    func deleteAccount() async throws {
        try await service.deleteMyAccount()
        try await auth.deleteAccount()
        user = nil
        families = []
    }
}
