import SwiftUI

/// Opened from Home's header for the family on screen. The organiser edits
/// the name and goal, shares or renews the code, and removes members.
/// Everyone can leave.
struct FamilySettingsView: View {
    @Environment(HomeModel.self) private var home
    @Environment(SessionStore.self) private var session
    @Environment(\.familyService) private var service
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var message: String?
    @State private var confirmRegenerate = false
    @State private var memberToRemove: FamilyMember?
    @State private var confirmLeave = false

    private var family: FamilySummary? { home.today?.family }
    private var isOrganiser: Bool { home.isOrganiser(session.user?.id) }
    private var organiserName: String? { home.members.first(where: \.isOrganiser)?.name }

    var body: some View {
        NavigationStack {
            List {
                if let message {
                    Section { Notice(text: message).listRowInsets(EdgeInsets()) }
                }
                if let family {
                    familySection(family)
                    if isOrganiser { inviteSection(family) }
                    membersSection(family)
                    leaveSection(family)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.canvas)
            .tint(.accentText)
            .navigationTitle("Family settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if busy {
                    ToolbarItem(placement: .topBarLeading) { OrbLoader(activity: .saving, compact: true) }
                }
            }
            .disabled(busy)
        }
    }

    // MARK: Sections

    private func familySection(_ family: FamilySummary) -> some View {
        Section {
            LabeledContent("Name", value: family.name)
            LabeledContent("Daily goal", value: StepFormatter.withUnit(family.dailyGoal))
            if isOrganiser {
                NavigationLink {
                    EditFamilyView(family: family)
                } label: {
                    Label { Text("Change name or goal") } icon: { Icon.edit.image }
                }
            }
        } header: {
            Text("Family").foregroundStyle(.secondaryText)
        } footer: {
            if !isOrganiser, let organiserName {
                Text("Only \(organiserName), the organiser, can change these.").foregroundStyle(.secondaryText)
            }
        }
    }

    private func inviteSection(_ family: FamilySummary) -> some View {
        Section {
            // Embedded: the list row is the card, so the code, Share and
            // New code read as one rounded group with full-width dividers.
            InviteCodeCard(family: family, embedded: true)
                .listRowInsets(EdgeInsets())
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            ShareLink(item: InviteMessage.text(familyName: family.name, code: family.inviteCode)) {
                Label { Text("Share invite") } icon: { Icon.share.image }
            }
            Button {
                confirmRegenerate = true
            } label: {
                Label { Text("Get a new code") } icon: { Icon.refresh.image }
            }
            .confirmationDialog("Get a new code?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
                Button("Get a new code") { run { _ = try await service.regenerateInviteCode(familyId: family.id) } }
            } message: {
                Text("The old code will stop working. People already in the family stay in it.")
            }
        } header: {
            Text("Invite code").foregroundStyle(.secondaryText)
        } footer: {
            Text("Up to \(FamilyRules.maxMembers) people can be in a family.").foregroundStyle(.secondaryText)
        }
    }

    private func membersSection(_ family: FamilySummary) -> some View {
        Section {
            ForEach(home.members) { member in
                HStack(spacing: 14) {
                    Avatar(name: member.name, hex: member.avatarColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.userId == session.user?.id ? String(localized: "\(member.name) (you)") : member.name)
                            .font(.body.weight(.semibold))
                        if member.isOrganiser {
                            Text("Organiser").font(.footnote).foregroundStyle(.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    if isOrganiser && member.userId != session.user?.id {
                        Button {
                            memberToRemove = member
                        } label: {
                            Label { Text("Remove") } icon: { Icon.userRemove.size(20) }
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.accentText)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove \(member.name)"))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("People").foregroundStyle(.secondaryText)
        }
        .confirmationDialog(
            Text("Remove \(memberToRemove?.name ?? "")?"),
            isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button("Remove \(member.name)", role: .destructive) {
                run { try await service.removeMember(familyId: family.id, userId: member.userId) }
            }
        } message: { member in
            Text("\(member.name) will leave \(family.name). Their steps stop counting here. They can join again with the code.")
        }
    }

    private func leaveSection(_ family: FamilySummary) -> some View {
        Section {
            Button {
                confirmLeave = true
            } label: {
                Label { Text("Leave \(family.name)") } icon: { Icon.logout.image }
            }
            .confirmationDialog("Leave \(family.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave family", role: .destructive) { leave(family) }
            } message: {
                Text(leaveMessage)
            }
        } footer: {
            Text("Leaving removes your steps from this family. You can join again with the code.").foregroundStyle(.secondaryText)
        }
    }

    private var leaveMessage: String {
        if isOrganiser, let next = home.members.first(where: { $0.userId != session.user?.id }) {
            return String(localized: "You're the organiser, so \(next.name) will take over.")
        }
        return String(localized: "Your steps will stop counting for this family.")
    }

    // MARK: Actions

    private func leave(_ family: FamilySummary) {
        run {
            try await service.leaveFamily(familyId: family.id)
            await session.refreshFamilies()
            dismiss()
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true
        message = nil
        Task {
            do {
                try await action()
            } catch let error as FamilyServiceError {
                message = error.message
            } catch {
                message = FamilyServiceError.unavailable("").message
            }
            busy = false
        }
    }
}

/// Organiser only: rename the family and change the daily goal.
struct EditFamilyView: View {
    let family: FamilySummary

    @Environment(\.familyService) private var service
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var goal: Int
    @State private var isSaving = false
    @State private var message: String?

    init(family: FamilySummary) {
        self.family = family
        _name = State(initialValue: family.name)
        _goal = State(initialValue: family.dailyGoal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Family name").font(.headline)
                TextField("Family name", text: $name)
                    .font(.title3)
                    .textInputAutocapitalization(.words)
                    .padding(16)
                    .background(.surface, in: .rect(cornerRadius: 16))
                Text("Daily goal").font(.headline).padding(.top, 8)
                GoalPicker(goal: $goal)
                Text("A new goal counts from today. Earlier days keep the goal they had.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryText)
                if let message { Notice(text: message) }
            }
            .padding(24)
        }
        .background(.canvas)
        .navigationTitle("Change name or goal")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Group {
                if isSaving {
                    OrbLoader(activity: .saving)
                } else {
                    PrimaryButton(title: "Save", isEnabled: FamilyRules.isValidName(name), action: save)
                }
            }
            .padding(24)
            .background(.canvas)
        }
    }

    private func save() {
        isSaving = true
        message = nil
        Task {
            do {
                _ = try await service.updateFamily(familyId: family.id, name: name, dailyGoal: goal)
                await session.refreshFamilies()
                dismiss()
            } catch let error as FamilyServiceError {
                message = error.message
            } catch {
                message = FamilyServiceError.unavailable("").message
            }
            isSaving = false
        }
    }
}
