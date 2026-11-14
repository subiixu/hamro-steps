import Foundation
import Observation

/// What Home shows for the selected family: today's ring and contributions
/// (live), and this week's markers.
@MainActor
@Observable
final class HomeModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private static let selectedKey = "home.selectedFamilyId"

    private(set) var families: [FamilySummary] = []
    private(set) var selectedFamilyId: String?
    private(set) var today: FamilyToday?
    private(set) var week: [FamilyWeekDay] = []
    private(set) var phase: Phase = .loading
    /// The Nepal day the loaded week was built for.
    private(set) var loadedDay: String?
    /// A feed event to bring into view, from a tapped notification. Home
    /// scrolls to it once its feed has loaded, then takes it with
    /// `takeFocus()` so it's shown once.
    private(set) var focusEventId: String?

    private let service: any FamilyService
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    /// The running `familyTodayUpdates` loop, cancelled to re-subscribe.
    @ObservationIgnored private var subscription: Task<Void, Never>?
    @ObservationIgnored private var resubscribeRequested = false
    /// Sleeps until the next Nepal midnight; replaced on every time change.
    @ObservationIgnored private var midnightTimer: Task<Void, Never>?
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        service: any FamilyService,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        selectedFamilyId = defaults.string(forKey: Self.selectedKey)
    }

    // MARK: Derived

    var selectedFamily: FamilySummary? {
        today?.family ?? families.first { $0.id == selectedFamilyId }
    }

    var showsSwitcher: Bool { families.count > 1 }

    /// Fixed family order (join order, organiser first), never by steps.
    var members: [FamilyMember] {
        (today?.members ?? []).sorted { $0.position < $1.position }
    }

    var total: Int { today?.total ?? 0 }
    var goal: Int { today?.goal ?? selectedFamily?.dailyGoal ?? 0 }
    var percent: Int { today?.percent ?? 0 }

    /// How far round the ring goes; past 1 means the goal was beaten.
    var ringFraction: Double {
        guard goal > 0 else { return 0 }
        return Double(total) / Double(goal)
    }

    var isGoalReached: Bool { goal > 0 && total >= goal }

    func isOrganiser(_ userId: String?) -> Bool {
        members.first { $0.userId == userId }?.isOrganiser ?? false
    }

    // MARK: Loading

    /// The session's family list changed (sign-in, create, join, leave).
    /// Keeps the selection when it's still there, else picks the first.
    func update(families newFamilies: [FamilySummary]) async {
        families = newFamilies
        let keep = newFamilies.contains { $0.id == selectedFamilyId }
        await select(keep ? selectedFamilyId : newFamilies.first?.id)
    }

    /// Show this family next time the list updates (a family just created
    /// or joined), without loading anything yet.
    func prefer(_ familyId: String) {
        selectedFamilyId = familyId
        defaults.set(familyId, forKey: Self.selectedKey)
    }

    /// Ask Home to bring this feed event into view (see `focusEventId`).
    func focus(eventId: String) {
        focusEventId = eventId
    }

    /// The event to bring into view, handed out once: later calls return
    /// nil until `focus(eventId:)` sets a new one.
    func takeFocus() -> String? {
        defer { focusEventId = nil }
        return focusEventId
    }

    func select(_ familyId: String?) async {
        selectedFamilyId = familyId
        defaults.set(familyId, forKey: Self.selectedKey)
        if today?.family.id != familyId {
            today = nil
            week = []
        }
        await reload()
    }

    func reload() async {
        guard let familyId = selectedFamilyId else {
            phase = .loading
            return
        }
        if today == nil { phase = .loading }
        do {
            async let todayResult = service.familyToday(familyId: familyId)
            async let weekResult = service.familyWeek(familyId: familyId)
            let (newToday, newWeek) = try await (todayResult, weekResult)
            guard familyId == selectedFamilyId else { return }
            today = newToday
            week = newWeek.days
            loadedDay = newWeek.today
            phase = .loaded
        } catch is CancellationError {
            return
        } catch let error as FamilyServiceError {
            if today == nil { phase = .failed(error.message) }
        } catch {
            if today == nil { phase = .failed(FamilyServiceError.unavailable("").message) }
        }
    }

    /// Live updates for the selected family until the task is cancelled.
    /// `refresh()` drops the subscription and opens a new one, so a backend
    /// query pinned to yesterday's Nepal day is replaced.
    func listen() async {
        while !Task.isCancelled {
            guard let familyId = selectedFamilyId else { return }
            resubscribeRequested = false
            let inner = Task { await self.consume(familyId) }
            subscription = inner
            await withTaskCancellationHandler { await inner.value } onCancel: { inner.cancel() }
            guard !Task.isCancelled, familyId == selectedFamilyId, resubscribeRequested else { return }
        }
    }

    /// Today's total also feeds today's week marker, so they never disagree.
    /// An update for a day the week wasn't built for means the Nepal day
    /// rolled over: the week is reloaded so markers and dates move on.
    private func consume(_ familyId: String) async {
        for await update in service.familyTodayUpdates(familyId: familyId) {
            guard familyId == selectedFamilyId, !Task.isCancelled else { return }
            today = update
            phase = .loaded
            if let loadedDay, update.day != loadedDay {
                await reload()
                continue
            }
            if let index = week.firstIndex(where: { $0.day == update.day }) {
                week[index].total = update.total
                week[index].goal = update.goal
                week[index].hit = update.total >= update.goal
            }
        }
    }

    // MARK: Rollover

    /// Today and the whole week again, with a fresh live subscription. Runs
    /// on foreground and when the Nepal day changes.
    func refresh() async {
        resubscribeRequested = true
        subscription?.cancel()
        await reload()
    }

    /// After a successful step sync: reload and re-open the live
    /// subscription. A plain `reload()` could advance `loadedDay` past
    /// midnight while the subscription stays pinned to yesterday, and then
    /// `refreshIfDayChanged()` would never re-open it.
    func syncFinished() async {
        await refresh()
    }

    /// Refreshes if the Nepal day moved on since the week was loaded (the
    /// midnight timer fired, or the clock or time zone changed).
    func refreshIfDayChanged() async {
        guard let loadedDay, NepalDay.string(for: now()) != loadedDay else { return }
        await refresh()
    }

    /// While the app is active: wakes at each Nepal midnight (18:15 UTC) and
    /// on significant time changes, and refreshes when the day moved on.
    /// Ends when the task is cancelled.
    func watchDayChanges(timeChanges: AsyncStream<Void>) async {
        scheduleMidnight()
        for await _ in timeChanges {
            // The clock jumped: the old wait was measured from the old time.
            scheduleMidnight()
            await refreshIfDayChanged()
        }
        guard !Task.isCancelled, let timer = midnightTimer else {
            midnightTimer?.cancel()
            midnightTimer = nil
            return
        }
        await withTaskCancellationHandler { await timer.value } onCancel: { timer.cancel() }
    }

    /// Cancels the pending midnight wait and starts one measured from now.
    private func scheduleMidnight() {
        midnightTimer?.cancel()
        midnightTimer = Task { [weak self, sleep] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = Self.nextNepalMidnight(after: self.now()).timeIntervalSince(self.now())
                // A second late, so the new day has surely begun.
                do { try await sleep(.seconds(max(wait, 0) + 1)) } catch { return }
                guard !Task.isCancelled else { return }
                await self.refreshIfDayChanged()
            }
        }
    }

    /// The next Nepal midnight strictly after `date`.
    nonisolated static func nextNepalMidnight(after date: Date) -> Date {
        let calendar = NepalDay.calendar
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }
}
