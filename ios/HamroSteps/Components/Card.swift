import SwiftUI

/// Rounded surface used by every block on the main screens.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.surface, in: .rect(cornerRadius: 24))
    }
}

/// The big full-width button at the bottom of onboarding and setup screens.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

/// A calm, neutral message (never red): "code not found", "try again".
struct Notice: View {
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Try again", action: retry)
                    .font(.body.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.surfaceMuted, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// A round coloured avatar with the person's initial.
struct Avatar: View {
    let name: String
    let hex: String
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 48

    var body: some View {
        Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
            .font(.title2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: hex), in: .circle)
            .accessibilityHidden(true)
    }
}
