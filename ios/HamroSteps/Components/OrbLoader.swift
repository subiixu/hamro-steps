import SwiftUI
import ThinkingOrbsKit

/// The one loading indicator in the app (project rule: Thinking Orbs, never
/// `ProgressView`). Pick the orb state that matches the activity.
struct OrbLoader: View {
    enum Activity {
        case readingSteps
        case connectingHealth

        var orbState: OrbState {
            switch self {
            case .readingSteps: .working
            case .connectingHealth: .connecting
            }
        }

        var message: LocalizedStringKey {
            switch self {
            case .readingSteps: "Counting your steps…"
            case .connectingHealth: "Connecting to Apple Health…"
            }
        }
    }

    var activity: Activity = .readingSteps
    var compact = false

    var body: some View {
        if compact {
            ThinkingOrb(state: activity.orbState, size: .px20)
                .accessibilityLabel(Text(activity.message))
        } else {
            VStack(spacing: 16) {
                ThinkingOrb(state: activity.orbState, size: .px64)
                Text(activity.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        OrbLoader(activity: .readingSteps)
        OrbLoader(activity: .connectingHealth)
        OrbLoader(compact: true)
    }
    .padding()
}
