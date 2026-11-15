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
    private var isSyncingTimeZone = false
    /// Bumped on every start, sign-in, sign-out and delete, so a profile
    /// change that finishes after the account changed can't put the old
    /// person back on screen.
    private var accountEpoch = 0
    /// The Health screen is shown once, whatever the person picked.
    private(set) var healthOnboardingDone: Bool

    private let auth: any AuthService
    private let service: any FamilyService
    private let defaults: UserDefaults
    private let push: PushRegistrar?

    init(auth: any AuthService, service: any FamilyService, defaults: UserDefaults = .standard, push: PushRegistrar? = nil) {
        self.auth = auth
        self.service = service
        self.defaults = defaults
        self.push = push
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
        accountEpoch += 1
        user = await auth.currentUser
        if let push, push.hasUnfinishedSignOut {
            // The app quit before an earlier sign-out's cleanup finished:
            // finish it now, still as that account.
            if user != nil {
                let auth = auth
                await push.signOut { await auth.signOut() }
            } else {
                push.forgetUnfinishedSignOut()
            }
            user = nil
        }
        if user != nil { await refreshFamilies() }
        isStarted = true
    }

    func signIn(identityToken: String, authorizationCode: String, fullName: PersonNameComponents?) async throws {
        accountEpoch += 1
        let auth = auth
        let timeZone = TimeZone.current.identifier
        let signIn: @MainActor () async throws -> AppUser = {
            try await auth.signInWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName,
                timeZone: timeZone
            )
        }
        // Through the push queue: the previous account's push cleanup and
        // sign-out finish first, so none of it can run as (or undo) this one.
        if let push { user = try await push.signIn(signIn) } else { user = try await signIn() }
        await refreshFamilies()
    }

    func saveName(_ name: String) async throws {
        user = try await auth.updateName(FamilyRules.cleanName(name))
    }

    /// The Me edit screen's Save.
    func saveProfile(_ profile: ProfileUpdate) async throws {
        let auth = auth
        try await applyToSameAccount { try await auth.updateProfile(profile) }
    }

    /// `jpeg` is already downscaled (`ProfilePhoto.jpeg`). `userId` is who
    /// was signed in when the person started the photo action; if that's no
    /// longer who's signed in, nothing is sent (`CancellationError`).
    func setPhoto(jpeg: Data, userId: String) async throws {
        guard user?.id == userId else { throw CancellationError() }
        let auth = auth
        try await applyToSameAccount { try await auth.setPhoto(jpeg: jpeg, userId: userId) }
    }

    func removePhoto(userId: String) async throws {
        guard user?.id == userId else { throw CancellationError() }
        let auth = auth
        try await applyToSameAccount { try await auth.removePhoto(userId: userId) }
    }

    /// Runs a profile change and shows its result, unless the account
    /// changed while it ran: then throws `CancellationError` and leaves
    /// `user` alone.
    private func applyToSameAccount(_ change: @MainActor () async throws -> AppUser) async throws {
        let epoch = accountEpoch
        let userId = user?.id
        let updated = try await change()
        guard accountEpoch == epoch, user?.id == userId else { throw CancellationError() }
        user = updated
    }

    /// When the phone's time zone differs from the stored one (they
    /// travelled), store the new one so family see the right local time.
    /// Quiet: no UI, failures are left for the next time the app opens.
    func syncTimeZone(_ identifier: String = TimeZone.current.identifier) async {
        guard let user, !identifier.isEmpty, user.timezone != identifier, !isSyncingTimeZone else { return }
        isSyncingTimeZone = true
        defer { isSyncingTimeZone = false }
        do {
            try await auth.updateTimeZone(identifier)
            if self.user?.id == user.id { self.user?.timezone = identifier }
        } catch {
            // Ignored: tried again next time the app becomes active.
        }
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

    /// Unregisters this phone's push tokens first, so the account's pushes
    /// stop reaching it. Best effort: unregister errors are ignored and each
    /// call is cut off by its request timeout.
    func signOut() async {
        accountEpoch += 1
        if let push {
            let auth = auth
            await push.signOut { await auth.signOut() }
        } else {
            await auth.signOut()
        }
        user = nil
        families = []
    }

    /// Two-step confirmed in the UI. Deletes everything on the backend first;
    /// only then forgets the local session. On failure the person stays
    /// signed in and nothing is lost.
    func deleteAccount() async throws {
        accountEpoch += 1
        let service = service
        let auth = auth
        let delete: @MainActor () async throws -> Void = {
            try await service.deleteMyAccount()
            try await auth.deleteAccount()
        }
        do {
            // Through the push queue: unregisters this phone first.
            if let push { try await push.deleteAccount(delete) } else { try await delete() }
        } catch {
            await push?.restore()
            throw error
        }
        user = nil
        families = []
    }
}
