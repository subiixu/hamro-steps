import Foundation
import SwiftUI

/// Everything the app asks the backend about families and steps. Mirrors the
/// Convex functions one to one, so the Convex phase only swaps the
/// implementation. Methods throw `FamilyServiceError`.
protocol FamilyService: Sendable {
    func createFamily(name: String, dailyGoal: Int) async throws -> FamilySummary
    /// For the join screen: which family a code belongs to, before joining.
    func previewInvite(code: String) async throws -> InvitePreview
    func joinFamily(code: String) async throws -> FamilySummary
    /// Organiser only. Returns the new code; the old one stops working.
    func regenerateInviteCode(familyId: String) async throws -> String
    /// Organiser only; removing yourself is `cannotRemoveSelf` (leave instead).
    func removeMember(familyId: String, userId: String) async throws
    /// Organiser only.
    func updateFamily(familyId: String, name: String, dailyGoal: Int) async throws -> FamilySummary
    func leaveFamily(familyId: String) async throws
    func myFamilies() async throws -> [FamilySummary]
    /// Today plus the previous days, keyed by Nepal day. Each write replaces
    /// that day's value.
    @discardableResult
    func syncSteps(days: [StepDay]) async throws -> SyncStepsResult
    func deleteMyAccount() async throws

    func familyToday(familyId: String) async throws -> FamilyToday
    /// Monday to Sunday of the current Nepal week.
    func familyWeek(familyId: String) async throws -> FamilyWeek
    /// Live `familyToday`: the current value first, then every change. Ends
    /// when the caller stops listening.
    func familyTodayUpdates(familyId: String) -> AsyncStream<FamilyToday>
}

/// What the Me edit screen saves in one go.
struct ProfileUpdate: Hashable, Sendable {
    var name: String
    /// Typed by the person; "" clears it.
    var city: String
    /// "YYYY-MM-DD", or `nil` to clear it.
    var birthday: String?
}

/// Sign in with Apple and the session that follows.
protocol AuthService: Sendable {
    var currentUser: AppUser? { get async }
    /// `identityToken` and `authorizationCode` come from
    /// `ASAuthorizationAppleIDCredential`. The backend needs the code to revoke
    /// the Apple token when the account is deleted. `fullName` is only sent by
    /// Apple on the very first sign-in. `timeZone` is the phone's (an IANA
    /// identifier), stored for information only.
    func signInWithApple(identityToken: String, authorizationCode: String, fullName: PersonNameComponents?, timeZone: String) async throws -> AppUser
    /// When `needsName`: the first name the person typed
    /// (`updateProfile({name})`, then `me()`).
    func updateName(_ name: String) async throws -> AppUser
    /// The Me edit screen: name, city and birthday together
    /// (`updateProfile`, then `me()`). An empty city clears it; a `nil`
    /// birthday clears it.
    func updateProfile(_ profile: ProfileUpdate) async throws -> AppUser
    /// Uploads an already-downscaled JPEG and makes it the person's photo
    /// (`generateAvatarUploadUrl`, upload, `setAvatar`, then `me()`).
    /// `userId` is the account signed in when the person started the photo
    /// action; the server refuses the change for any other account.
    func setPhoto(jpeg: Data, userId: String) async throws -> AppUser
    /// `removeAvatar`, then `me()`. `userId` as for `setPhoto`.
    func removePhoto(userId: String) async throws -> AppUser
    /// The phone moved time zone since it was stored: `updateProfile({timezone})`.
    func updateTimeZone(_ identifier: String) async throws
    func signOut() async
    /// Forgets the local session once the backend has deleted the account
    /// (`FamilyService.deleteMyAccount`).
    func deleteAccount() async throws
}

extension EnvironmentValues {
    @Entry var familyService: any FamilyService = MockFamilyService.preview
    @Entry var authService: any AuthService = MockAuthService.preview
}
