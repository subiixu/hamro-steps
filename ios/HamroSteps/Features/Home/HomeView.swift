import SwiftUI

/// Home (PRD F6–F8): the family's progress today, who added what (fixed
/// order, never ranked), and which days this week the family hit the goal.
struct HomeView: View {
    @Environment(HomeModel.self) private var home
    @Environment(SessionStore.self) private var session
    @Environment(StepSync.self) private var stepSync

    @State private var showSettings = AppLaunch.screen == .settings
    @State private var showAddFamily = false
    /// Drops the chevron to the middle of the title's first line, at any
    /// text size, instead of the middle of a wrapped title.
    @ScaledMetric(relativeTo: .largeTitle) private var chevronTop: CGFloat = 10

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            // Room below the last card so the floating tab bar never sits on it.
            .contentMargins(.bottom, 72, for: .scrollContent)
            .background(.canvas)
            .refreshable {
                await stepSync.sync()
                await home.reload()
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .task(id: home.selectedFamilyId) {
            await home.listen()
        }
        .sheet(isPresented: $showSettings) {
            FamilySettingsView()
        }
        .sheet(isPresented: $showAddFamily) {
            FamilySetupView(isFirstFamily: false) { family in
                showAddFamily = false
                home.prefer(family.id)
                Task { await session.refreshFamilies() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if home.showsSwitcher {
                Menu {
                    ForEach(home.families) { family in
                        Button {
                            Task { await home.select(family.id) }
                        } label: {
                            if family.id == home.selectedFamilyId {
                                Label { Text(family.name) } icon: { Icon.tick.image }
                            } else {
                                Text(family.name)
                            }
                        }
                    }
                    Divider()
                    Button { showAddFamily = true } label: {
                        Label { Text("Add another family") } icon: { Icon.plus.image }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        familyTitle
                        Icon.chevronDown.size(22).foregroundStyle(.secondaryText)
                            .padding(.top, chevronTop)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(home.selectedFamily?.name ?? ""), switch family"))
            } else {
                familyTitle
                    .contextMenu {
                        Button { showAddFamily = true } label: {
                            Label { Text("Add another family") } icon: { Icon.plus.image }
                        }
                    }
            }
            Spacer(minLength: 8)
            Button {
                showSettings = true
            } label: {
                Icon.settings.size(24)
                    .frame(width: 48, height: 48)
                    .background(.surface, in: .circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Family settings")
            .disabled(home.today == nil)
        }
        .padding(.top, 12)
    }

    private var familyTitle: some View {
        Text(home.selectedFamily?.name ?? String(localized: "Your family"))
            .font(.largeTitle.bold())
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch home.phase {
        case .loading where home.today == nil:
            OrbLoader(activity: .loadingFamily)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
        case .failed(let message) where home.today == nil:
            Notice(text: message) { Task { await home.reload() } }
        default:
            ProgressCard(total: home.total, goal: home.goal, percent: home.percent, fraction: home.ringFraction, reached: home.isGoalReached)
            SyncStatusRow(lastSyncedAt: stepSync.lastSyncedAt, isSyncing: stepSync.isSyncing)
            ContributionsCard(members: home.members, currentUserId: session.user?.id)
            if !home.week.isEmpty {
                WeekCard(days: home.week, today: home.today?.day)
            }
        }
    }
}

// MARK: - Progress ring

struct ProgressCard: View {
    let total: Int
    let goal: Int
    let percent: Int
    let fraction: Double
    let reached: Bool

    var body: some View {
        Card {
            VStack(spacing: 20) {
                ProgressRing(fraction: fraction, percent: percent, reached: reached)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 6) {
                    Text(StepFormatter.count(total))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(total)))
                    Text("of \(StepFormatter.count(goal)) steps today")
                        .font(.title3)
                        .foregroundStyle(.secondaryText)
                    Text(reached
                         ? String(localized: "Goal reached! Well walked, everyone.")
                         : String(localized: "\(StepFormatter.count(goal - total)) more steps to go, together"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(reached ? Color.goal : Color.primary)
                        .padding(.top, 4)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Family steps today"))
        .accessibilityValue(Text(reached
            ? "\(StepFormatter.count(total)) of \(StepFormatter.count(goal)). Goal reached, \(percent) percent."
            : "\(StepFormatter.count(total)) of \(StepFormatter.count(goal)), \(percent) percent."))
    }
}

/// The family's total against the goal. Past 100% the ring turns the goal
/// colour and keeps going round: a celebration, never capped, never red.
struct ProgressRing: View {
    let fraction: Double
    let percent: Int
    let reached: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 210
    private let lineWidth: CGFloat = 22

    var body: some View {
        // Capped so at accessibility sizes the ring doesn't fill the card and
        // push the totals below the fold; the text around it grows instead.
        let size = min(diameter, 240)
        ZStack {
            Circle()
                .stroke(.surfaceMuted, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(reached ? Color.goal : Color.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction > 1 {
                // The extra lap beyond the goal, in a lighter goal colour.
                Circle()
                    .trim(from: 0, to: min(fraction - 1, 1))
                    .stroke(Color.goal.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth * 0.55, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 4) {
                if reached {
                    Icon.celebrate.size(size * 0.14).foregroundStyle(.goal)
                }
                Text("\(percent)%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(lineWidth + 8)
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.8), value: fraction)
    }
}

// MARK: - Last synced

struct SyncStatusRow: View {
    let lastSyncedAt: Date?
    let isSyncing: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isSyncing {
                OrbLoader(activity: .syncingSteps, compact: true)
                Text("Sending your steps…")
            } else {
                Icon.clock.size(20)
                if let lastSyncedAt {
                    Text("Your steps synced \(lastSyncedAt, format: .relative(presentation: .named))")
                } else {
                    Text("Your steps haven't synced yet. Pull down to try.")
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Contributions

struct ContributionsCard: View {
    let members: [FamilyMember]
    let currentUserId: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Everyone's steps today")
                    .font(.title3.weight(.semibold))
                    .padding(.bottom, 8)
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { Divider().padding(.leading, 64) }
                    MemberRow(member: member, isYou: member.userId == currentUserId)
                }
            }
        }
    }
}

struct MemberRow: View {
    let member: FamilyMember
    let isYou: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            HStack(spacing: 14) {
                Avatar(name: member.name, hex: member.avatarColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isYou ? String(localized: "\(member.name) (you)") : member.name)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if member.isOrganiser {
                        HStack(spacing: 4) {
                            Icon.organiser.size(14)
                            Text("Organiser")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondaryText)
                    }
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            steps
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var steps: some View {
        if let value = member.steps {
            Text(StepFormatter.count(value))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel(Text(StepFormatter.withUnit(value)))
        } else {
            Text("not synced yet")
                .font(.body)
                .foregroundStyle(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - This week

struct WeekCard: View {
    let days: [FamilyWeekDay]
    let today: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hitCount: Int { days.filter { $0.hit && !$0.isBeforeFamily }.count }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week")
                        .font(.title3.weight(.semibold))
                    if hitCount > 0 {
                        Text(hitCount == 1 ? String(localized: "Goal reached on 1 day") : String(localized: "Goal reached on \(hitCount) days"))
                            .font(.subheadline)
                            .foregroundStyle(.secondaryText)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 4 : 7), spacing: 14) {
                    ForEach(days) { day in
                        WeekDayMarker(day: day, isToday: day.day == today)
                    }
                }
            }
        }
    }
}

struct WeekDayMarker: View {
    let day: FamilyWeekDay
    let isToday: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 38

    private var date: Date? { NepalDay.start(of: day.day) }

    var body: some View {
        VStack(spacing: 6) {
            Text(date.map { $0.formatted(Date.FormatStyle(timeZone: NepalDay.timeZone).weekday(.narrow)) } ?? "")
                .font(.footnote.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.primary : Color.secondaryText)
                .opacity(day.isBeforeFamily ? 0.5 : 1)
            ZStack {
                if day.hit {
                    Circle().fill(.goal)
                    Icon.tick.size(size * 0.5).foregroundStyle(.white)
                } else if day.isBeforeFamily {
                    Circle().fill(Color.secondary.opacity(0.08))
                } else if day.isFuture {
                    Circle().strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                } else {
                    Circle().fill(.surfaceMuted)
                }
                if isToday && !day.hit {
                    Circle().strokeBorder(.accent, lineWidth: 2)
                }
            }
            .frame(width: size, height: size)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        let name = date.map { $0.formatted(Date.FormatStyle(timeZone: NepalDay.timeZone).weekday(.wide)) } ?? day.day
        if day.isFuture { return String(localized: "\(name), still to come") }
        if day.isBeforeFamily { return String(localized: "\(name), before the family started") }
        if day.hit { return String(localized: "\(name), goal reached") }
        return String(localized: "\(name), \(StepFormatter.withUnit(day.total))")
    }
}
