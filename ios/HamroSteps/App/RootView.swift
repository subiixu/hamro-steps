import SwiftUI

/// First launch shows "Connect Apple Health"; after that, the three tabs.
struct RootView: View {
    @AppStorage("healthOnboardingDone") private var onboardingDone = false
    @Environment(StepStore.self) private var steps
    @Environment(\.scenePhase) private var scenePhase

    private var showOnboarding: Bool {
        AppLaunch.forcedOnboarding ?? !onboardingDone
    }

    var body: some View {
        Group {
            if showOnboarding {
                ConnectHealthView {
                    onboardingDone = true
                }
            } else {
                MainTabView()
            }
        }
        .background(.canvas)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !showOnboarding else { return }
            Task { await steps.refresh() }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab {
                TodayView()
            } label: {
                Label { Text("Today") } icon: { Icon.home.image }
            }
            Tab {
                FamilyView()
            } label: {
                Label { Text("Family") } icon: { Icon.family.image }
            }
            Tab {
                MeView()
            } label: {
                Label { Text("Me") } icon: { Icon.profile.image }
            }
        }
    }
}

#Preview("Tabs") {
    MainTabView()
        .environment(StepStore(source: MockStepSource.sampleWeek()))
}
