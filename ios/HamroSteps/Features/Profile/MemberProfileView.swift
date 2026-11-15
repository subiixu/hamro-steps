import SwiftUI

/// What a family member sees when they tap someone: a big photo, the name,
/// where they live with their time now, and their birthday (no year).
struct MemberProfileView: View {
    let member: FamilyMember
    var isYou = false

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 22

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Bento.gap) {
                    header
                    details
                }
                .padding(.horizontal, Bento.margin)
                .padding(.vertical, 8)
            }
            .background(.canvas)
            .tint(.accentText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var displayName: String {
        let name = member.name.isEmpty ? String(localized: "Family member") : member.name
        return isYou ? String(localized: "\(name) (you)") : name
    }

    private var header: some View {
        VStack(spacing: 14) {
            Avatar(name: member.name, photoUrl: member.photoUrl, size: 140)
            VStack(spacing: 4) {
                Text(displayName)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if member.isOrganiser {
                    Text("Organiser")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Bento.padding)
        .padding(.horizontal, Bento.padding)
        .bentoSurface()
    }

    @ViewBuilder
    private var details: some View {
        let birthday = member.birthday.flatMap { ProfileFormat.birthday($0) }
        // Ticks each minute so "their time now" stays right while open.
        TimelineView(.everyMinute) { context in
            let place = ProfileFormat.placeLine(city: member.city, timezone: member.timezone, now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                if let place {
                    detail(icon: .location, label: "Lives in", value: place)
                }
                if let birthday {
                    if place != nil { TileDivider() }
                    detail(icon: .birthday, label: "Birthday", value: birthday)
                }
                if place == nil && birthday == nil {
                    Text(isYou
                         ? "Add where you live and your birthday from Me › Edit profile."
                         : "\(member.name.isEmpty ? String(localized: "They") : member.name) hasn't added where they live or a birthday yet.")
                        .font(.body)
                        .foregroundStyle(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Bento.padding)
            .padding(.vertical, 4)
            .bentoSurface()
        }
    }

    private func detail(icon: Icon, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 14) {
            icon.size(min(iconSize, 34))
                .foregroundStyle(.accentText)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryText)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MemberProfileView(member: FamilyMember(
        userId: "u_aama", name: "Aama", position: 1, isOrganiser: false, steps: 8_105, lastSyncedAt: nil,
        city: "Kathmandu", timezone: "Asia/Kathmandu", birthday: "1962-08-24"
    ))
}
