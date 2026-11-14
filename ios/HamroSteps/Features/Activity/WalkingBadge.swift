import SwiftUI

/// A small live "Walking now" pill for a member row. The dot pulses gently;
/// with Reduce Motion it stays still.
struct WalkingBadge: View {
    var label: LocalizedStringKey = "Walking now"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if !reduceMotion {
                    Circle()
                        .fill(Color.accent.opacity(0.45))
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulsing ? 2.4 : 1)
                        .opacity(pulsing ? 0 : 1)
                }
                Circle()
                    .fill(.accent)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 14, height: 14)
            // The walker icon goes first when space is tight; the words
            // never wrap mid-word.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Icon.walking.size(iconSize)
                        .foregroundStyle(.accent)
                    text
                }
                text
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Color.accent.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
        .onAppear { startPulse() }
        .onChange(of: reduceMotion) { _, _ in startPulse() }
    }

    private var text: some View {
        Text(label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
    }

    private func startPulse() {
        guard !reduceMotion else {
            pulsing = false
            return
        }
        pulsing = false
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulsing = true
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WalkingBadge()
        WalkingBadge(label: "You're walking")
    }
    .padding()
}
