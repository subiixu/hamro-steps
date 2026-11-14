import SwiftUI
import UIKit

/// Create, step 3: the code in big type and a Share button that sends a
/// WhatsApp-friendly invite message.
struct InviteCodeView: View {
    let family: FamilySummary
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                SetupHeading(title: "Invite your family", detail: "Send this code to everyone in \(family.name). They install Hamro Steps and type it in.")
                InviteCodeCard(family: family)
            }
            .padding(.horizontal, Bento.margin)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                ShareLink(item: InviteMessage.text(familyName: family.name, code: family.inviteCode)) {
                    Label { Text("Share invite") } icon: { Icon.share.image }
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                SecondaryButton(title: "Done", action: onDone)
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
            .background(.canvas)
        }
        .background(.canvas)
        .navigationBarBackButtonHidden()
    }
}

/// The code itself, big enough to read out over a phone call, with Copy.
struct InviteCodeCard: View {
    let family: FamilySummary
    /// Inside another tile (Family settings), which already draws the surface.
    var embedded = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Text(InviteCode.display(family.inviteCode))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .tracking(4)
                .textSelection(.enabled)
                .accessibilityLabel(Text("Family code"))
                .accessibilityValue(Text(family.inviteCode.map(String.init).joined(separator: " ")))
            Button {
                UIPasteboard.general.string = family.inviteCode
                copied = true
            } label: {
                Label { Text(copied ? "Copied" : "Copy code") } icon: { (copied ? Icon.tick : Icon.copy).image }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.accentText)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, embedded ? 8 : 28)
        .padding(.horizontal, embedded ? 0 : 16)
        .background {
            if !embedded {
                Color.clear.bentoSurface()
            }
        }
    }
}

#Preview {
    NavigationStack {
        InviteCodeView(family: FamilySummary(familyId: "f_thapa", name: "Thapa Family", dailyGoal: 50_000, inviteCode: "K7M2QX", organiserId: "u_priya", memberCount: 5, isFull: false)) {}
    }
}
