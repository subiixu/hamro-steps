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
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    VStack(alignment: .leading, spacing: Bento.gap) {
                        header
                        content
                    }
                    .padding(.horizontal, Bento.margin)
                    .padding(.bottom, 24)
                }
                // Room below the last card so the floating tab bar never sits on it.
                .contentMargins(.bottom, 72, for: .scrollContent)
                .defaultScrollAnchor(AppLaunch.homeScrollAnchor)
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
        VStack(alignment: .leading, spacing: 12) {
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
                GlassIconButton(icon: .settings, label: "Family settings") { showSettings = true }
                    .disabled(home.today == nil)
            }
            if !home.members.isEmpty {
                togetherRow
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var familyTitle: some View {
        Text(home.selectedFamily?.name ?? String(localized: "Your family"))
            .font(.largeTitle.bold())
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Overlapping avatars and how many are in the family: who this is for.
    private var togetherRow: some View {
        HStack(spacing: 10) {
            AvatarStack(people: home.members.map { AvatarStack.Person(id: $0.userId, name: $0.name, hex: $0.avatarColor) })
            Group {
                if home.members.count == 1 {
                    Text("Just you so far")
                } else {
                    Text("\(home.members.count) walking together")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
            TodayTile(
                total: home.total, goal: home.goal, percent: home.percent,
                fraction: home.ringFraction, reached: home.isGoalReached, members: members
            )
            if let walk {
                WalkButton(controller: walk)
            }
            halfTiles
            ContributionsCard(members: members, currentUserId: session.user?.id, familyTotal: home.total)
            if !home.week.isEmpty {
                WeekCard(days: home.week, today: home.today?.day)
            }
            if let feed {
                FeedCard(model: feed, highlightedEventId: highlightedEventId)
            }
        }
    }

    /// Status and sync side by side; stacked at accessibility text sizes.
    private var halfTiles: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Bento.gap))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Bento.gap))
        return layout {
            StatusTile(status: myStatus) { showStatusPicker = true }
            SyncTile(lastSyncedAt: stepSync.lastSyncedAt, isSyncing: stepSync.isSyncing)
        }
        .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Today

/// The family's total against the goal, the ring, and a few plain facts.
struct TodayTile: View {
    let total: Int
    let goal: Int
    let percent: Int
    let fraction: Double
    let reached: Bool
    let members: [FamilyMember]
    @Environment(\.now) private var now
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Ticks so the "walking now" chip drops when a walk ends.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            tile(now: now())
        }
    }

    private func tile(now: Date) -> some View {
        let synced = members.filter { $0.steps != nil }.count
        let walking = members.filter { member in member.activeWalk.map { !$0.isOver(at: now) } ?? false }.count
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return Card(title: "Today", icon: .home) {
            VStack(alignment: .leading, spacing: 16) {
                layout {
                    totals
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    ProgressRing(fraction: fraction, percent: percent, reached: reached)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Family steps today"))
                .accessibilityValue(Text(reached
                    ? "\(StepFormatter.count(total)) of \(StepFormatter.count(goal)). Goal reached, \(percent) percent."
                    : "\(StepFormatter.count(total)) of \(StepFormatter.count(goal)), \(percent) percent."))

                if synced > 0 || walking > 0 {
                    ActivityWrapLayout(spacing: 6) {
                        if synced > 0 {
                            InfoChip(icon: .tick, text: String(localized: "\(synced) of \(members.count) synced"))
                        }
                        if walking > 0 {
                            InfoChip(icon: .walking, text: String(localized: "\(walking) walking now"))
                        }
                    }
                }
            }
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(StepFormatter.count(total))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(total)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("of \(StepFormatter.count(goal)) steps")
                .font(.subheadline)
                .foregroundStyle(.secondaryText)
            Text(reached
                 ? String(localized: "Goal reached! Well walked, everyone.")
                 : String(localized: "\(StepFormatter.count(max(goal - total, 0))) more to go, together"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(reached ? Color.goalText : Color.accentText)
                .padding(.top, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The family's total against the goal. Past 100% the ring turns the goal
/// colour and keeps going round: a celebration, never capped, never red.
struct ProgressRing: View {
    let fraction: Double
    let percent: Int
    let reached: Bool
    private let base: CGFloat
    @ScaledMetric private var diameter: CGFloat

    init(fraction: Double, percent: Int, reached: Bool, diameter: CGFloat = 124) {
        self.fraction = fraction
        self.percent = percent
        self.reached = reached
        self.base = diameter
        _diameter = ScaledMetric(wrappedValue: diameter, relativeTo: .largeTitle)
    }

    var body: some View {
        // Capped so at accessibility sizes the ring doesn't fill the tile;
        // the text around it grows instead.
        let size = min(diameter, base * 1.3)
        let lineWidth = size * 0.11
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
            VStack(spacing: 2) {
                if reached {
                    Icon.celebrate.size(size * 0.17).foregroundStyle(.goalText)
                }
                Text("\(percent)%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(lineWidth + 6)
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.8), value: fraction)
    }
}

// MARK: - Half tiles

/// A small (half-width) tile.
struct SmallTile<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Bento.smallPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .bentoSurface(radius: Bento.smallRadius)
    }
}

/// "Status" (set one) or "Your status" (change it). Opens the status picker.
struct StatusTile: View {
    let status: MemberStatus?
    let action: () -> Void
    @Environment(\.now) private var now
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22

    var body: some View {
        let active = status.flatMap { $0.isActive(at: now()) ? $0 : nil }
        Button(action: action) {
            SmallTile {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ((active?.preset?.icon) ?? (active == nil ? .edit : .statusCustom)).size(iconSize)
                            .foregroundStyle(.accentText)
                        Spacer(minLength: 4)
                        Icon.chevronRight.size(16).foregroundStyle(.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(active == nil ? "Status" : "Your status")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondaryText)
                        Text(active?.displayText ?? String(localized: "Set my status"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(.rect(cornerRadius: Bento.smallRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active?.displayText.map { Text("Your status: \($0)") } ?? Text("Set my status"))
        .accessibilityHint(Text("Choose what your family sees next to your name."))
    }
}

/// When the viewer's own steps last reached the family.
struct SyncTile: View {
    let lastSyncedAt: Date?
    let isSyncing: Bool
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22

    var body: some View {
        SmallTile {
            VStack(alignment: .leading, spacing: 10) {
                if isSyncing {
                    OrbLoader(activity: .syncingSteps, compact: true)
                        .frame(height: iconSize)
                } else {
                    Icon.clock.size(iconSize).foregroundStyle(.secondaryText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your steps")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondaryText)
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Group {
                            if isSyncing {
                                Text("Sending…")
                            } else if let lastSyncedAt {
                                Text("Synced \(lastSyncedAt, format: .relative(presentation: .named))")
                            } else {
                                Text("Not synced yet")
                            }
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    }
                    if !isSyncing && lastSyncedAt == nil {
                        Text("Pull down to try.")
                            .font(.footnote)
                            .foregroundStyle(.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Everyone today

struct ContributionsCard: View {
    let members: [FamilyMember]
    let currentUserId: String?
    /// Today's family total; each bar is a member's share of it.
    var familyTotal: Int = 0
    @Environment(\.now) private var now

    var body: some View {
        // Ticks so a walk or status drops off when it ends, without waiting
        // for the next refresh.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            card(now: now())
        }
    }

    private func card(now: Date) -> some View {
        Card(title: "Everyone today", icon: .family) {
            VStack(alignment: .leading, spacing: 18) {
                // Fixed family order: shares are shown, never ranked.
                ForEach(members) { member in
                    MemberRow(member: member, isYou: member.userId == currentUserId, now: now, share: share(of: member))
                }
            }
        }
    }

    private func share(of member: FamilyMember) -> Double {
        guard familyTotal > 0, let steps = member.steps, steps > 0 else { return 0 }
        return min(Double(steps) / Double(familyTotal), 1)
    }
}

struct MemberRow: View {
    let member: FamilyMember
    let isYou: Bool
    var now: Date = .now
    /// The member's share of today's family total, 0...1.
    var share: Double = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var crownSize: CGFloat = 15

    private var displayName: String {
        isYou ? String(localized: "\(member.name) (you)") : member.name
    }

    private var isWalking: Bool {
        member.activeWalk.map { !$0.isOver(at: now) } ?? false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: member.name, hex: member.avatarColor)
                .overlay(alignment: .bottomTrailing) {
                    if isWalking { WalkingDot().offset(x: 4, y: 4) }
                }
            VStack(alignment: .leading, spacing: 8) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(displayName)
                                .font(.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                // The crown says it visually; VoiceOver gets the word.
                                .accessibilityLabel(member.isOrganiser ? Text("\(displayName), organiser") : Text(displayName))
                            if member.isOrganiser {
                                Icon.organiser.size(crownSize)
                                    .foregroundStyle(.accentText)
                            }
                        }
                        if isWalking {
                            Text("Walking now")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.accentText)
                        }
                        StatusLabel(status: member.status, now: now)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    steps
                }
                ShareBar(share: share, color: Color(hex: member.avatarColor))
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var steps: some View {
        if let value = member.steps {
            Text(StepFormatter.count(value))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel(Text(StepFormatter.withUnit(value)))
        } else {
            Text("not synced yet")
                .font(.subheadline)
                .foregroundStyle(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A thin bar in the member's colour: their share of today's family total.
/// Not a ranking; the family order stays fixed.
struct ShareBar: View {
    let share: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(.surfaceMuted)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: share > 0 ? max(proxy.size.width * share, 4) : 0)
                }
            }
            .animation(.spring(duration: 0.6), value: share)
            .accessibilityHidden(true)
    }
}

// MARK: - Family moments

struct FeedCard: View {
    let model: FeedModel
    var highlightedEventId: String?

    var body: some View {
        Card(title: "Family moments", icon: .moments) {
            FeedList(model: model, highlightedEventId: highlightedEventId)
                .id(model.familyId)
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
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TileLabel("This week", icon: .calendar)
                        Spacer(minLength: 8)
                        // One line, so ViewThatFits falls back to the stack
                        // when it doesn't fit beside the label.
                        hits.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TileLabel("This week", icon: .calendar)
                        // Stacked fallback: the summary may wrap here.
                        hits.fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder
    private var hits: some View {
        if hitCount > 0 {
            Text(hitCount == 1 ? String(localized: "Goal reached on 1 day") : String(localized: "Goal reached on \(hitCount) days"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.goalText)
        }
    }
}

struct WeekDayMarker: View {
    let day: FamilyWeekDay
    let isToday: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    private var date: Date? { NepalDay.start(of: day.day) }

    var body: some View {
        VStack(spacing: 6) {
            Text(date.map { $0.formatted(Date.FormatStyle(timeZone: NepalDay.timeZone).weekday(.narrow)) } ?? "")
                .font(.footnote.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.accentText : Color.secondaryText)
                .opacity(day.isBeforeFamily ? 0.5 : 1)
            ZStack {
                if day.hit {
                    Circle().fill(.goal)
                    Icon.tick.size(size * 0.5).foregroundStyle(.white)
                } else if day.isBeforeFamily {
                    Circle().fill(Color.surfaceMuted.opacity(0.5))
                } else if day.isFuture {
                    Circle().strokeBorder(Color.secondaryText.opacity(0.3), lineWidth: 1)
                } else if !isToday {
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
