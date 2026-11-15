import SwiftUI

/// The person's own page: their profile, Apple Health, sign out, delete
/// account.
struct MeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StepSync.self) private var stepSync
    @State private var confirmSignOut = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Bento.gap) {
                    // Same custom title as Home (no navigation bar), so the two
                    // tabs start at the same height.
                    Text("Me")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)
                        .padding(.top, 12)

                    profileTile
                    healthTile

                    rows {
                        NavigationLink {
                            NotificationsScreen()
                        } label: {
                            TileRow(icon: .notification, title: "Notifications")
                        }
                        .buttonStyle(.plain)
                        TileDivider()
                        Link(destination: URL(string: "https://subiixu.github.io/hamro-steps/privacy/")!) {
                            TileRow(icon: .health, title: "Privacy policy")
                        }
                        .buttonStyle(.plain)
                    }

                    rows {
                        Button {
                            confirmSignOut = true
                        } label: {
                            TileRow(icon: .logout, title: "Sign out", showsChevron: false)
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("Sign out of Hamro Steps?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                            Button("Sign out") {
                                Task {
                                    await session.signOut()
                                    stepSync.reset()
                                }
                            }
                        } message: {
                            Text("Your family keeps your steps so far. Sign in again with Apple any time.")
                        }
                        TileDivider()
                        NavigationLink {
                            DeleteAccountView()
                        } label: {
                            TileRow(icon: .delete, title: "Delete account", isDestructive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Bento.margin)
                .padding(.bottom, 16)
            }
            .background(.canvas)
            .tint(.accentText)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .task { await stepSync.refreshHealthStatus() }
        }
    }

    private var profileTile: some View {
        let user = session.user
        let birthday = user?.birthday.flatMap { ProfileFormat.birthday($0) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Avatar(name: user?.displayName ?? "", photoUrl: user?.photoUrl, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user?.displayName ?? "")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if let city = user?.city, !city.isEmpty {
                        Label { Text(city) } icon: { Icon.location.size(16) }
                            .font(.subheadline)
                            .foregroundStyle(.secondaryText)
                    }
                    if let birthday {
                        Label { Text("Birthday \(birthday)") } icon: { Icon.birthday.size(16) }
                            .font(.subheadline)
                            .foregroundStyle(.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
            TileDivider()
            NavigationLink {
                ProfileEditView(user: session.user)
            } label: {
                TileRow(icon: .edit, title: "Edit profile")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Bento.padding)
        .padding(.vertical, 4)
        .bentoSurface()
    }

    /// Rows grouped on one white tile.
    private func rows(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, Bento.padding)
        .padding(.vertical, 4)
        .bentoSurface()
    }

    private var healthTile: some View {
        Card(title: "Apple Health", icon: .health) {
            healthStatus
            if stepSync.isHealthAvailable && stepSync.healthRequested {
                Text("Steps not showing? Open the Health app, tap your picture, then Apps › Hamro Steps, and turn on Steps.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var healthStatus: some View {
        if !stepSync.isHealthAvailable {
            Text("Apple Health isn't available on this iPhone.")
                .fixedSize(horizontal: false, vertical: true)
        } else if stepSync.healthRequested {
            // The request status only says the sheet was shown, not that
            // access was granted (Health hides a denial). So "Reading steps"
            // needs real data: a sync only records a time when it read
            // non-zero steps. Otherwise stay neutral.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                if let last = stepSync.lastSyncedAt {
                    miniTile(icon: .health, iconStyle: .goalText) {
                        Text("Reading steps").font(.body.weight(.semibold))
                    }
                    miniTile(icon: .clock, iconStyle: .secondaryText) {
                        Text("Steps last sent \(last, format: .relative(presentation: .named))")
                            .font(.subheadline)
                            .foregroundStyle(.secondaryText)
                    }
                } else {
                    miniTile(icon: .health, iconStyle: .accentText) {
                        Text("Permission asked").font(.body.weight(.semibold))
                    }
                    miniTile(icon: .clock, iconStyle: .secondaryText) {
                        Text("No steps read yet. If you walked today and nothing shows, check the steps below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondaryText)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hamro Steps can't see your steps yet, so they aren't counting for your family.")
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await stepSync.connectHealth() }
                } label: {
                    Label { Text("Connect Apple Health") } icon: { Icon.health.image }
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
            }
        }
    }

    /// A small grey tile inside the Apple Health tile.
    private func miniTile(icon: Icon, iconStyle: Color, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            icon.size(20).foregroundStyle(iconStyle)
                .accessibilityHidden(true)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.surfaceMuted, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Account deletion (PRD F1), in two steps: this page says what will go,
/// then a final confirmation does it.
struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StepSync.self) private var stepSync
    @State private var confirm = false
    @State private var isDeleting = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                Text("Delete your account?")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 14) {
                    Text("This removes everything Hamro Steps has about you:")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    item("Your name, photo and sign-in")
                    item("Your step totals")
                    item("Your place in every family you're in")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Bento.padding)
                .bentoSurface()
                Text("Your families carry on without you. If you organise a family, the next person in it takes over. The steps in Apple Health stay on your iPhone.")
                    .font(.body)
                    .foregroundStyle(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                if let message { Notice(text: message) }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 8)
        }
        .background(.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Group {
                if isDeleting {
                    OrbLoader(activity: .deleting)
                } else {
                    Button(role: .destructive) {
                        confirm = true
                    } label: {
                        Text("Delete my account")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
            .background(.canvas)
        }
        .confirmationDialog("This can't be undone", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive, action: delete)
        } message: {
            Text("Your account and steps will be deleted for good.")
        }
    }

    private func item(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon.delete.size(20).foregroundStyle(.secondaryText).padding(.top, 2)
                .accessibilityHidden(true)
            Text(text).font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func delete() {
        isDeleting = true
        message = nil
        Task {
            do {
                try await session.deleteAccount()
                stepSync.reset()
            } catch {
                message = String(localized: "Your account wasn't deleted. Please try again in a moment.")
            }
            isDeleting = false
        }
    }
}

/// Me › Notifications: owns the settings model for as long as it's shown.
private struct NotificationsScreen: View {
    @Environment(\.activityService) private var activity
    @State private var model: NotificationSettingsModel?

    var body: some View {
        Group {
            if let model {
                NotificationSettingsView(model: model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = NotificationSettingsModel(service: activity) }
        }
    }
}
