import Foundation

/// In-memory `ActivityService` with a realistic family, for previews, the
/// debug gallery and tests. It applies the contract's rules itself (walk
/// limit per Nepal day, auto-stop, status validation, reaction toggling,
/// 3-day feed window), so the UI behaves as it will against Convex.
actor MockActivityService: ActivityService {
    static let familyId = "family-sharma"

    static let me = FeedActor(userId: "user-anish", name: "Anish", avatarColor: "#2E86AB")
    static let mum = FeedActor(userId: "user-mum", name: "Mum", avatarColor: "#D45D79")
    static let dad = FeedActor(userId: "user-dad", name: "Dad", avatarColor: "#8C5E58")
    static let ram = FeedActor(userId: "user-ram", name: "Ram", avatarColor: "#3BB273")
    static let priya = FeedActor(userId: "user-priya", name: "Priya", avatarColor: "#7768AE")

    private let now: @Sendable () -> Date
    private let latency: Duration
    private let calendar = ActivityTime.nepalCalendar

    private var walkStarts: [Date]
    private var walk: ActiveWalk?
    private var status: MemberStatus?
    private var events: [FeedEvent]
    private var prefs = NotificationPrefs.defaults
    private var devices: [String: APNsEnvironment] = [:]
    private var nextId = 1
    /// Makes the next call fail, to show error states.
    private var failNext: (any Error)?

    /// - Parameters:
    ///   - latency: delay before each call returns, to show loading states.
    ///   - walksStartedToday: walks already started today, to show the limit.
    ///   - sampleFeed: start with the sample feed (`false`: empty feed).
    init(
        now: @escaping @Sendable () -> Date = { .now },
        latency: Duration = .zero,
        walksStartedToday: Int = 0,
        sampleFeed: Bool = true
    ) {
        let start = now()
        self.now = now
        self.latency = latency
        self.walkStarts = Array(repeating: start.addingTimeInterval(-60), count: walksStartedToday)
        self.events = sampleFeed ? Self.sampleEvents(now: start) : []
    }

    // MARK: Test and gallery helpers

    func failNextCall(with error: any Error) { failNext = error }

    /// The viewer's walk, as `familyToday` would report it.
    func currentWalk() -> ActiveWalk? {
        guard let walk, !walk.isOver(at: now()) else { return nil }
        return walk
    }

    /// The viewer's status, as `familyToday` would report it.
    func currentStatus() -> MemberStatus? {
        guard let status, status.isActive(at: now()) else { return nil }
        return status
    }

    func registeredDevices() -> [String: APNsEnvironment] { devices }

    // MARK: ActivityService

    func startWalk() async throws -> WalkStart {
        try await step()
        let now = now()
        if let walk, !walk.isOver(at: now) { throw ActivityError.alreadyWalking }
        let today = walkStarts.filter { calendar.isDate($0, inSameDayAs: now) }
        guard today.count < WalkRules.dailyLimit else { throw ActivityError.walkLimitReached }

        let started = ActiveWalk(startedAt: now, endsAt: now.addingTimeInterval(WalkRules.duration))
        walk = started
        walkStarts.append(now)
        let walkId = makeId("walk")
        events.insert(FeedEvent(
            id: makeId("event"), type: .walkStarted, actor: Self.me, day: dayKey(now),
            createdAt: ActivityTime.millis(now), data: FeedEventData(walkId: walkId)
        ), at: 0)
        return WalkStart(walkId: walkId, startedAt: ActivityTime.millis(started.startedAt), endsAt: ActivityTime.millis(started.endsAt))
    }

    func stopWalk() async throws {
        try await step()
        walk = nil
    }

    func setStatus(_ input: StatusInput) async throws {
        try await step()
        let now = now()
        let checked = try StatusInput.validated(
            preset: input.preset, text: input.text,
            expiresAt: input.expiresAt.map(ActivityTime.date), now: now
        )
        let expiry = checked.expiresAt ?? ActivityTime.millis(now.addingTimeInterval(StatusInput.defaultDuration))
        status = MemberStatus(preset: checked.preset, text: checked.text, expiresAt: expiry)
    }

    func clearStatus() async throws {
        try await step()
        status = nil
    }

    func feed(familyId: String) async throws -> [FeedEvent] {
        try await step()
        guard familyId == Self.familyId else { throw ActivityError.notMember }
        let now = now()
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        return events
            .filter { $0.createdDate >= windowStart }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(100)
            .map { $0 }
    }

    func react(eventId: String, emoji: Reaction) async throws {
        try await step()
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { throw ActivityError.notMember }
        events[index] = events[index].reacting(with: emoji)
    }

    func notificationPrefs() async throws -> NotificationPrefs {
        try await step()
        return prefs
    }

    func setNotificationPrefs(_ patch: NotificationPrefsPatch) async throws {
        try await step()
        prefs = prefs.applying(patch)
    }

    func registerDevice(apnsToken: String, environment: APNsEnvironment) async throws {
        try await step()
        devices[apnsToken] = environment
    }

    func unregisterDevice(apnsToken: String) async throws {
        try await step()
        devices[apnsToken] = nil
    }

    // MARK: Private

    private func step() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        if let error = failNext {
            failNext = nil
            throw error
        }
    }

    private func makeId(_ prefix: String) -> String {
        defer { nextId += 1 }
        return "\(prefix)-mock-\(nextId)"
    }

    private func dayKey(_ date: Date) -> String {
        Self.dayKey(date, calendar: calendar)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A believable couple of days in one family, newest first, plus one
    /// event from 4 days ago that the 3-day window leaves out.
    static func sampleEvents(now: Date) -> [FeedEvent] {
        let calendar = ActivityTime.nepalCalendar
        func event(_ id: String, _ type: FeedEventType, _ actor: FeedActor?, minutesAgo: Double,
                   _ reactions: [Reaction: Int] = [:], mine: Reaction? = nil) -> FeedEvent {
            let date = now.addingTimeInterval(-minutesAgo * 60)
            return FeedEvent(
                id: id, type: type, actor: actor, day: dayKey(date, calendar: calendar),
                createdAt: ActivityTime.millis(date),
                data: type == .walkStarted ? FeedEventData(walkId: "walk-\(id)") : nil,
                reactions: Reaction.allCases.compactMap { e in reactions[e].map { ReactionCount(emoji: e, count: $0) } },
                myReaction: mine
            )
        }
        return [
            event("e1", .walkStarted, ram, minutesAgo: 6, [.clap: 1]),
            event("e2", .family50, nil, minutesAgo: 34, [.raisedHands: 3, .fire: 1], mine: .raisedHands),
            event("e3", .member5k, mum, minutesAgo: 80, [.clap: 2, .heart: 3], mine: .heart),
            event("e4", .member10k, me, minutesAgo: 190, [.fire: 2, .laugh: 1]),
            event("e5", .family100, nil, minutesAgo: 60 * 22, [.clap: 4, .raisedHands: 2, .laugh: 1], mine: .clap),
            event("e6", .member5k, dad, minutesAgo: 60 * 26, [.heart: 2]),
            event("e7", .walkStarted, priya, minutesAgo: 60 * 28),
            event("e-old", .member5k, priya, minutesAgo: 60 * 24 * 4),
        ]
    }
}
