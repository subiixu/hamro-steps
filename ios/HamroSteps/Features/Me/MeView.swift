import SwiftUI

/// The person's own page: name, Apple Health, sign out, delete account.
struct MeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StepSync.self) private var stepSync
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                // Same custom title as Home (no navigation bar), so the two
                // tabs start at the same height.
                Text("Me")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 0, trailing: 4))
                    .listRowBackground(Color.clear)
                    .listSectionSpacing(12)
                Section {
                    HStack(spacing: 16) {
                        Avatar(name: session.user?.displayName ?? "", hex: session.user?.avatarColor ?? "")
                        Text(session.user?.displayName ?? "")
                            .font(.title2.bold())
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    healthStatus
                } header: {
                    Text("Apple Health").foregroundStyle(.secondaryText)
                } footer: {
                    if stepSync.isHealthAvailable && stepSync.healthRequested {
                        Text("Steps not showing? Open the Health app, tap your picture, then Apps › Hamro Steps, and turn on Steps.")
                            .foregroundStyle(.secondaryText)
                    }
                }

                Section {
                    NavigationLink {
                        NotificationsScreen()
                    } label: {
                        Label { Text("Notifications") } icon: { Icon.notification.image }
                    }
                }

                Section {
                    Button {
                        confirmSignOut = true
                    } label: {
                        Label { Text("Sign out") } icon: { Icon.logout.image }
                    }
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

                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        // System destructive red: the standard iOS cue for
                        // an action that removes data (allowed by the brief).
                        Label { Text("Delete account") } icon: { Icon.delete.image }
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.canvas)
            .tint(.accentText)
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(.compact)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .task { await stepSync.refreshHealthStatus() }
        }
    }

    @ViewBuilder
    private var healthStatus: some View {
        if !stepSync.isHealthAvailable {
            Label { Text("Apple Health isn't available on this iPhone.") } icon: { Icon.health.image }
        } else if stepSync.healthRequested {
            // The request status only says the sheet was shown, not that
            // access was granted (Health hides a denial). So "Reading steps"
            // needs real data: a sync only records a time when it read
            // non-zero steps. Otherwise stay neutral.
            VStack(alignment: .leading, spacing: 4) {
                if let last = stepSync.lastSyncedAt {
                    Label { Text("Reading steps").font(.body.weight(.semibold)) } icon: { Icon.health.image.foregroundStyle(.goal) }
                    Text("Steps last sent \(last, format: .relative(presentation: .named))")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryText)
                } else {
                    Label { Text("Permission asked").font(.body.weight(.semibold)) } icon: { Icon.health.image }
                    Text("No steps read yet. If you walked today and nothing shows, check the steps below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hamro Steps can't see your steps yet, so they aren't counting for your family.")
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await stepSync.connectHealth() }
                } label: {
                    Label { Text("Connect Apple Health") } icon: { Icon.health.image }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .padding(.vertical, 6)
        }
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
            VStack(alignment: .leading, spacing: 20) {
                Text("Delete your account?")
                    .font(.largeTitle.bold())
                Text("This removes everything Hamro Steps has about you:")
                    .font(.body)
                VStack(alignment: .leading, spacing: 12) {
                    item("Your name and sign-in")
                    item("Your step totals")
                    item("Your place in every family you're in")
                }
                Text("Your families carry on without you. If you organise a family, the next person in it takes over. The steps in Apple Health stay on your iPhone.")
                    .font(.body)
                    .foregroundStyle(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let message { Notice(text: message) }
            }
            .padding(24)
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
            .padding(24)
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
            Text(text).font(.body)
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
