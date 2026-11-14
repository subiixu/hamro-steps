import Foundation
import Testing
@testable import HamroSteps

@MainActor
struct HomeModelTests {
    /// `familyToday` as the backend sends it: members out of order, a null
    /// name and null steps.
    private static let json = """
    {
      "family": {"familyId": "f1", "name": "Thapa Family", "dailyGoal": 50000, "inviteCode": "K7M2QX",
                 "organiserId": "u1", "memberCount": 4, "isFull": false},
      "day": "2026-11-14", "goal": 50000, "total": 61000, "percent": 122,
      "members": [
        {"userId": "u3", "name": "Buwa", "avatarColor": "#4F74C9", "position": 2, "isOrganiser": false, "steps": 40000, "lastSyncedAt": 1794000000000, "status": null},
        {"userId": "u1", "name": "Priya", "avatarColor": "#E07A3F", "position": 0, "isOrganiser": true, "steps": 1000, "lastSyncedAt": 1794000000000, "status": null},
        {"userId": "u4", "name": null, "avatarColor": "#C28A1E", "position": 3, "isOrganiser": false, "steps": null, "lastSyncedAt": null, "status": null},
        {"userId": "u2", "name": "Aama", "avatarColor": "#2C9A76", "position": 1, "isOrganiser": false, "steps": 20000, "lastSyncedAt": 1794000000000, "status": null}
      ]
    }
    """

    private func decoded() throws -> FamilyToday {
        try JSONDecoder().decode(FamilyToday.self, from: Data(Self.json.utf8))
    }

    @Test func focusEventIsHandedOutOnce() {
        let home = HomeModel(service: MockFamilyService.sample(signedIn: true), defaults: TestTime.defaults())
        #expect(home.takeFocus() == nil)
        home.focus(eventId: "e_1")
        #expect(home.focusEventId == "e_1")
        #expect(home.takeFocus() == "e_1")
        #expect(home.focusEventId == nil)
        #expect(home.takeFocus() == nil)
        // A newer tap replaces one not yet shown.
        home.focus(eventId: "e_2")
        home.focus(eventId: "e_3")
        #expect(home.takeFocus() == "e_3")
    }

    @Test func fixedOrderByPositionNeverBySteps() async throws {
        let today = try decoded()
        let home = HomeModel(service: StubFamilyService(today: ["f1": today]), defaults: TestTime.defaults())
        await home.update(families: [today.family])
        #expect(home.members.map(\.userId) == ["u1", "u2", "u3", "u4"])
    }

    @Test func notSyncedStaysNilNotZero() async throws {
        let today = try decoded()
        let home = HomeModel(service: StubFamilyService(today: ["f1": today]), defaults: TestTime.defaults())
        await home.update(families: [today.family])
        let unsynced = try #require(home.members.last)
        #expect(unsynced.steps == nil)
        #expect(unsynced.lastSynced == nil)
        #expect(unsynced.name == "")
    }

    @Test func percentAndRingGoPast100WithoutCapping() async throws {
        let today = try decoded()
        let home = HomeModel(service: StubFamilyService(today: ["f1": today]), defaults: TestTime.defaults())
        await home.update(families: [today.family])
        #expect(home.phase == .loaded)
        #expect(home.percent == 122)
        #expect(home.ringFraction == 1.22)
        #expect(home.isGoalReached)
        #expect(home.isOrganiser("u1"))
        #expect(!home.isOrganiser("u2"))
    }

    @Test func percentUnderGoalAndZeroGoalIsSafe() async throws {
        var today = try decoded()
        today.total = 12_500
        today.percent = 25
        var home = HomeModel(service: StubFamilyService(today: ["f1": today]), defaults: TestTime.defaults())
        await home.update(families: [today.family])
        #expect(home.ringFraction == 0.25)
        #expect(!home.isGoalReached)

        today.goal = 0
        home = HomeModel(service: StubFamilyService(today: ["f1": today]), defaults: TestTime.defaults())
        await home.update(families: [today.family])
        #expect(home.ringFraction == 0)
        #expect(!home.isGoalReached)
    }

    @Test func switchingFamiliesLoadsTheOtherFamilyAndRemembersIt() async throws {
        let service = MockFamilyService.sample(signedIn: true)
        let defaults = TestTime.defaults()
        let home = HomeModel(service: service, defaults: defaults)
        let families = try await service.myFamilies()
        #expect(families.map(\.familyId) == ["f_thapa", "f_cousins"])

        await home.update(families: families)
        #expect(home.showsSwitcher)
        #expect(home.today?.family.familyId == "f_thapa")
        #expect(home.members.count == 5)
        #expect(home.members.filter { $0.steps == nil }.map(\.name) == ["Bikash"])
        #expect(home.week.count == 7)

        await home.select("f_cousins")
        #expect(home.today?.family.familyId == "f_cousins")
        #expect(home.members.map(\.name) == ["Rohan", "Priya", "Anju"])
        #expect(home.goal == 30_000)

        // A new launch picks up where the person left off.
        let relaunched = HomeModel(service: service, defaults: defaults)
        await relaunched.update(families: families)
        #expect(relaunched.today?.family.familyId == "f_cousins")
    }

    @Test func leavingTheSelectedFamilyFallsBackToTheFirst() async throws {
        let service = MockFamilyService.sample(signedIn: true)
        let home = HomeModel(service: service, defaults: TestTime.defaults())
        await home.update(families: try await service.myFamilies())
        await home.select("f_cousins")
        try await service.leaveFamily(familyId: "f_cousins")
        await home.update(families: try await service.myFamilies())
        #expect(home.today?.family.familyId == "f_thapa")
        #expect(!home.showsSwitcher)
    }

    @Test func liveUpdatesArriveAfterASync() async throws {
        let service = MockFamilyService.sample(signedIn: true)
        let home = HomeModel(service: service, defaults: TestTime.defaults())
        await home.update(families: try await service.myFamilies())
        let before = home.total
        let listening = Task { await home.listen() }
        defer { listening.cancel() }

        let today = NepalDay.string(for: .now)
        try await service.syncSteps(days: [StepDay(day: today, steps: 10_240)])
        for _ in 0..<100 where home.total == before { try await Task.sleep(for: .milliseconds(10)) }
        #expect(home.total == before - 5_240 + 10_240)
        #expect(home.week.last { $0.day == today }?.total == home.total)
    }
}

@MainActor
struct SessionStoreTests {
    private static let user = AppUser(userId: "u1", name: "Priya", needsName: false, avatarColor: "#E07A3F", timezone: nil, lastSyncedAt: nil)

    @Test func deleteAccountDeletesOnTheBackendThenForgetsTheSession() async throws {
        let service = StubFamilyService()
        let auth = StubAuthService(user: Self.user)
        let session = SessionStore(auth: auth, service: service, defaults: TestTime.defaults())
        await session.start()
        #expect(session.user != nil)

        try await session.deleteAccount()

        #expect(await service.calls.contains("deleteMyAccount"))
        #expect(await auth.calls == ["deleteAccount"])
        #expect(session.user == nil)
        #expect(session.route == .welcome)
    }

    @Test func failedDeleteKeepsThePersonSignedIn() async throws {
        let service = StubFamilyService(deleteError: .unavailable("offline"))
        let auth = StubAuthService(user: Self.user)
        let session = SessionStore(auth: auth, service: service, defaults: TestTime.defaults())
        await session.start()

        await #expect(throws: FamilyServiceError.unavailable("offline")) { try await session.deleteAccount() }

        #expect(await auth.calls.isEmpty)
        #expect(session.user?.userId == "u1")
    }

    @Test func deleteAccountWithTheMockBackendRemovesEverything() async throws {
        let backend = MockFamilyService.sample(signedIn: true)
        let session = SessionStore(auth: MockAuthService(backend: backend, defaults: nil), service: backend, defaults: TestTime.defaults())
        await session.start()
        #expect(session.families.count == 2)

        try await session.deleteAccount()

        #expect(session.route == .welcome)
        #expect(await backend.currentUser == nil)
        await #expect(throws: FamilyServiceError.notAuthenticated) { try await backend.myFamilies() }
    }

    @Test func signInPassesTheAuthorizationCodeAndTimeZone() async throws {
        let backend = MockFamilyService.sample(signedIn: false)
        let auth = MockAuthService(backend: backend, defaults: nil)
        let session = SessionStore(auth: auth, service: backend, defaults: TestTime.defaults())
        await session.start()
        #expect(session.route == .welcome)

        try await session.signIn(identityToken: "token", authorizationCode: "code-123", fullName: nil)

        let received = try #require(await auth.lastSignIn)
        #expect(received.authorizationCode == "code-123")
        #expect(received.timeZone == TimeZone.current.identifier)
        #expect(session.route == .health)
        session.finishHealthOnboarding()
        #expect(session.route == .main)
    }

    @Test func newPersonIsAskedForANameThenToCreateOrJoin() async throws {
        let backend = MockFamilyService.sample(signedIn: true, newUser: true)
        let defaults = TestTime.defaults()
        let session = SessionStore(auth: MockAuthService(backend: backend, defaults: nil), service: backend, defaults: defaults)
        await session.start()
        #expect(session.route == .askName)
        try await session.saveName("  Aama ")
        #expect(session.user?.name == "Aama")
        session.finishHealthOnboarding()
        #expect(session.route == .setup)
    }
}
