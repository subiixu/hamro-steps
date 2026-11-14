import SwiftUI

/// Shown once after sign-in. Explains in plain words why steps are needed
/// (Apple requires it, and parents need to know), then shows HealthKit's own
/// sheet. We move on whatever the person picks: a read denial is invisible.
struct HealthPermissionView: View {
    var onFinished: () -> Void

    @Environment(StepSync.self) private var stepSync
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Icon.health
                    .size(56)
                    .foregroundStyle(.accent)
                    .frame(width: 112, height: 112)
                    .background(Color.accent.opacity(0.14), in: .circle)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)

                Text("Share your steps with your family")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 16) {
                    reason("Your phone already counts your steps in Apple Health.")
                    reason("Hamro Steps adds them to your family's total for the day, so nobody types anything.")
                    reason("Your family sees only your step total for each day. Never where you are.")
                    reason("We only read steps. We never change your Health data, and never sell it or use it for ads.")
                }

                if !stepSync.isHealthAvailable {
                    Notice(text: String(localized: "Apple Health isn't available on this device, so your steps can't be shared from it. You can still follow your family."))
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if isConnecting {
                    OrbLoader(activity: .connectingHealth)
                } else if stepSync.isHealthAvailable {
                    PrimaryButton(title: "Allow step count") { connect() }
                    Text("On the next screen, turn on Steps, then tap Allow.")
                        .font(.footnote)
                        .foregroundStyle(.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Not now") { onFinished() }
                        .font(.body)
                        .foregroundStyle(.secondaryText)
                } else {
                    PrimaryButton(title: "Continue") { onFinished() }
                }
            }
            .padding(24)
            .background(.canvas)
        }
        .background(.canvas)
    }

    private func reason(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon.tick.size(22).foregroundStyle(.goal).padding(.top, 2)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connect() {
        isConnecting = true
        Task {
            await stepSync.connectHealth()
            isConnecting = false
            onFinished()
        }
    }
}

#Preview {
    HealthPermissionView {}
        .environment(StepSync(source: MockStepSource.sampleWeek(), service: MockFamilyService.preview))
}
