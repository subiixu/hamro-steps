import SwiftUI

/// Shown once after sign-in. Explains in plain words why steps are needed
/// (Apple requires it, and parents need to know), then shows HealthKit's own
/// sheet. We move on whatever the person picks: a read denial is invisible.
struct HealthPermissionView: View {
    var onFinished: () -> Void

    @Environment(StepSync.self) private var stepSync
    @State private var isConnecting = false
    @ScaledMetric(relativeTo: .headline) private var badge: CGFloat = 32

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                VStack(alignment: .leading, spacing: 16) {
                    Icon.health
                        .size(32)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.accent, in: .rect(cornerRadius: 18, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Share your steps with your family")
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .padding(.top, 24)
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 16) {
                    reason("Your phone already counts your steps in Apple Health.")
                    reason("Hamro Steps adds them to your family's total for the day, so nobody types anything.")
                    reason("Your family sees only your step total for each day. Never where you are.")
                    reason("We only read steps. We never change your Health data, and never sell it or use it for ads.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Bento.padding)
                .bentoSurface()

                if stepSync.isHealthAvailable {
                    Card(title: "On the next screen", icon: .health) {
                        VStack(alignment: .leading, spacing: 14) {
                            step(1, "Turn on Steps")
                            step(2, "Tap Allow")
                        }
                    }
                } else {
                    Notice(text: String(localized: "Apple Health isn't available on this device, so your steps can't be shared from it. You can still follow your family."))
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if isConnecting {
                    OrbLoader(activity: .connectingHealth)
                } else if stepSync.isHealthAvailable {
                    PrimaryButton(title: "Allow step count") { connect() }
                    SecondaryButton(title: "Not now") { onFinished() }
                } else {
                    PrimaryButton(title: "Continue") { onFinished() }
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
            .background(.canvas)
        }
        .background(.canvas)
    }

    private func reason(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon.tick.size(22).foregroundStyle(.goalText).padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One numbered step of the Health sheet ("1  Turn on Steps").
    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Text(verbatim: "\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.accentText)
                .frame(width: badge, height: badge)
                .background(Color.accent.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            Text(text)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(number): \(Text(text))"))
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
