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
    @State private var shownMember: FamilyMember?
    @State private var confirmLeave = false

    private var family: FamilySummary? { home.today?.family }
    private var isOrganiser: Bool { home.isOrganiser(session.user?.id) }
    private var organiserName: String? { home.members.first(where: \.isOrganiser)?.name }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Bento.gap) {
                    if let message { Notice(text: message) }
                    if let family {
                        familyTile(family)
                        if isOrganiser { inviteTile(family) }
                        peopleTile(family)
                        leaveTile(family)
                    }
                }
                .padding(.horizontal, Bento.margin)
                .padding(.vertical, 8)
            }
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

    // MARK: Tiles

    private func familyTile(_ family: FamilySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Card(title: "Family", icon: .home) {
                VStack(alignment: .leading, spacing: 0) {
                    fact("Name", family.name)
                    TileDivider()
                    fact("Daily goal", StepFormatter.withUnit(family.dailyGoal))
                    if isOrganiser {
                        TileDivider()
                        NavigationLink {
                            EditFamilyView(family: family)
                        } label: {
                            TileRow(icon: .edit, title: "Change name or goal")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !isOrganiser, let organiserName {
                footer(Text("Only \(organiserName), the organiser, can change these."))
            }
        }
    }

    private func inviteTile(_ family: FamilySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Card(title: "Invite code", icon: .share) {
                VStack(alignment: .leading, spacing: 0) {
                    InviteCodeCard(family: family, embedded: true)
                    TileDivider()
                    ShareLink(item: InviteMessage.text(familyName: family.name, code: family.inviteCode)) {
                        TileRow(icon: .share, title: "Share invite", isAction: true)
                    }
                    .buttonStyle(.plain)
                    TileDivider()
                    Button {
                        confirmRegenerate = true
                    } label: {
                        TileRow(icon: .refresh, title: "Get a new code", isAction: true)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Get a new code?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
                        Button("Get a new code") { run { _ = try await service.regenerateInviteCode(familyId: family.id) } }
                    } message: {
                        Text("The old code will stop working. People already in the family stay in it.")
                    }
                }
            }
            footer(Text("Up to \(FamilyRules.maxMembers) people can be in a family."))
        }
    }

    private func peopleTile(_ family: FamilySummary) -> some View {
        Card(title: "People", icon: .family) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(home.members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { TileDivider() }
                    memberRow(member)
                }
            }
        }
        .sheet(item: $shownMember) { member in
            MemberProfileView(member: member, isYou: member.userId == session.user?.id)
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

    private func memberRow(_ member: FamilyMember) -> some View {
        let canRemove = isOrganiser && member.userId != session.user?.id
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            Button {
                shownMember = member
            } label: {
                HStack(spacing: 14) {
                    Avatar(name: member.name, photoUrl: member.photoUrl)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.userId == session.user?.id ? String(localized: "\(member.name) (you)") : member.name)
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if member.isOrganiser {
                            Text("Organiser").font(.footnote).foregroundStyle(.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Shows their profile"))
            if canRemove {
                Button {
                    memberToRemove = member
                } label: {
                    Label { Text("Remove") } icon: { Icon.userRemove.size(18) }
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.accentText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.surfaceMuted, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(member.name)"))
            }
        }
        .padding(.vertical, 10)
    }

    private func leaveTile(_ family: FamilySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                confirmLeave = true
            } label: {
                TileRow(icon: .logout, title: "Leave \(family.name)", isAction: true)
                    .padding(.horizontal, Bento.padding)
                    .padding(.vertical, 2)
                    .bentoSurface()
            }
            .buttonStyle(.plain)
            .confirmationDialog("Leave \(family.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave family", role: .destructive) { leave(family) }
            } message: {
                Text(leaveMessage)
            }
            footer(Text("Leaving removes your steps from this family. You can join again with the code."))
        }
    }

    /// "Name   Thapa Family": a fact row; stacks at accessibility sizes.
    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(label)
                .foregroundStyle(.primary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(value)
                .foregroundStyle(.secondaryText)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Quiet text under a tile, like a list footer.
    private func footer(_ text: Text) -> some View {
        text
            .font(.footnote)
            .foregroundStyle(.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
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
            VStack(alignment: .leading, spacing: Bento.gap) {
                TileLabel("Family name", icon: .home)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                TextField("Family name", text: $name)
                    .font(.title3)
                    .textInputAutocapitalization(.words)
                    .fieldTile()
                TileLabel("Daily goal", icon: .goal)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                GoalPicker(goal: $goal)
                Text("A new goal counts from today. Earlier days keep the goal they had.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                if let message { Notice(text: message) }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 8)
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
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
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
