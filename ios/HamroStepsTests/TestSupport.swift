import Foundation
@testable import HamroSteps

enum TestTime {
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static func date(_ zone: String, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Each test gets its own defaults, so nothing leaks between tests.
    static func defaults() -> UserDefaults {
        let name = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

/// A `FamilyService` that returns canned values and records calls, for
/// shapes the mock backend never produces (shuffled order) and failures.
actor StubFamilyService: FamilyService {
    var today: [String: FamilyToday] = [:]
    var deleteError: FamilyServiceError?
    private(set) var calls: [String] = []

    init(today: [String: FamilyToday] = [:], deleteError: FamilyServiceError? = nil) {
        self.today = today
        self.deleteError = deleteError
    }

    private func fail<T>(_ name: String) throws -> T {
        calls.append(name)
        throw FamilyServiceError.unavailable("stub")
    }

    func createFamily(name: String, dailyGoal: Int) async throws -> FamilySummary { try fail("createFamily") }
    func previewInvite(code: String) async throws -> InvitePreview { try fail("previewInvite") }
    func joinFamily(code: String) async throws -> FamilySummary { try fail("joinFamily") }
    func regenerateInviteCode(familyId: String) async throws -> String { try fail("regenerateInviteCode") }
    func removeMember(familyId: String, userId: String) async throws { calls.append("removeMember") }
    func updateFamily(familyId: String, name: String, dailyGoal: Int) async throws -> FamilySummary { try fail("updateFamily") }
    func leaveFamily(familyId: String) async throws { calls.append("leaveFamily") }
    func myFamilies() async throws -> [FamilySummary] {
        calls.append("myFamilies")
        return today.values.map(\.family).sorted { $0.familyId < $1.familyId }
    }
    func syncSteps(days: [StepDay]) async throws -> SyncStepsResult { try fail("syncSteps") }
    func deleteMyAccount() async throws {
        calls.append("deleteMyAccount")
        if let deleteError { throw deleteError }
    }
    func familyToday(familyId: String) async throws -> FamilyToday {
        calls.append("familyToday")
        guard let value = today[familyId] else { throw FamilyServiceError.notMember }
        return value
    }
    func familyWeek(familyId: String) async throws -> FamilyWeek {
        calls.append("familyWeek")
        return FamilyWeek(today: "2026-11-14", weekStart: "2026-11-09", startsAt: 0, days: [])
    }
    nonisolated func familyTodayUpdates(familyId: String) -> AsyncStream<FamilyToday> {
        AsyncStream { $0.finish() }
    }
}

/// An `AuthService` that records calls.
actor StubAuthService: AuthService {
    private(set) var calls: [String] = []
    var user: AppUser?

    init(user: AppUser?) { self.user = user }

    var currentUser: AppUser? { get async { user } }
    func signInWithApple(identityToken: String, authorizationCode: String, fullName: PersonNameComponents?, timeZone: String) async throws -> AppUser {
        calls.append("signInWithApple")
        return user!
    }
    func updateName(_ name: String) async throws -> AppUser { user! }
    func signOut() async { calls.append("signOut"); user = nil }
    func deleteAccount() async throws { calls.append("deleteAccount"); user = nil }
}
