import SwiftUI

/// Loads and saves the 4 notification switches. A switch moves at once and
/// moves back if saving fails.
@MainActor @Observable
final class NotificationSettingsModel {
    enum Phase: Equatable { case loading, loaded, failed }

    private(set) var prefs = NotificationPrefs.defaults
    private(set) var phase: Phase = .loading
    private(set) var saveFailed = false

    @ObservationIgnored private let service: any ActivityService

    init(service: any ActivityService) {
        self.service = service
    }

    func load() async {
        phase = .loading
        do {
            prefs = try await service.notificationPrefs()
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    func set(_ kind: NotificationKind, to value: Bool) async {
        let before = prefs[kind]
        guard before != value else { return }
        prefs[kind] = value
        saveFailed = false
        do {
            try await service.setNotificationPrefs(NotificationPrefsPatch(kind, value))
        } catch {
            prefs[kind] = before
            saveFailed = true
        }
    }
}

extension NotificationKind {
    var title: LocalizedStringKey {
        switch self {
        case .walkStarted: "Someone starts a walk"
        case .goalHit: "The family reaches the goal"
        case .reactions: "Reactions to you"
        case .eveningNudge: "Evening reminder"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .walkStarted: "When someone in the family taps “I'm walking”, so you can join them or give them a call."
        case .goalHit: "Celebrate together when everyone's steps add up to today's goal."
        case .reactions: "When someone reacts to your steps or your walk."
        case .eveningNudge: "At 7 pm Nepal time, if the family is still short of the goal, a gentle note that a short walk would help."
        }
    }
}

/// Notification settings: 4 switches, each with a plain description.
struct NotificationSettingsView: View {
    let model: NotificationSettingsModel

    var body: some View {
        Form {
            switch model.phase {
            case .loading:
                ActivityLoadingRow(message: "Loading your notification settings…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .failed:
                Section {
                    Text("We couldn't load your notification settings.")
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await model.load() } }
                }
            case .loaded:
                Section {
                    ForEach(NotificationKind.allCases) { kind in
                        Toggle(isOn: binding(for: kind)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title)
                                    .font(.body.weight(.semibold))
                                Text(kind.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 6)
                        }
                        .tint(.accent)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Icon.notification.size(16)
                        Text("Let me know when")
                    }
                } footer: {
                    if model.saveFailed {
                        Text("That change didn't save. Check your connection and try again.")
                    } else {
                        Text("Your family never sees these settings.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.canvas)
        .navigationTitle("Notifications")
        .task { await model.load() }
    }

    private func binding(for kind: NotificationKind) -> Binding<Bool> {
        Binding(
            get: { model.prefs[kind] },
            set: { value in Task { await model.set(kind, to: value) } }
        )
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(model: NotificationSettingsModel(service: MockActivityService()))
    }
}
