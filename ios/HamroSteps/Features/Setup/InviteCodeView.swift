import SwiftUI
import UIKit

/// Create, step 3: the code in big type and a Share button that sends a
/// WhatsApp-friendly invite message.
struct InviteCodeView: View {
    let family: FamilySummary
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Invite your family")
                    .font(.largeTitle.bold())
                Text("Send this code to everyone in \(family.name). They install Hamro Steps and type it in.")
                    .font(.body)
                    .foregroundStyle(.secondaryText)
                InviteCodeCard(family: family)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                ShareLink(item: InviteMessage.text(familyName: family.name, code: family.inviteCode)) {
                    Label { Text("Share invite") } icon: { Icon.share.image }
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Button("Done", action: onDone)
                    .font(.title3.weight(.semibold))
                    .padding(.vertical, 6)
            }
            .padding(24)
            .background(.canvas)
        }
        .background(.canvas)
        .navigationBarBackButtonHidden()
    }
}

/// The code itself, big enough to read out over a phone call, with Copy.
struct InviteCodeCard: View {
    let family: FamilySummary
    /// Inside a List row, which already draws the rounded surface.
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
            .buttonStyle(.bordered)
            .tint(.accentText)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(embedded ? Color.clear : Color.surface, in: .rect(cornerRadius: 24))
    }
}

#Preview {
    NavigationStack {
        InviteCodeView(family: FamilySummary(familyId: "f_thapa", name: "Thapa Family", dailyGoal: 50_000, inviteCode: "K7M2QX", organiserId: "u_priya", memberCount: 5, isFull: false)) {}
    }
}
