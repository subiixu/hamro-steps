import SwiftUI

/// Phase 1 placeholder: profile header and settings rows with no actions yet.
struct MeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        HStack(spacing: 16) {
                            Icon.profile
                                .size(32)
                                .foregroundStyle(.accent)
                                .frame(width: 64, height: 64)
                                .background(Color.accent.opacity(0.14), in: .circle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("You").font(.title2.bold())
                                Text("Sign in arrives in the next update.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Card {
                        VStack(spacing: 0) {
                            row(icon: .home, title: "Apple Health")
                            Divider().padding(.leading, 40)
                            row(icon: .fire, title: "Streaks")
                            Divider().padding(.leading, 40)
                            row(icon: .settings, title: "Settings")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(.canvas)
            .navigationTitle("Me")
        }
    }

    private func row(icon: Icon, title: LocalizedStringKey) -> some View {
        HStack(spacing: 16) {
            icon.foregroundStyle(.accent)
            Text(title)
            Spacer()
            Icon.chevronRight.size(18).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    MeView()
}
