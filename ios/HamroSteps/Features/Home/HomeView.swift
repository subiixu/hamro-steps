import SwiftUI

/// Home (PRD F6–F14): the family's progress today, the walk button, who
/// added what (fixed order, never ranked) with who's walking and their
/// status, which days this week the family hit the goal, and the feed.
struct HomeView: View {
    @Environment(HomeModel.self) private var home
    @Environment(SessionStore.self) private var session
    @Environment(StepSync.self) private var stepSync
    @Environment(\.activityService) private var activity
    @Environment(\.now) private var now
    @Environment(\.scenePhase) private var scenePhase

    @State private var walk: WalkController?
    @State private var feed: FeedModel?
    /// The feed event a tapped notification brought into view, softly
    /// highlighted for a moment.
    @State private var highlightedEventId: String?
    /// The running focus from the latest tap; a newer tap cancels it.
    @State private var focusTask: Task<Void, Never>?
    @State private var showStatusPicker = false
    /// The status just saved or cleared here, shown until `familyToday`
    /// catches up. `.some(nil)` means cleared.
    @State private var savedStatus: MemberStatus??

    @State private var showSettings = AppLaunch.screen == .settings
    @State private var showAddFamily = false
    /// Drops the chevron to the middle of the title's first line, at any
    /// text size, instead of the middle of a wrapped title.
    @ScaledMetric(relativeTo: .largeTitle) private var chevronTop: CGFloat = 10

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                    await feed?.load()
                }
                .onChange(of: focusCheck, initial: true) { showFocusedEvent(proxy) }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .task(id: home.selectedFamilyId) {
            await home.listen()
        }
        .task(id: home.selectedFamilyId) {
            if walk == nil { walk = WalkController(service: activity) }
            if let familyId = home.selectedFamilyId, feed?.familyId != familyId {
                feed = FeedModel(service: activity, familyId: familyId, viewerId: session.user?.id)
            }
        }
        .task(id: highlightedEventId) {
            guard highlightedEventId != nil,
                  (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
            withAnimation(.easeOut(duration: 0.6)) { highlightedEventId = nil }
        }
        .onChange(of: viewer?.walkingSince, initial: true) { syncWalk() }
        .onChange(of: viewer?.walkEndsAt) { syncWalk() }
        .onChange(of: viewer?.status) { savedStatus = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { walk?.expireStaleNotice() }
        }
        .sheet(isPresented: $showStatusPicker) {
            StatusPicker(current: myStatus) { input in
                try await activity.setStatus(input)
                let expiry = input.expiresAt ?? ActivityTime.millis(now().addingTimeInterval(StatusInput.defaultDuration))
                savedStatus = .some(MemberStatus(preset: input.preset, text: input.text, expiresAt: expiry))
            } onClear: {
                try await activity.clearStatus()
                savedStatus = .some(nil)
            }
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

    // MARK: Activity

    /// The signed-in member's row in today's family.
    private var viewer: FamilyMember? {
        home.members.first { $0.userId == session.user?.id }
    }

    private var myStatus: MemberStatus? {
        savedStatus ?? viewer?.status
    }

    private func syncWalk() {
        walk?.sync(walkingSince: viewer?.walkingSince, walkEndsAt: viewer?.walkEndsAt)
    }

    /// Members with the viewer's status as just saved here.
    private var members: [FamilyMember] {
        guard let savedStatus else { return home.members }
        return home.members.map { member in
            var member = member
            if member.userId == session.user?.id { member.status = savedStatus }
            return member
        }
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
            if let walk {
                WalkButton(controller: walk)
            }
            StatusEntry(status: myStatus) { showStatusPicker = true }
            ContributionsCard(members: members, currentUserId: session.user?.id)
            if !home.week.isEmpty {
                WeekCard(days: home.week, today: home.today?.day)
            }
            if let feed {
                FeedCard(model: feed, highlightedEventId: highlightedEventId)
            }
        }
    }
}

// MARK: - Focus from a tapped notification

extension HomeView {
    /// What decides whether a tapped notification's event can be shown yet.
    struct FocusCheck: Equatable {
        var eventId: String?
        var feedFamilyId: String?
        var feedPhase: FeedModel.Phase?
    }

    var focusCheck: FocusCheck {
        FocusCheck(eventId: home.focusEventId, feedFamilyId: feed?.familyId, feedPhase: feed?.phase)
    }

    /// Once the selected family's feed has loaded, takes the focus event,
    /// reloads the feed if the event is newer than it, then scrolls to the
    /// event and highlights it. An event that isn't there leaves the family
    /// showing as it is.
    func showFocusedEvent(_ proxy: ScrollViewProxy) {
        guard home.focusEventId != nil, let feed, feed.familyId == home.selectedFamilyId,
              feed.phase != .loading, let eventId = home.takeFocus() else { return }
        focusTask?.cancel()
        focusTask = Task {
            /// Still the latest tap, and the feed on screen is still this one.
            @MainActor func current() -> Bool {
                !Task.isCancelled && self.feed === feed && home.selectedFamilyId == feed.familyId
            }
            if !feed.events.contains(where: { $0.id == eventId }) {
                // Its own task, so cancelling this focus never fails the reload.
                await Task { await feed.load() }.value
                guard current() else { return }
            }
            guard feed.events.contains(where: { $0.id == eventId }) else { return }
            // Let the rows lay out before scrolling to one.
            try? await Task.sleep(for: .milliseconds(150))
            guard current() else { return }
            withAnimation { proxy.scrollTo(eventId, anchor: .center) }
            highlightedEventId = eventId
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
    @Environment(\.now) private var now

    var body: some View {
        // Ticks so a walk or status drops off when it ends, without waiting
        // for the next refresh.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            card(now: now())
        }
    }

    private func card(now: Date) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Everyone's steps today")
                    .font(.title3.weight(.semibold))
                    .padding(.bottom, 8)
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { Divider().padding(.leading, 64) }
                    MemberRow(member: member, isYou: member.userId == currentUserId, now: now)
                }
            }
        }
    }
}

struct MemberRow: View {
    let member: FamilyMember
    let isYou: Bool
    var now: Date = .now
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
                    if let walk = member.activeWalk, !walk.isOver(at: now) {
                        WalkingBadge()
                    }
                    StatusLabel(status: member.status, now: now)
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

// MARK: - Status entry

/// "Set my status" on Home, or the viewer's current status with a way to
/// change it. Opens the status picker.
struct StatusEntry: View {
    let status: MemberStatus?
    let action: () -> Void
    @Environment(\.now) private var now

    var body: some View {
        let active = status.flatMap { $0.isActive(at: now()) ? $0 : nil }
        Button(action: action) {
            HStack(spacing: 12) {
                ((active?.preset?.icon) ?? (active == nil ? .edit : .statusCustom)).size(20)
                    .foregroundStyle(.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    if let text = active?.displayText {
                        Text("Your status").font(.footnote).foregroundStyle(.secondaryText)
                        Text(text).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    } else {
                        Text("Set my status").font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text("Let your family know what you're up to.")
                            .font(.footnote).foregroundStyle(.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Icon.chevronRight.size(16).foregroundStyle(.secondaryText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surface, in: .rect(cornerRadius: 24))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active?.displayText.map { Text("Your status: \($0)") } ?? Text("Set my status"))
        .accessibilityHint(Text("Choose what your family sees next to your name."))
    }
}

// MARK: - Family moments

struct FeedCard: View {
    let model: FeedModel
    var highlightedEventId: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Family moments")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                FeedList(model: model, highlightedEventId: highlightedEventId)
                    .id(model.familyId)
            }
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
