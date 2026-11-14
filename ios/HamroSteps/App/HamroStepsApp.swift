import SwiftUI
import UIKit
import UserNotifications

@main
struct HamroStepsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.session)
                .environment(delegate.stepSync)
                .environment(delegate.home)
                .environment(delegate.push)
                .environment(delegate.pushInbox)
                .environment(\.familyService, delegate.services.family)
                .environment(\.authService, delegate.services.auth)
                .environment(\.activityService, delegate.services.activity)
                .environment(\.now, delegate.services.now)
                .tint(.accent)
                // Light mode only (also UIUserInterfaceStyle in project.yml).
                .preferredColorScheme(.light)
        }
    }
}

/// Owns the services and the long-lived models, registers HealthKit
/// background delivery at launch, as Apple requires, and is the system's
/// door for push: the APNs token and notification taps.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let services = AppLaunch.services()
    lazy var push = PushRegistrar(activity: services.activity, authorizer: AppLaunch.pushAuthorizer())
    let pushInbox = PushInbox()
    lazy var session = SessionStore(auth: services.auth, service: services.family, push: push)
    lazy var stepSync = StepSync(source: services.steps, service: services.family)
    lazy var home = HomeModel(service: services.family)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let home = home
        stepSync.onSynced = { await home.syncFinished() }
        if let healthKit = services.steps as? HealthKitStepSource {
            let sync = stepSync
            healthKit.startBackgroundDelivery { done in
                Task { @MainActor in
                    await sync.sync()
                    done()
                }
            }
        }
        return true
    }

    // MARK: Push

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let push = push
        Task { await push.didReceive(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Simulator or no network: nothing to send; the next launch tries again.
    }

    /// In the foreground: still show it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let payload = PushRouter.payload(from: response.notification.request.content.userInfo)
        await MainActor.run { pushInbox.received(payload) }
    }
}

/// The services the app runs on: Convex, or the in-memory mocks for a Debug
/// mock launch (see `AppLaunch.services()`).
struct AppServices {
    let family: any FamilyService
    let auth: any AuthService
    let steps: any StepSource
    let activity: any ActivityService
    /// The one clock for walk timers and status expiry, shared by the mocks
    /// and the views, so sample walks and screenshots agree.
    let now: @Sendable () -> Date
}

extension EnvironmentValues {
    @Entry var activityService: any ActivityService = MockActivityService()
    /// The current time; read it instead of `Date.now` in activity views.
    @Entry var now: @Sendable () -> Date = { .now }
}

/// Debug-only launch arguments for the simulator and screenshots:
///   -mockSteps            sample week instead of HealthKit
///   -mockStepsLoading     step reads never finish
///   -signedOut            start at Welcome
///   -newUser              sign in with no name and no families
///   -screen <name>        open one screen directly: welcome, name, health,
///                         setup, create-name, create-goal, invite, join,
///                         home, settings, me
///   -homeState <state>    with the mocks, for Home screenshots: `walking`
///                         (you're out on a walk) or `goal` (goal reached)
///   -homeScroll <where>   open Home scrolled to `center` or `bottom`
/// `-signedOut`, `-newUser` and `-screen` run on the in-memory mocks; without
/// them the app runs on Convex.
enum AppLaunch {
    enum Screen: String {
        case welcome, name, health, setup
        case createName = "create-name"
        case createGoal = "create-goal"
        case invite, join, home, settings, me
    }

    /// Convex (auth, family and activity) unless this is a Debug mock launch
    /// (`-signedOut`, `-newUser` or `-screen`) or the Convex URLs are missing,
    /// which falls back to the mocks.
    static func services() -> AppServices {
        if !isMockLaunch, let config = ConvexConfig() {
            let convex = ConvexServices.live(config: config)
            return AppServices(
                family: convex.family,
                auth: convex.auth,
                steps: stepSource(),
                activity: convex.activity,
                now: { .now }
            )
        }
        return mockServices()
    }

    /// A Debug launch with an argument that only makes sense against the mocks.
    static var isMockLaunch: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-signedOut") || args.contains("-newUser") || screen != nil
        #else
        return false
        #endif
    }

    static func mockServices() -> AppServices {
        let defaults = UserDefaults.standard
        var signedIn = defaults.bool(forKey: MockAuthService.signedInKey)
        var newUser = false
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-signedOut") { signedIn = false }
        if args.contains("-newUser") { newUser = true; signedIn = true }
        if let screen {
            signedIn = screen != .welcome
            newUser = screen == .name
            defaults.set(screen != .health, forKey: "healthOnboardingDone")
            defaults.removeObject(forKey: "home.selectedFamilyId")
        }
        #endif
        let now: @Sendable () -> Date = { .now }
        let family = MockFamilyService.sample(signedIn: signedIn, newUser: newUser, delay: .milliseconds(350), now: now)
        #if DEBUG
        let shown = HomeStateFamily.wrap(family, now: now)
        #else
        let shown: any FamilyService = family
        #endif
        return AppServices(
            family: shown,
            auth: MockAuthService(backend: family, defaults: defaults),
            steps: stepSource(),
            activity: SampleFamilyActivity(MockActivityService(now: now, latency: .milliseconds(350))),
            now: now
        )
    }

    static func stepSource() -> any StepSource {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-mockStepsLoading") { return MockStepSource(delay: .seconds(3600)) }
        if args.contains("-mockSteps") { return MockStepSource.sampleWeek(calendar: NepalDay.calendar) }
        #endif
        return HealthKitStepSource()
    }

    /// The system's notification prompt, except on a Debug `-screen home`
    /// launch, where it would sit over the Home screenshots.
    static func pushAuthorizer() -> any PushAuthorizer {
        #if DEBUG
        if screen == .home { return SilentPushAuthorizer() }
        #endif
        return SystemPushAuthorizer()
    }

    /// Debug `-homeScroll center|bottom`: where Home opens scrolled to, for
    /// screenshots of the lower tiles. `nil` (the top) otherwise.
    static var homeScrollAnchor: UnitPoint? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-homeScroll"), args.indices.contains(index + 1) {
            switch args[index + 1] {
            case "center": return .center
            case "bottom": return .bottom
            default: return nil
            }
        }
        #endif
        return nil
    }

    static var screen: Screen? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-screen"), args.indices.contains(index + 1) {
            return Screen(rawValue: args[index + 1])
        }
        #endif
        return nil
    }
}

/// For the mock launches only: the mock activity service answers for its own
/// sample family, so every mock family's feed reads from that one.
struct SampleFamilyActivity: ActivityService {
    let base: MockActivityService
    init(_ base: MockActivityService) { self.base = base }

    func startWalk() async throws -> WalkStart { try await base.startWalk() }
    func stopWalk() async throws { try await base.stopWalk() }
    func setStatus(_ input: StatusInput) async throws { try await base.setStatus(input) }
    func clearStatus() async throws { try await base.clearStatus() }
    func feed(familyId: String) async throws -> [FeedEvent] {
        try await base.feed(familyId: MockActivityService.familyId)
    }
    func react(eventId: String, emoji: Reaction) async throws { try await base.react(eventId: eventId, emoji: emoji) }
    func notificationPrefs() async throws -> NotificationPrefs { try await base.notificationPrefs() }
    func setNotificationPrefs(_ patch: NotificationPrefsPatch) async throws { try await base.setNotificationPrefs(patch) }
    func registerDevice(apnsToken: String, environment: APNsEnvironment) async throws {
        try await base.registerDevice(apnsToken: apnsToken, environment: environment)
    }
    func unregisterDevice(apnsToken: String) async throws { try await base.unregisterDevice(apnsToken: apnsToken) }
}

#if DEBUG
/// `-screen home`: never asks for notifications, so no prompt covers Home.
struct SilentPushAuthorizer: PushAuthorizer {
    func status() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization() async -> Bool { false }
    func registerForRemoteNotifications() {}
}

/// Debug screenshots only (`-homeState walking|goal` on a mock launch): shows
/// the sample family with the signed-in user out walking, or with today's
/// steps past the goal. Everything else goes straight to the mock.
struct HomeStateFamily: FamilyService {
    enum State: String, Sendable { case walking, goal }

    let base: any FamilyService
    let state: State
    /// When the pretend walk started, fixed at launch so the timer runs.
    let walkStart: Date

    static func wrap(_ base: any FamilyService, now: @Sendable () -> Date) -> any FamilyService {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-homeState"), args.indices.contains(index + 1),
              let state = State(rawValue: args[index + 1]) else { return base }
        return HomeStateFamily(base: base, state: state, walkStart: now().addingTimeInterval(-12 * 60))
    }

    func adjust(_ today: FamilyToday) -> FamilyToday {
        var today = today
        switch state {
        case .walking:
            for index in today.members.indices where today.members[index].userId == MockFamilyService.sampleUserId {
                today.members[index].walkingSince = ActivityTime.millis(walkStart)
                today.members[index].walkEndsAt = ActivityTime.millis(walkStart.addingTimeInterval(120 * 60))
            }
        case .goal:
            var added = 0
            for index in today.members.indices {
                guard let steps = today.members[index].steps else { continue }
                let more = steps * 4 / 5
                today.members[index].steps = steps + more
                added += more
            }
            today.total += added
            today.percent = today.goal > 0 ? today.total * 100 / today.goal : 0
        }
        return today
    }

    func familyToday(familyId: String) async throws -> FamilyToday {
        adjust(try await base.familyToday(familyId: familyId))
    }

    func familyTodayUpdates(familyId: String) -> AsyncStream<FamilyToday> {
        let upstream = base.familyTodayUpdates(familyId: familyId)
        let adjust = self.adjust
        return AsyncStream { continuation in
            let task = Task {
                for await today in upstream { continuation.yield(adjust(today)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func familyWeek(familyId: String) async throws -> FamilyWeek {
        var week = try await base.familyWeek(familyId: familyId)
        if state == .goal, let index = week.days.firstIndex(where: { $0.day == week.today }) {
            week.days[index].hit = true
            week.days[index].total = max(week.days[index].total, week.days[index].goal)
        }
        return week
    }

    func createFamily(name: String, dailyGoal: Int) async throws -> FamilySummary {
        try await base.createFamily(name: name, dailyGoal: dailyGoal)
    }
    func previewInvite(code: String) async throws -> InvitePreview { try await base.previewInvite(code: code) }
    func joinFamily(code: String) async throws -> FamilySummary { try await base.joinFamily(code: code) }
    func regenerateInviteCode(familyId: String) async throws -> String { try await base.regenerateInviteCode(familyId: familyId) }
    func removeMember(familyId: String, userId: String) async throws { try await base.removeMember(familyId: familyId, userId: userId) }
    func updateFamily(familyId: String, name: String, dailyGoal: Int) async throws -> FamilySummary {
        try await base.updateFamily(familyId: familyId, name: name, dailyGoal: dailyGoal)
    }
    func leaveFamily(familyId: String) async throws { try await base.leaveFamily(familyId: familyId) }
    func myFamilies() async throws -> [FamilySummary] { try await base.myFamilies() }
    @discardableResult
    func syncSteps(days: [StepDay]) async throws -> SyncStepsResult { try await base.syncSteps(days: days) }
    func deleteMyAccount() async throws { try await base.deleteMyAccount() }
}
#endif
