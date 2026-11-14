import SwiftUI

/// Shown once, on first launch. HealthKit's own sheet does the asking; we
/// move on whatever the user picks, because a read denial is invisible to us.
struct ConnectHealthView: View {
    var onFinished: () -> Void

    @Environment(StepStore.self) private var steps
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Icon.home
                .size(56)
                .foregroundStyle(.accent)
                .frame(width: 112, height: 112)
                .background(Color.accent.opacity(0.14), in: .circle)

            VStack(spacing: 12) {
                Text("Connect Apple Health")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Hamro Steps reads your step count from Apple Health so your family can cheer you on. We only read steps, and never write anything.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)

            Spacer()

            if isConnecting {
                OrbLoader(activity: .connectingHealth)
                    .frame(height: 120)
            } else {
                VStack(spacing: 12) {
                    Button {
                        Task { await connect() }
                    } label: {
                        Text("Connect Apple Health")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)

                    Button("Not now") { onFinished() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.canvas)
    }

    private func connect() async {
        isConnecting = true
        await steps.connect()
        isConnecting = false
        onFinished()
    }
}

#Preview {
    ConnectHealthView {}
        .environment(StepStore(source: MockStepSource.sampleWeek()))
}
