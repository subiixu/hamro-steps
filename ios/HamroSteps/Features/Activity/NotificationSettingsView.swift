import SwiftUI

/// Loads and saves the 4 notification switches. A switch moves at once, is
/// disabled until its save finishes, and moves back if saving fails, so
/// saves for one switch never overlap.
@MainActor @Observable
final class NotificationSettingsModel {
    enum Phase: Equatable { case loading, loaded, failed }

    private(set) var prefs = NotificationPrefs.defaults
    private(set) var phase: Phase = .loading
    private(set) var saveFailed = false
    /// Switches with a save in flight.
    private(set) var saving: Set<NotificationKind> = []

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

    func isSaving(_ kind: NotificationKind) -> Bool { saving.contains(kind) }

    func set(_ kind: NotificationKind, to value: Bool) async {
        let before = prefs[kind]
        guard before != value, !saving.contains(kind) else { return }
        saving.insert(kind)
        defer { saving.remove(kind) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                switch model.phase {
                case .loading:
                    ActivityLoadingRow(message: "Loading your notification settings…")
                        .frame(maxWidth: .infinity, minHeight: 80)
                case .failed:
                    Notice(text: String(localized: "We couldn't load your notification settings.")) {
                        Task { await model.load() }
                    }
                case .loaded:
                    Card(title: "Let me know when", icon: .notification) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(NotificationKind.allCases.enumerated()), id: \.element) { index, kind in
                                if index > 0 { TileDivider() }
                                Toggle(isOn: binding(for: kind)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(kind.title)
                                            .font(.body.weight(.semibold))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(kind.detail)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .tint(.accent)
                                .disabled(model.isSaving(kind))
                                .padding(.vertical, 14)
                            }
                        }
                    }
                    Group {
                        if model.saveFailed {
                            Text("That change didn't save. Check your connection and try again.")
                        } else {
                            Text("Your family never sees these settings.")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 8)
        }
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
