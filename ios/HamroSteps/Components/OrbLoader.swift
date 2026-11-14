import SwiftUI
import ThinkingOrbsKit

/// The one loading indicator in the app (project rule: Thinking Orbs, never
/// `ProgressView`). Pick the orb state that matches the activity.
struct OrbLoader: View {
    enum Activity {
        case loadingFamily
        case syncingSteps
        case connectingHealth
        case signingIn
        case saving
        case joining
        case deleting

        var orbState: OrbState {
            switch self {
            case .loadingFamily, .syncingSteps: .working
            case .connectingHealth, .signingIn, .joining: .connecting
            case .saving, .deleting: .working
            }
        }

        var message: LocalizedStringKey {
            switch self {
            case .loadingFamily: "Getting your family's steps…"
            case .syncingSteps: "Sending your steps…"
            case .connectingHealth: "Connecting to Apple Health…"
            case .signingIn: "Signing you in…"
            case .saving: "Saving…"
            case .joining: "Joining your family…"
            case .deleting: "Deleting your account…"
            }
        }
    }

    var activity: Activity = .loadingFamily
    var compact = false

    var body: some View {
        if compact {
            ThinkingOrb(state: activity.orbState, size: .px20)
                .accessibilityLabel(Text(activity.message))
        } else {
            VStack(spacing: 16) {
                ThinkingOrb(state: activity.orbState, size: .px64)
                Text(activity.message)
                    .font(.body)
                    .foregroundStyle(.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        OrbLoader(activity: .loadingFamily)
        OrbLoader(activity: .connectingHealth)
        OrbLoader(compact: true)
    }
    .padding()
}
