import SwiftUI

/// Phase 1 placeholder. Family create/join, the shared goal ring and cheers
/// arrive with the backend (phase 2).
struct FamilyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            Icon.family
                                .size(32)
                                .foregroundStyle(.accent)
                            Text("Walk together")
                                .font(.title2.bold())
                            Text("Create a family or join one with an invite code to see everyone's steps add up.")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Button {} label: {
                                    Label { Text("Create") } icon: { Icon.plus.size(18) }
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                Button {} label: {
                                    Label { Text("Invite") } icon: { Icon.share.size(18) }
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            .controlSize(.large)
                            .disabled(true)
                            Text("Coming soon")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        PlaceholderRow(icon: .goal, tint: .goal, title: "Family goal ring",
                                       detail: "Everyone's steps fill one ring.")
                    }
                    Card {
                        PlaceholderRow(icon: .cheer, tint: .cheer, title: "Cheers and nudges",
                                       detail: "Send a cheer when someone's on a roll.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(.canvas)
            .navigationTitle("Family")
        }
    }
}

#Preview {
    FamilyView()
}
