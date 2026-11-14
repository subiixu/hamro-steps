import SwiftUI

/// Picks the screen from the session: Welcome → name → Health → create or
/// join → the two tabs. Syncs steps whenever the app comes to the front.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StepSync.self) private var stepSync
    @Environment(HomeModel.self) private var home
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let screen = AppLaunch.screen, session.isStarted {
                DebugScreen(screen: screen)
            } else {
                switch session.route {
                case .launching:
                    OrbLoader(activity: .loadingFamily)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .welcome:
                    WelcomeView()
                case .askName:
                    AskNameView()
                case .health:
                    HealthPermissionView { session.finishHealthOnboarding() }
                case .setup:
                    FamilySetupView(isFirstFamily: true) { family in
                        home.prefer(family.id)
                        Task { await session.refreshFamilies() }
                    }
                case .main:
                    MainTabView()
                }
            }
        }
        .background(.canvas)
        .animation(.default, value: session.route)
        .task {
            await session.start()
            await stepSync.refreshHealthStatus()
        }
        .task(id: session.families) {
            await home.update(families: session.families)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.user != nil else { return }
            // Back in the foreground: the Nepal day may have changed while away.
            Task { await home.refresh() }
            guard session.healthOnboardingDone else { return }
            Task { await stepSync.sync() }
        }
        .task(id: scenePhase == .active) {
            // Nepal midnight and clock changes, only while the app is active.
            guard scenePhase == .active else { return }
            await home.watchDayChanges(timeChanges: Self.significantTimeChanges())
        }
        .onChange(of: session.user?.id) { _, id in
            guard id != nil, session.healthOnboardingDone else { return }
            Task { await stepSync.sync() }
        }
    }

    /// Midnight passing on the phone, a time zone change or a clock change.
    private static func significantTimeChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(named: UIApplication.significantTimeChangeNotification) {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct MainTabView: View {
    enum TabID: Hashable { case home, me }

    @State private var selection: TabID = AppLaunch.screen == .me ? .me : .home

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: TabID.home) {
                HomeView()
            } label: {
                Label { Text("Home") } icon: { Icon.home.image }
            }
            Tab(value: TabID.me) {
                MeView()
            } label: {
                Label { Text("Me") } icon: { Icon.profile.image }
            }
        }
    }
}

/// Debug builds: `-screen <name>` opens one screen with sample data, for
/// screenshots without tapping through onboarding.
private struct DebugScreen: View {
    let screen: AppLaunch.Screen
    @Environment(SessionStore.self) private var session

    var body: some View {
        switch screen {
        case .welcome: WelcomeView()
        case .name: AskNameView()
        case .health: HealthPermissionView {}
        case .setup: FamilySetupView(isFirstFamily: true) { _ in }
        case .createName: NavigationStack { CreateFamilyNameView { _ in } }
        case .createGoal: NavigationStack { CreateGoalView(familyName: "Thapa Family") { _ in } }
        case .invite:
            NavigationStack {
                InviteCodeView(family: FamilySummary(familyId: "f_thapa", name: "Thapa Family", dailyGoal: 50_000, inviteCode: "K7M2QX", organiserId: "u_priya", memberCount: 5, isFull: false)) {}
            }
        case .join: NavigationStack { JoinFamilyView { _ in } }
        case .home, .settings, .me: MainTabView()
        }
    }
}
