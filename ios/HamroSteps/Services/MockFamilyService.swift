import Foundation

/// In-memory backend for this phase and for tests. Behaves like the Convex
/// API (handoffs/2026-11-14-1403-convex-core.md, "API reference"): same
/// errors, fixed family order, `steps: nil` until a member syncs, Nepal days,
/// live updates after every change.
actor MockFamilyService: FamilyService {
    static let preview = MockFamilyService.sample(signedIn: true)

    /// The sample user the mock signs in as.
    static let sampleUserId = "u_priya"
    /// Code of a sample family that already has 8 people.
    static let fullFamilyCode = "WXYZ22"

    fileprivate struct StoredUser {
        var name: String?
        var avatarColor: String
        var timezone: String?
    }

    fileprivate struct StoredFamily {
        let id: String
        var name: String
        var dailyGoal: Int
        var inviteCode: String
        /// Join order, organiser first.
        var memberIds: [String]
        var organiserId: String
        /// Nepal day the family was created.
        var createdDay: String
        /// Closed days: Nepal day → the midnight snapshot (frozen goal).
        var closedDays: [String: ClosedDay] = [:]
    }

    /// Mirrors the backend's midnight snapshot plus `dayContributions`: the
    /// goal is frozen at the close, and a late sync replaces the contribution
    /// of a member who counted at that midnight.
    fileprivate struct ClosedDay {
        var goal: Int
        /// Members at the close → their steps for the day.
        var contributions: [String: Int]
        /// Seeded sample totals with no per-member breakdown.
        var unattributed: Int = 0
        var total: Int { unattributed + contributions.values.reduce(0, +) }
        var hit: Bool { total >= goal }
    }

    private var users: [String: StoredUser]
    private var families: [String: StoredFamily]
    private var familyOrder: [String]
    /// userId → Nepal day → steps.
    private var steps: [String: [String: Int]]
    private var lastSyncedAt: [String: Double]
    private var signedInUserId: String?
    private var listeners: [String: [UUID: AsyncStream<FamilyToday>.Continuation]] = [:]
    private let delay: Duration
    private let now: @Sendable () -> Date
    private var nextId = 1
    /// The Nepal day still open; earlier days get snapshots on the next call.
    private var openDay: String

    /// Every call, by name, in order (for tests).
    private(set) var calls: [String] = []
    private(set) var lastSyncedDays: [StepDay] = []

    init(delay: Duration = .zero, now: @escaping @Sendable () -> Date = { .now }) {
        self.init(seed: Seed(), delay: delay, now: now)
    }

    fileprivate init(seed: Seed, delay: Duration, now: @escaping @Sendable () -> Date) {
        users = seed.users
        families = Dictionary(uniqueKeysWithValues: seed.families.map { ($0.id, $0) })
        familyOrder = seed.families.map(\.id)
        steps = seed.steps
        lastSyncedAt = seed.lastSyncedAt
        signedInUserId = seed.signedInUserId
        self.delay = delay
        self.now = now
        let today = NepalDay.string(for: now())
        // Snapshot the sync window's closed days the seed didn't cover, as if
        // the midnight job had run on each of them.
        let windowStart = NepalDay.calendar.date(byAdding: .day, value: -6, to: NepalDay.start(of: today)!)
            .map(NepalDay.string(for:)) ?? today
        openDay = today
        Self.close(from: windowStart, to: today, families: &families, order: familyOrder, steps: steps)
    }

    // MARK: Session (driven by MockAuthService)

    /// `me()`.
    var currentUser: AppUser? {
        signedInUserId.flatMap(appUser)
    }

    /// `/auth/apple`: finds or creates the sample user.
    @discardableResult
    func signIn(fullName: PersonNameComponents?, timeZone: String?) -> AppUser {
        let id = Self.sampleUserId
        if users[id] == nil {
            users[id] = StoredUser(name: nil, avatarColor: "#E07A3F")
        }
        if let given = fullName?.givenName, users[id]?.name == nil, FamilyRules.isValidName(given) {
            users[id]?.name = FamilyRules.cleanName(given)
        }
        if let timeZone { users[id]?.timezone = timeZone }
        signedInUserId = id
        return appUser(id)!
    }

    /// `updateProfile({name})`, then `me()`.
    func updateMyName(_ name: String) throws -> AppUser {
        let id = try requireUser()
        guard FamilyRules.isValidName(name) else { throw FamilyServiceError.invalidName }
        users[id]?.name = FamilyRules.cleanName(name)
        notify(familiesOf: id)
        return appUser(id)!
    }

    func signOut() {
        signedInUserId = nil
    }

    // MARK: FamilyService

    func createFamily(name: String, dailyGoal: Int) async throws -> FamilySummary {
        try await begin("createFamily")
        let userId = try requireUser()
        guard FamilyRules.isValidName(name) else { throw FamilyServiceError.invalidName }
        guard FamilyRules.goalRange.contains(dailyGoal) else { throw FamilyServiceError.invalidGoal }
        let family = StoredFamily(
            id: makeId("f"), name: FamilyRules.cleanName(name), dailyGoal: dailyGoal, inviteCode: uniqueCode(),
            memberIds: [userId], organiserId: userId, createdDay: NepalDay.string(for: now())
        )
        families[family.id] = family
        familyOrder.append(family.id)
        return view(family)
    }

    func previewInvite(code: String) async throws -> InvitePreview {
        try await begin("previewInvite")
        let userId = try requireUser()
        guard let family = family(withCode: code) else { throw FamilyServiceError.invalidCode }
        let summary = view(family)
        return InvitePreview(
            familyId: family.id, name: family.name, memberCount: summary.memberCount,
            isFull: summary.isFull, alreadyMember: family.memberIds.contains(userId)
        )
    }

    func joinFamily(code: String) async throws -> FamilySummary {
        try await begin("joinFamily")
        let userId = try requireUser()
        guard var family = family(withCode: code) else { throw FamilyServiceError.invalidCode }
        if family.memberIds.contains(userId) { return view(family) }
        guard family.memberIds.count < FamilyRules.maxMembers else { throw FamilyServiceError.familyFull }
        family.memberIds.append(userId)
        families[family.id] = family
        notify(familyId: family.id)
        return view(family)
    }

    func regenerateInviteCode(familyId: String) async throws -> String {
        try await begin("regenerateInviteCode")
        try requireOrganiser(familyId)
        let code = uniqueCode()
        families[familyId]?.inviteCode = code
        notify(familyId: familyId)
        return code
    }

    func removeMember(familyId: String, userId: String) async throws {
        try await begin("removeMember")
        let me = try requireOrganiser(familyId)
        guard userId != me else { throw FamilyServiceError.cannotRemoveSelf }
        guard families[familyId]?.memberIds.contains(userId) == true else { throw FamilyServiceError.notMember }
        drop(userId, from: familyId)
    }

    func updateFamily(familyId: String, name: String, dailyGoal: Int) async throws -> FamilySummary {
        try await begin("updateFamily")
        try requireOrganiser(familyId)
        guard FamilyRules.isValidName(name) else { throw FamilyServiceError.invalidName }
        guard FamilyRules.goalRange.contains(dailyGoal) else { throw FamilyServiceError.invalidGoal }
        families[familyId]?.name = FamilyRules.cleanName(name)
        families[familyId]?.dailyGoal = dailyGoal
        notify(familyId: familyId)
        return view(families[familyId]!)
    }

    func leaveFamily(familyId: String) async throws {
        try await begin("leaveFamily")
        let userId = try requireMember(familyId)
        drop(userId, from: familyId)
    }

    func myFamilies() async throws -> [FamilySummary] {
        try await begin("myFamilies")
        let userId = try requireUser()
        return familyOrder.compactMap { families[$0] }.filter { $0.memberIds.contains(userId) }.map { family in
            var summary = view(family)
            summary.isOrganiser = family.organiserId == userId
            summary.position = family.memberIds.firstIndex(of: userId)
            return summary
        }
    }

    @discardableResult
    func syncSteps(days: [StepDay]) async throws -> SyncStepsResult {
        try await begin("syncSteps")
        let userId = try requireUser()
        let today = NepalDay.string(for: now())
        let oldest = NepalDay.calendar.date(byAdding: .day, value: -6, to: NepalDay.start(of: today)!)
            .map(NepalDay.string(for:)) ?? today
        // The whole batch is checked before anything is written.
        for entry in days {
            // "YYYY-MM-DD" strings compare in date order.
            guard NepalDay.start(of: entry.day) != nil, entry.day <= today, entry.day >= oldest else {
                throw FamilyServiceError.invalidDay
            }
            guard FamilyRules.stepsRange.contains(entry.steps) else { throw FamilyServiceError.invalidSteps }
        }
        for entry in days {
            steps[userId, default: [:]][entry.day] = entry.steps
            // A late sync for a closed day updates each family that counted
            // this user at that midnight; the goal stays frozen.
            guard entry.day < today else { continue }
            for id in familyOrder where families[id]?.closedDays[entry.day]?.contributions[userId] != nil {
                families[id]?.closedDays[entry.day]?.contributions[userId] = entry.steps
            }
        }
        let syncedAt = now().timeIntervalSince1970 * 1000
        lastSyncedDays = days
        lastSyncedAt[userId] = syncedAt
        notify(familiesOf: userId)
        return SyncStepsResult(lastSyncedAt: syncedAt, today: today)
    }

    func deleteMyAccount() async throws {
        try await begin("deleteMyAccount")
        let userId = try requireUser()
        for id in familyOrder where families[id]?.memberIds.contains(userId) == true {
            drop(userId, from: id)
        }
        steps[userId] = nil
        lastSyncedAt[userId] = nil
        users[userId] = nil
        signedInUserId = nil
    }

    func familyToday(familyId: String) async throws -> FamilyToday {
        try await begin("familyToday")
        try requireMember(familyId)
        return snapshot(familyId)!
    }

    func familyWeek(familyId: String) async throws -> FamilyWeek {
        try await begin("familyWeek")
        try requireMember(familyId)
        let family = families[familyId]!
        let date = now()
        let today = NepalDay.string(for: date)
        let week = NepalDay.week(containing: date)
        let days = week.map { day in
            let goal = family.dailyGoal
            if day < today, day >= family.createdDay, let closed = family.closedDays[day] {
                return FamilyWeekDay(day: day, total: closed.total, goal: closed.goal, hit: closed.hit, isFuture: false, isBeforeFamily: false)
            }
            if day > today {
                return FamilyWeekDay(day: day, total: 0, goal: goal, hit: false, isFuture: true, isBeforeFamily: false)
            }
            if day < family.createdDay {
                return FamilyWeekDay(day: day, total: 0, goal: goal, hit: false, isFuture: false, isBeforeFamily: true)
            }
            // Today, and a closed day with no snapshot: live against the current goal.
            let total = liveTotal(family, day: day)
            return FamilyWeekDay(day: day, total: total, goal: goal, hit: total >= goal, isFuture: false, isBeforeFamily: false)
        }
        let start = week.first ?? today
        return FamilyWeek(
            today: today, weekStart: start,
            startsAt: (NepalDay.start(of: start) ?? date).timeIntervalSince1970 * 1000,
            days: days
        )
    }

    nonisolated func familyTodayUpdates(familyId: String) -> AsyncStream<FamilyToday> {
        AsyncStream { continuation in
            let token = UUID()
            continuation.onTermination = { _ in
                Task { await self.stopListening(token, familyId: familyId) }
            }
            Task { await self.startListening(token, familyId: familyId, continuation: continuation) }
        }
    }

    // MARK: Helpers

    private func begin(_ name: String) async throws {
        calls.append(name)
        if delay > .zero { try await Task.sleep(for: delay) }
        closeDaysIfNeeded()
    }

    /// The backend's midnight job, run lazily: every day between the last
    /// open day and today gets a snapshot per family with the goal and
    /// members it had then. Days already snapshotted are left alone.
    private func closeDaysIfNeeded() {
        let today = NepalDay.string(for: now())
        guard openDay < today else { return }
        Self.close(from: openDay, to: today, families: &families, order: familyOrder, steps: steps)
        openDay = today
    }

    /// Snapshots each day in `start..<end` (Nepal day strings).
    private static func close(
        from start: String, to end: String,
        families: inout [String: StoredFamily], order: [String], steps: [String: [String: Int]]
    ) {
        guard var date = NepalDay.start(of: start) else { return }
        var day = start
        while day < end {
            for id in order {
                guard var family = families[id], family.createdDay <= day, family.closedDays[day] == nil else { continue }
                var contributions: [String: Int] = [:]
                for member in family.memberIds { contributions[member] = steps[member]?[day] ?? 0 }
                family.closedDays[day] = ClosedDay(goal: family.dailyGoal, contributions: contributions)
                families[id] = family
            }
            guard let next = NepalDay.calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
            day = NepalDay.string(for: next)
        }
    }

    private func appUser(_ id: String) -> AppUser? {
        guard let user = users[id] else { return nil }
        return AppUser(
            userId: id, name: user.name, needsName: user.name == nil, avatarColor: user.avatarColor,
            timezone: user.timezone, lastSyncedAt: lastSyncedAt[id]
        )
    }

    private func view(_ family: StoredFamily) -> FamilySummary {
        FamilySummary(
            familyId: family.id, name: family.name, dailyGoal: family.dailyGoal, inviteCode: family.inviteCode,
            organiserId: family.organiserId, memberCount: family.memberIds.count,
            isFull: family.memberIds.count >= FamilyRules.maxMembers
        )
    }

    private func family(withCode code: String) -> StoredFamily? {
        guard InviteCode.isValid(code) else { return nil }
        let clean = InviteCode.normalise(code)
        return familyOrder.lazy.compactMap { self.families[$0] }.first { $0.inviteCode == clean }
    }

    private func requireUser() throws -> String {
        guard let id = signedInUserId else { throw FamilyServiceError.notAuthenticated }
        return id
    }

    @discardableResult
    private func requireMember(_ familyId: String) throws -> String {
        let userId = try requireUser()
        guard families[familyId]?.memberIds.contains(userId) == true else { throw FamilyServiceError.notMember }
        return userId
    }

    @discardableResult
    private func requireOrganiser(_ familyId: String) throws -> String {
        let userId = try requireMember(familyId)
        guard families[familyId]?.organiserId == userId else { throw FamilyServiceError.notOrganiser }
        return userId
    }

    private func makeId(_ prefix: String) -> String {
        defer { nextId += 1 }
        return "\(prefix)_\(nextId)"
    }

    private func uniqueCode() -> String {
        let letters = Array(InviteCode.alphabet)
        while true {
            let code = String((0..<InviteCode.length).map { _ in letters.randomElement()! })
            if !families.values.contains(where: { $0.inviteCode == code }) { return code }
        }
    }

    /// Leaving or being removed: the organiser role passes to the
    /// earliest-joined remaining member, and an empty family is deleted.
    private func drop(_ userId: String, from familyId: String) {
        guard var family = families[familyId] else { return }
        family.memberIds.removeAll { $0 == userId }
        if family.memberIds.isEmpty {
            families[familyId] = nil
            familyOrder.removeAll { $0 == familyId }
            listeners[familyId]?.values.forEach { $0.finish() }
            listeners[familyId] = nil
            return
        }
        if family.organiserId == userId {
            family.organiserId = family.memberIds[0]
        }
        families[familyId] = family
        notify(familyId: familyId)
    }

    private func liveTotal(_ family: StoredFamily, day: String) -> Int {
        family.memberIds.reduce(0) { $0 + (steps[$1]?[day] ?? 0) }
    }

    private func snapshot(_ familyId: String) -> FamilyToday? {
        guard let family = families[familyId] else { return nil }
        let day = NepalDay.string(for: now())
        let total = liveTotal(family, day: day)
        let goal = family.dailyGoal
        let members = family.memberIds.enumerated().compactMap { index, id -> FamilyMember? in
            guard let user = users[id] else { return nil }
            return FamilyMember(
                userId: id, name: user.name ?? "", avatarColor: user.avatarColor, position: index,
                isOrganiser: id == family.organiserId, steps: steps[id]?[day], lastSyncedAt: lastSyncedAt[id]
            )
        }
        let percent = goal > 0 ? Int((Double(total) / Double(goal) * 100).rounded(.down)) : 0
        return FamilyToday(family: view(family), day: day, goal: goal, total: total, percent: percent, members: members)
    }

    private func startListening(_ token: UUID, familyId: String, continuation: AsyncStream<FamilyToday>.Continuation) {
        listeners[familyId, default: [:]][token] = continuation
        if let current = snapshot(familyId) { continuation.yield(current) }
    }

    private func stopListening(_ token: UUID, familyId: String) {
        listeners[familyId]?[token] = nil
    }

    private func notify(familyId: String) {
        guard let current = snapshot(familyId) else { return }
        listeners[familyId]?.values.forEach { $0.yield(current) }
    }

    private func notify(familiesOf userId: String) {
        for id in familyOrder where families[id]?.memberIds.contains(userId) == true {
            notify(familyId: id)
        }
    }
}

// MARK: - Sample data

private struct Seed {
    var users: [String: MockFamilyService.StoredUser] = [:]
    var families: [MockFamilyService.StoredFamily] = []
    var steps: [String: [String: Int]] = [:]
    var lastSyncedAt: [String: Double] = [:]
    var signedInUserId: String?
}

extension MockFamilyService {
    /// A family of 5 in fixed order (one never synced), a second smaller
    /// family for the switcher, and a full family to try "family is full".
    /// `newUser` signs in with no name and no families, like a first sign-in.
    static func sample(
        signedIn: Bool,
        newUser: Bool = false,
        delay: Duration = .zero,
        now: @escaping @Sendable () -> Date = { .now }
    ) -> MockFamilyService {
        let date = now()
        let today = NepalDay.string(for: date)
        let todayStart = NepalDay.start(of: today)!
        let longAgo = NepalDay.string(for: date.addingTimeInterval(-60 * 86_400))
        let syncedAt = date.addingTimeInterval(-25 * 60).timeIntervalSince1970 * 1000
        let me = sampleUserId

        var seed = Seed()
        let people: [(String, String?, String)] = [
            (me, newUser ? nil : "Priya", "#E07A3F"),
            ("u_aama", "Aama", "#2C9A76"),
            ("u_buwa", "Buwa", "#4F74C9"),
            ("u_sunita", "Sunita", "#A65DBA"),
            ("u_bikash", "Bikash", "#C28A1E"),
            ("u_rohan", "Rohan", "#3C8FA8"),
            ("u_anju", "Anju", "#C2577A"),
        ] + (1...8).map { ("u_full\($0)", "Member \($0)", "#7A7F87") }
        for (id, name, color) in people {
            seed.users[id] = StoredUser(name: name, avatarColor: color, timezone: id == me ? "Australia/Sydney" : "Asia/Kathmandu")
        }

        // Today's steps. Bikash has never synced, so he has no row at all.
        let todaySteps = [me: 5_240, "u_aama": 8_105, "u_buwa": 3_980, "u_sunita": 12_210, "u_rohan": 9_400, "u_anju": 6_050]
        for (id, value) in todaySteps where !(newUser && id == me) {
            seed.steps[id, default: [:]][today] = value
            seed.lastSyncedAt[id] = syncedAt
        }

        // Closed days earlier this Nepal week: some hit, some not.
        let pastTotals = [52_300, 41_200, 55_800, 60_150, 38_400, 50_900]
        var closed: [String: Int] = [:]
        for (offset, total) in pastTotals.enumerated() {
            guard let day = NepalDay.calendar.date(byAdding: .day, value: -(offset + 1), to: todayStart) else { continue }
            closed[NepalDay.string(for: day)] = total
        }
        // Members counted at each close, with no per-member steps seeded.
        func snapshots(_ totals: [String: Int], goal: Int, members: [String]) -> [String: ClosedDay] {
            totals.mapValues { total in
                ClosedDay(goal: goal, contributions: Dictionary(uniqueKeysWithValues: members.map { ($0, 0) }), unattributed: total)
            }
        }
        let thapa = [me, "u_aama", "u_buwa", "u_sunita", "u_bikash"]
        let cousins = ["u_rohan", me, "u_anju"]

        if !newUser {
            seed.families.append(StoredFamily(
                id: "f_thapa", name: "Thapa Family", dailyGoal: 50_000, inviteCode: "K7M2QX",
                memberIds: thapa, organiserId: me,
                createdDay: longAgo, closedDays: snapshots(closed, goal: 50_000, members: thapa)
            ))
            seed.families.append(StoredFamily(
                id: "f_cousins", name: "Sydney Cousins", dailyGoal: 30_000, inviteCode: "P4RT8N",
                memberIds: cousins, organiserId: "u_rohan",
                createdDay: longAgo, closedDays: snapshots(closed.mapValues { $0 * 3 / 5 }, goal: 30_000, members: cousins)
            ))
        }
        seed.families.append(StoredFamily(
            id: "f_full", name: "Big Family", dailyGoal: 80_000, inviteCode: fullFamilyCode,
            memberIds: (1...8).map { "u_full\($0)" }, organiserId: "u_full1", createdDay: longAgo
        ))
        seed.signedInUserId = signedIn ? me : nil
        return MockFamilyService(seed: seed, delay: delay, now: now)
    }
}
