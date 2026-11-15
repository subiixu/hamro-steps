import Foundation
import Testing
import UserNotifications
@testable import HamroSteps

/// One ordered list of calls across the fakes below, so a test can check
/// what happened first.
final class PushCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func add(_ entry: String) { lock.withLock { entries.append(entry) } }
    var calls: [String] { lock.withLock { entries } }
}

/// Holds callers until opened, and ignores cancellation while it does,
/// like a network call that won't give up.
actor PushGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0

    func wait() async {
        arrivals += 1
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// The backend's side of push, with its real rules: device calls need a
/// signed-in caller, a token belongs to whoever registered it last, and
/// unregister only removes the caller's own token (notifications.ts).
final class FakePushBackend: @unchecked Sendable {
    private struct NotSignedIn: Error {}
    private let lock = NSLock()
    private var signedInAs: String?
    private var owners: [String: String]

    init(account: String? = "u_me", devices: [String: String] = [:]) {
        signedInAs = account
        owners = devices
    }

    var account: String? {
        get { lock.withLock { signedInAs } }
        set { lock.withLock { signedInAs = newValue } }
    }
    var devices: [String: String] { lock.withLock { owners } }

    /// A call carries the identity it was sent with, even if it lands
    /// after a sign-out or another sign-in (nil: refused, like requireUser).
    func register(_ token: String, as who: String?) throws -> String {
        try lock.withLock {
            guard let who else { throw NotSignedIn() }
            owners[token] = who
            return who
        }
    }

    func unregister(_ token: String, as who: String?) throws -> String {
        try lock.withLock {
            guard let who else { throw NotSignedIn() }
            if owners[token] == who { owners[token] = nil }
            return who
        }
    }
}

/// Records device calls against the fake backend; everything else is
/// unused here.
struct RecordingActivity: ActivityService {
    let log: PushCallLog
    let backend: FakePushBackend
    var unregisterDelay: Duration = .zero
    var fails = false
    /// Holds `registerDevice` before it lands, ignoring cancellation.
    var registerGate: PushGate?
    /// Holds only calls sent as this account (nil: every call).
    var gatedAccount: String?
    /// Holds `unregisterDevice` before it lands, ignoring cancellation.
    var unregisterGate: PushGate?

    private struct Down: Error {}

    func startWalk() async throws -> WalkStart { throw Down() }
    func stopWalk() async throws {}
    func setStatus(_ input: StatusInput) async throws {}
    func clearStatus() async throws {}
    func feed(familyId: String) async throws -> [FeedEvent] { [] }
    func react(eventId: String, emoji: Reaction) async throws {}
    func notificationPrefs() async throws -> NotificationPrefs { .defaults }
    func setNotificationPrefs(_ patch: NotificationPrefsPatch) async throws {}
    func registerDevice(apnsToken: String, environment: APNsEnvironment) async throws {
        let sentAs = backend.account
        if gatedAccount == nil || gatedAccount == sentAs { await registerGate?.wait() }
        if fails { log.add("register \(apnsToken) failed"); throw Down() }
        do {
            let who = try backend.register(apnsToken, as: sentAs)
            log.add("register \(apnsToken) \(environment.rawValue) as \(who)")
        } catch {
            log.add("register \(apnsToken) refused")
            throw error
        }
    }
    func unregisterDevice(apnsToken: String) async throws {
        let sentAs = backend.account
        await unregisterGate?.wait()
        try await Task.sleep(for: unregisterDelay)
        if fails { log.add("unregister \(apnsToken) failed"); throw Down() }
        do {
            let who = try backend.unregister(apnsToken, as: sentAs)
            log.add("unregister \(apnsToken) as \(who)")
        } catch {
            log.add("unregister \(apnsToken) refused")
            throw error
        }
    }
}

/// Signs the fake backend in and out. Signs in as `next`. Like the Convex
/// auth service, sign-out only clears the session once its call returns.
struct RecordingAuth: AuthService {
    let log: PushCallLog
    let backend: FakePushBackend
    var next = "u_other"
    /// Holds `signOut` before it clears the session, ignoring cancellation.
    var signOutGate: PushGate?

    private func user(_ id: String) -> AppUser {
        AppUser(userId: id, name: "Priya", needsName: false)
    }

    var currentUser: AppUser? { get async { backend.account.map(user) } }
    func signInWithApple(identityToken: String, authorizationCode: String, fullName: PersonNameComponents?, timeZone: String) async throws -> AppUser {
        backend.account = next
        log.add("signIn \(next)")
        return user(next)
    }
    func updateName(_ name: String) async throws -> AppUser { user(backend.account ?? next) }
    func updateProfile(_ profile: ProfileUpdate) async throws -> AppUser { user(backend.account ?? next) }
    func setPhoto(jpeg: Data, userId: String) async throws -> AppUser { user(backend.account ?? next) }
    func removePhoto(userId: String) async throws -> AppUser { user(backend.account ?? next) }
    func updateTimeZone(_ identifier: String) async throws {}
    func signOut() async {
        await signOutGate?.wait()
        log.add("signOut \(backend.account ?? "nobody")")
        backend.account = nil
    }
    func deleteAccount() async throws {
        log.add("deleteAccount \(backend.account ?? "nobody")")
        backend.account = nil
    }
}

@MainActor
final class FakeAuthorizer: PushAuthorizer {
    var current: UNAuthorizationStatus
    var grants: Bool
    private(set) var prompts = 0
    private(set) var registrations = 0

    init(_ status: UNAuthorizationStatus = .notDetermined, grants: Bool = true) {
        current = status
        self.grants = grants
    }

    func status() async -> UNAuthorizationStatus { current }
    func requestAuthorization() async -> Bool {
        prompts += 1
        current = grants ? .authorized : .denied
        return grants
    }
    func registerForRemoteNotifications() { registrations += 1 }
}

struct DeviceTokenTests {
    @Test func hexIsLowercaseTwoCharactersPerByte() {
        let token = Data([0x00, 0x0f, 0xab, 0xff, 0x10])
        #expect(DeviceToken.hex(token) == "000fabff10")
        #expect(DeviceToken.hex(Data()) == "")
    }

    @Test func debugBuildsUseSandboxOthersProduction() {
        #expect(DeviceToken.environment(isDebug: true) == .sandbox)
        #expect(DeviceToken.environment(isDebug: false) == .production)
        // Tests run a debug build.
        #expect(DeviceToken.currentEnvironment == .sandbox)
    }

    @Test func storeRemembersEveryTokenInOrder() {
        let store = DeviceTokenStore(defaults: TestTime.defaults())
        #expect(store.lastToken == nil)
        store.add("aa")
        store.add("bb")
        store.add("aa")
        #expect(store.tokens == ["bb", "aa"])
        #expect(store.lastToken == "aa")
        store.remove("aa")
        #expect(store.tokens == ["bb"])
        store.clear()
        #expect(store.tokens.isEmpty)
    }
}

struct PushRouterTests {
    @Test(arguments: [
        ("walk_started", PushPayload.Kind.walkStarted),
        ("family_100", .family100),
        ("reaction", .reaction),
        ("evening_nudge", .eveningNudge),
    ])
    func parsesEachType(raw: String, kind: PushPayload.Kind) {
        let payload = PushRouter.payload(from: ["type": raw, "familyId": "f_1", "eventId": "e_9", "aps": ["sound": "default"]])
        #expect(payload?.kind == kind)
        #expect(payload?.familyId == "f_1")
        // The nudge is about the family, not an event.
        #expect(payload?.eventId == (kind == .eveningNudge ? nil : "e_9"))
    }

    @Test func eventIdIsOptional() {
        let payload = PushRouter.payload(from: ["type": "family_100", "familyId": "f_1"])
        #expect(payload == PushPayload(kind: .family100, familyId: "f_1", eventId: nil))
    }

    @Test func unknownTypeIsNotOurs() {
        #expect(PushRouter.payload(from: ["type": "something_new", "familyId": "f_1"]) == nil)
        #expect(PushRouter.payload(from: ["familyId": "f_1"]) == nil)
    }

    @Test func missingFamilyIdIsNotOurs() {
        #expect(PushRouter.payload(from: ["type": "reaction", "eventId": "e_1"]) == nil)
        #expect(PushRouter.payload(from: ["type": "reaction", "familyId": ""]) == nil)
        #expect(PushRouter.payload(from: ["type": "reaction", "familyId": 42]) == nil)
    }

    @Test func routesToTheFamilyOnlyWhenAMember() {
        let payload = PushPayload(kind: .reaction, familyId: "f_1", eventId: "e_2")
        #expect(PushRouter.route(payload, familyIds: ["f_0", "f_1"]) == .family(id: "f_1", eventId: "e_2"))
        #expect(PushRouter.route(payload, familyIds: ["f_0"]) == .home)
        #expect(PushRouter.route(nil, familyIds: ["f_1"]) == .home)
    }

    @MainActor @Test func inboxHandsOverATapOnce() {
        let inbox = PushInbox()
        inbox.received(PushPayload(kind: .walkStarted, familyId: "f_1", eventId: nil))
        #expect(inbox.tapCount == 1)
        #expect(inbox.take(familyIds: ["f_1"]) == .family(id: "f_1", eventId: nil))
        #expect(inbox.pending == nil)
        #expect(inbox.take(familyIds: ["f_1"]) == .home)
        inbox.received(nil)
        #expect(inbox.tapCount == 2)
    }
}

/// Polls until `condition` holds or 2 s pass.
@MainActor
func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
}

@MainActor
struct PushRegistrarTests {
    let log = PushCallLog()
    let backend = FakePushBackend()

    func registrar(
        _ authorizer: FakeAuthorizer,
        activity: RecordingActivity? = nil,
        store: DeviceTokenStore? = nil,
        requestTimeout: Duration = .seconds(10)
    ) -> PushRegistrar {
        PushRegistrar(
            activity: activity ?? RecordingActivity(log: log, backend: backend),
            authorizer: authorizer,
            tokens: store ?? DeviceTokenStore(defaults: TestTime.defaults()),
            environment: .sandbox,
            requestTimeout: requestTimeout
        )
    }

    func signOut(_ push: PushRegistrar) async {
        let auth = RecordingAuth(log: log, backend: backend)
        await push.signOut { await auth.signOut() }
    }

    @Test func noPromptBeforeSignIn() async {
        let authorizer = FakeAuthorizer()
        let push = registrar(authorizer)
        await push.sessionChanged(signedIn: false, inFamily: false)
        await push.sessionChanged(signedIn: false, inFamily: true)
        #expect(authorizer.prompts == 0)
        #expect(authorizer.registrations == 0)
    }

    @Test func noPromptWhileSignedInWithoutAFamily() async {
        let authorizer = FakeAuthorizer()
        let push = registrar(authorizer)
        await push.sessionChanged(signedIn: true, inFamily: false)
        #expect(authorizer.prompts == 0)
        #expect(authorizer.registrations == 0)
    }

    @Test func promptsOnHomeThenRegisters() async {
        let authorizer = FakeAuthorizer()
        let push = registrar(authorizer)
        await push.sessionChanged(signedIn: true, inFamily: true)
        #expect(authorizer.prompts == 1)
        #expect(authorizer.registrations == 1)
    }

    @Test func deniedNeverRegisters() async {
        let authorizer = FakeAuthorizer(grants: false)
        let push = registrar(authorizer)
        await push.sessionChanged(signedIn: true, inFamily: true)
        await push.sessionChanged(signedIn: true, inFamily: true)
        #expect(authorizer.prompts == 1)
        #expect(authorizer.registrations == 0)
    }

    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral])
    func alreadyAllowedRegistersEveryLaunchWithoutPrompting(status: UNAuthorizationStatus) async {
        let authorizer = FakeAuthorizer(status)
        let push = registrar(authorizer)
        // Signed in, still in onboarding: no family yet, but already allowed.
        await push.sessionChanged(signedIn: true, inFamily: false)
        #expect(authorizer.prompts == 0)
        #expect(authorizer.registrations == 1)
    }

    @Test func tokenGoesToTheBackendAsHexAndIsRemembered() async {
        let authorizer = FakeAuthorizer(.authorized)
        let store = DeviceTokenStore(defaults: TestTime.defaults())
        let push = registrar(authorizer, store: store)
        await push.sessionChanged(signedIn: true, inFamily: true)
        await push.didReceive(token: Data([0xde, 0xad, 0xbe, 0xef]))
        #expect(log.calls == ["register deadbeef sandbox as u_me"])
        #expect(store.tokens == ["deadbeef"])
    }

    @Test func tokenAfterSignOutIsIgnored() async {
        let push = registrar(FakeAuthorizer(.authorized))
        await push.sessionChanged(signedIn: false, inFamily: false)
        await push.didReceive(token: Data([0x01]))
        #expect(log.calls.isEmpty)
        #expect(push.lastToken == nil)
    }

    @Test func signOutWithoutATokenJustSignsOut() async {
        let push = registrar(FakeAuthorizer(.authorized))
        await signOut(push)
        #expect(log.calls == ["signOut u_me"])
    }

    /// Each device call has its own timeout: a hung unregister is cancelled
    /// and sign-out carries on, so the queue can't hang.
    @Test func aHungRequestIsCutOffByItsTimeout() async {
        let store = DeviceTokenStore(defaults: TestTime.defaults())
        store.tokens = ["aa", "bb"]
        let activity = RecordingActivity(log: log, backend: backend, unregisterDelay: .seconds(30))
        let push = registrar(FakeAuthorizer(.authorized), activity: activity, store: store, requestTimeout: .milliseconds(200))
        let clock = ContinuousClock()
        let elapsed = await clock.measure { await signOut(push) }
        #expect(elapsed < .seconds(3))
        // Both unregisters were cancelled before landing; sign-out still ran.
        #expect(log.calls == ["signOut u_me"])
        #expect(backend.account == nil)
        #expect(store.tokens.isEmpty)
        #expect(push.hasUnfinishedSignOut == false)
    }

    @Test func withTimeoutReturnsTheResultInTime() async throws {
        let value = try await PushRegistrar.withTimeout(.seconds(5)) { 42 }
        #expect(value == 42)
        await #expect(throws: PushRequestTimeout.self) {
            try await PushRegistrar.withTimeout(.milliseconds(50)) { try await Task.sleep(for: .seconds(30)) }
        }
    }

    @Test func registrationInFlightAtSignOutIsUnregisteredAfterIt() async {
        let gate = PushGate()
        let push = registrar(FakeAuthorizer(.authorized), activity: RecordingActivity(log: log, backend: backend, registerGate: gate))
        await push.sessionChanged(signedIn: true, inFamily: true)
        let registering = Task { await push.didReceive(token: Data([0xab])) }
        while await gate.arrivals == 0 { await Task.yield() }
        // Sign-out starts while registerDevice is still on its way.
        let signingOut = Task { await signOut(push) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(log.calls.isEmpty)
        await gate.open()
        await signingOut.value
        await registering.value
        #expect(log.calls == ["register ab sandbox as u_me", "unregister ab as u_me", "signOut u_me"])
        #expect(backend.devices.isEmpty)
        #expect(push.lastToken == nil)
    }

    /// Token A is registering, token B is queued behind it, then sign-out.
    /// A must not stay linked to the departed account.
    @Test func everyTokenThatMayHaveReachedTheBackendIsUnregistered() async throws {
        let gate = PushGate()
        let store = DeviceTokenStore(defaults: TestTime.defaults())
        let push = registrar(FakeAuthorizer(.authorized), activity: RecordingActivity(log: log, backend: backend, registerGate: gate), store: store)
        await push.sessionChanged(signedIn: true, inFamily: true)
        let first = Task { await push.didReceive(token: Data([0xaa])) }
        while await gate.arrivals == 0 { await Task.yield() }
        let second = Task { await push.didReceive(token: Data([0xbb])) }
        try await eventually { store.tokens.count == 2 }
        let signingOut = Task { await signOut(push) }
        try await Task.sleep(for: .milliseconds(50))
        await gate.open()
        await signingOut.value
        await first.value
        await second.value
        // B was queued before sign-out, so it is never sent.
        #expect(log.calls == ["register aa sandbox as u_me", "unregister aa as u_me", "unregister bb as u_me", "signOut u_me"])
        #expect(backend.devices.isEmpty)
        #expect(store.tokens.isEmpty)
    }
}

@MainActor
struct PushSessionTests {
    let log = PushCallLog()
    let backend = FakePushBackend(devices: ["cafe01": "u_me"])

    func session(
        activity: RecordingActivity? = nil,
        auth: RecordingAuth? = nil,
        deleteError: FamilyServiceError? = nil
    ) -> (SessionStore, DeviceTokenStore, FakeAuthorizer, PushRegistrar) {
        let store = DeviceTokenStore(defaults: TestTime.defaults())
        store.add("cafe01")
        let authorizer = FakeAuthorizer(.authorized)
        let push = PushRegistrar(
            activity: activity ?? RecordingActivity(log: log, backend: backend),
            authorizer: authorizer,
            tokens: store,
            environment: .sandbox
        )
        let session = SessionStore(
            auth: auth ?? RecordingAuth(log: log, backend: backend),
            service: StubFamilyService(deleteError: deleteError),
            defaults: TestTime.defaults(),
            push: push
        )
        return (session, store, authorizer, push)
    }

    func signIn(_ session: SessionStore) async throws {
        try await session.signIn(identityToken: "id", authorizationCode: "code", fullName: nil)
    }

    @Test func unregistersBeforeSignOut() async {
        let (session, store, _, _) = session()
        await session.start()
        await session.signOut()
        #expect(log.calls == ["unregister cafe01 as u_me", "signOut u_me"])
        #expect(store.tokens.isEmpty)
        #expect(backend.devices.isEmpty)
        #expect(session.user == nil)
    }

    @Test func signOutStillHappensWhenUnregisterFails() async {
        let (session, store, _, _) = session(activity: RecordingActivity(log: log, backend: backend, fails: true))
        await session.start()
        await session.signOut()
        #expect(log.calls == ["unregister cafe01 failed", "signOut u_me"])
        #expect(store.tokens.isEmpty)
    }

    @Test func unregistersBeforeAccountDeletion() async throws {
        let (session, store, _, _) = session()
        await session.start()
        try await session.deleteAccount()
        #expect(log.calls == ["unregister cafe01 as u_me", "deleteAccount u_me"])
        #expect(store.tokens.isEmpty)
        #expect(session.user == nil)
    }

    @Test func failedDeletionRegistersThePhoneAgain() async {
        let (session, _, authorizer, _) = session(deleteError: .unavailable("down"))
        await session.start()
        await #expect(throws: FamilyServiceError.self) { try await session.deleteAccount() }
        #expect(log.calls == ["unregister cafe01 as u_me"])
        #expect(authorizer.registrations == 1)
        #expect(session.user != nil)
    }

    /// Account A's registration is suspended when A signs out and B signs
    /// in. B's work can't start until A's registration has finished and
    /// been cleaned up, so when B registers the same token, B keeps it.
    @Test func theLastAccountsRegistrationFinishesBeforeTheNextAccountRegisters() async throws {
        let gate = PushGate()
        let (session, store, _, push) = session(activity: RecordingActivity(log: log, backend: backend, registerGate: gate, gatedAccount: "u_me"))
        store.clear()
        await session.start()
        await push.sessionChanged(signedIn: true, inFamily: true)
        let registering = Task { await push.didReceive(token: Data([0xcd])) }
        while await gate.arrivals == 0 { await Task.yield() }

        let signingOut = Task { await session.signOut() }
        try await Task.sleep(for: .milliseconds(50))
        let signingIn = Task { try await signIn(session) }
        try await Task.sleep(for: .milliseconds(100))
        // Everything waits behind A's registration.
        #expect(log.calls.isEmpty)
        #expect(backend.account == "u_me")

        await gate.open()
        await registering.value
        await signingOut.value
        try await signingIn.value
        await push.sessionChanged(signedIn: true, inFamily: true)
        await push.didReceive(token: Data([0xcd]))
        #expect(log.calls == [
            "register cd sandbox as u_me",
            "unregister cd as u_me",
            "signOut u_me",
            "signIn u_other",
            "register cd sandbox as u_other",
        ])
        #expect(backend.devices["cd"] == "u_other")
        #expect(session.user?.userId == "u_other")
    }

    /// A slow backend sign-out can't be overtaken by the next sign-in:
    /// otherwise the old sign-out would clear the new account's session.
    @Test func aSuspendedSignOutCannotBeOvertakenByANewSignIn() async throws {
        let gate = PushGate()
        var auth = RecordingAuth(log: log, backend: backend)
        auth.signOutGate = gate
        let (session, _, _, _) = session(auth: auth)
        await session.start()

        let signingOut = Task { await session.signOut() }
        while await gate.arrivals == 0 { await Task.yield() }
        let signingIn = Task { try await signIn(session) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(log.calls == ["unregister cafe01 as u_me"])
        #expect(backend.account == "u_me")

        await gate.open()
        await signingOut.value
        try await signingIn.value
        #expect(log.calls == ["unregister cafe01 as u_me", "signOut u_me", "signIn u_other"])
        #expect(backend.account == "u_other")
        #expect(session.user?.userId == "u_other")
    }

    /// Deletion waits for a registration still on its way, then fails. The
    /// re-registration queues behind the cleanup, so the cleanup can't
    /// remove it.
    @Test func failedDeletionRegistersAgainAfterTheCleanup() async throws {
        let gate = PushGate()
        let (session, store, authorizer, push) = session(activity: RecordingActivity(log: log, backend: backend, registerGate: gate), deleteError: .unavailable("down"))
        store.clear()
        await session.start()
        await push.sessionChanged(signedIn: true, inFamily: true)
        let registering = Task { await push.didReceive(token: Data([0xcd])) }
        while await gate.arrivals == 0 { await Task.yield() }

        let deleting = Task { try await session.deleteAccount() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(log.calls.isEmpty)
        await gate.open()
        await registering.value
        await #expect(throws: FamilyServiceError.self) { try await deleting.value }
        #expect(authorizer.registrations == 2)
        // APNs answers the restore with the same token.
        await push.didReceive(token: Data([0xcd]))
        #expect(log.calls == ["register cd sandbox as u_me", "unregister cd as u_me", "register cd sandbox as u_me"])
        #expect(backend.devices["cd"] == "u_me")
        #expect(session.user != nil)
    }

    /// The app quit before a sign-out finished: the next launch finishes
    /// it, as that account, and starts signed out.
    @Test func unfinishedSignOutIsFinishedAtNextLaunch() async {
        let (session, store, _, push) = session()
        store.signOutPending = true
        await session.start()
        #expect(log.calls == ["unregister cafe01 as u_me", "signOut u_me"])
        #expect(session.user == nil)
        #expect(push.hasUnfinishedSignOut == false)
        #expect(backend.devices.isEmpty)
    }
}

@MainActor
struct PushTapTests {
    @Test func tapDuringOnboardingOpensItsFamilyOnceHomeShows() async throws {
        let backend = MockFamilyService.sample(signedIn: true)
        let session = SessionStore(auth: MockAuthService(backend: backend, defaults: nil), service: backend, defaults: TestTime.defaults())
        let home = HomeModel(service: backend, defaults: TestTime.defaults())
        await session.start()
        #expect(session.route == .health)
        await home.update(families: session.families)
        let other = try #require(session.families.last?.id)
        #expect(home.selectedFamilyId != other)

        let inbox = PushInbox()
        inbox.received(PushPayload(kind: .reaction, familyId: other, eventId: "e_1"))
        await inbox.open(session: session, home: home)
        // Still onboarding: the tap waits.
        #expect(inbox.pending != nil)
        #expect(home.selectedFamilyId != other)

        session.finishHealthOnboarding()
        #expect(session.route == .main)
        await inbox.open(session: session, home: home)
        #expect(inbox.pending == nil)
        #expect(home.selectedFamilyId == other)
        // The event the push was about waits for Home to bring it into view.
        #expect(home.takeFocus() == "e_1")
    }

    @Test func tapForAFamilyThePersonIsNotInLeavesHomeAsItWas() async throws {
        let backend = MockFamilyService.sample(signedIn: true)
        let defaults = TestTime.defaults()
        defaults.set(true, forKey: "healthOnboardingDone")
        let session = SessionStore(auth: MockAuthService(backend: backend, defaults: nil), service: backend, defaults: defaults)
        let home = HomeModel(service: backend, defaults: TestTime.defaults())
        await session.start()
        await home.update(families: session.families)
        let before = home.selectedFamilyId

        let inbox = PushInbox()
        inbox.received(PushPayload(kind: .walkStarted, familyId: "f_someone_else", eventId: nil))
        await inbox.open(session: session, home: home)
        #expect(inbox.pending == nil)
        #expect(home.selectedFamilyId == before)
        #expect(home.focusEventId == nil)
    }

    @Test func tapWithoutAnEventShowsTheFamilyWithNoFocus() async throws {
        let backend = MockFamilyService.sample(signedIn: true)
        let defaults = TestTime.defaults()
        defaults.set(true, forKey: "healthOnboardingDone")
        let session = SessionStore(auth: MockAuthService(backend: backend, defaults: nil), service: backend, defaults: defaults)
        let home = HomeModel(service: backend, defaults: TestTime.defaults())
        await session.start()
        await home.update(families: session.families)
        let other = try #require(session.families.last?.id)

        let inbox = PushInbox()
        inbox.received(PushPayload(kind: .walkStarted, familyId: other, eventId: nil))
        await inbox.open(session: session, home: home)
        #expect(home.selectedFamilyId == other)
        #expect(home.focusEventId == nil)
    }
}
