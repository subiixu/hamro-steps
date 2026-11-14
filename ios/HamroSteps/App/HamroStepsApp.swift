import SwiftUI

@main
struct HamroStepsApp: App {
    @State private var steps = StepStore(source: AppLaunch.stepSource())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(steps)
                .tint(.accent)
        }
    }
}

/// Picks the step source. Debug builds accept launch arguments so the
/// simulator can show each state without HealthKit:
///   -mockSteps          sample week, onboarding skipped
///   -mockStepsLoading   never finishes loading (shows the orb)
///   -showOnboarding     always show "Connect Apple Health" first
enum AppLaunch {
    static func stepSource() -> any StepSource {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-mockStepsLoading") { return MockStepSource(delay: .seconds(3600)) }
        if args.contains("-mockSteps") { return MockStepSource.sampleWeek() }
        #endif
        return HealthKitStepSource()
    }

    static var forcedOnboarding: Bool? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-showOnboarding") { return true }
        if args.contains("-mockSteps") || args.contains("-mockStepsLoading") { return false }
        #endif
        return nil
    }
}
