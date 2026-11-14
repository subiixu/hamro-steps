import SwiftUI
import UIKit

@main
struct HamroStepsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.session)
                .environment(delegate.stepSync)
                .environment(delegate.home)
                .environment(\.familyService, delegate.services.family)
                .environment(\.authService, delegate.services.auth)
                .environment(\.activityService, delegate.services.activity)
                .environment(\.now, delegate.services.now)
                .tint(.accent)
        }
    }
}

/// Owns the services and the long-lived models, and registers HealthKit
/// background delivery at launch, as Apple requires.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let services = AppLaunch.services()
    lazy var session = SessionStore(auth: services.auth, service: services.family)
    lazy var stepSync = StepSync(source: services.steps, service: services.family)
    lazy var home = HomeModel(service: services.family)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
}

/// The services the app runs on. This phase always uses the in-memory mocks;
/// the Convex phase swaps `family`, `auth` and `activity` here and nowhere else.
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
enum AppLaunch {
    enum Screen: String {
        case welcome, name, health, setup
        case createName = "create-name"
        case createGoal = "create-goal"
        case invite, join, home, settings, me
    }

    static func services() -> AppServices {
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
        return AppServices(
            family: family,
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

/// Temporary, until the mock activity service knows the mock families: the
/// mock only answers for its own sample family, so every family's feed reads
/// from that one. Goes when Convex lands.
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
