import Foundation
import Observation

/// Whose steps History shows: the family's total, or your own. Never another
/// member's (user decision, PRD no-ranking rule).
enum HistoryTab: String, CaseIterable, Identifiable, Sendable {
    case family, me

    var id: Self { self }

    var title: String {
        switch self {
        case .family: String(localized: "Family")
        case .me: String(localized: "Me")
        }
    }
}

enum HistoryRange: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Self { self }
    var days: Int { rawValue }
    var title: String { String(localized: "\(rawValue) days") }
}

/// One bar on the chart: a Nepal day with data (never a day before the
/// family existed, or before Health had any steps for you).
struct HistoryDay: Hashable, Sendable, Identifiable {
    /// Nepal day, "YYYY-MM-DD".
    let day: String
    let steps: Int
    /// The family goal that day; `nil` on the Me tab.
    let goal: Int?
    let hit: Bool

    var id: String { day }
}

/// The plain-words lines under the chart, as numbers first so they can be
/// tested, then worded by `lines`.
struct HistoryTrend: Hashable, Sendable {
    let range: Int
    /// Family only: the goal was reached on `goalHits` of `countedDays`.
    var goalHits: Int?
    var countedDays: Int
    var dailyAverage: Int
    /// Change in the daily average against the `range` days before, in
    /// percent (unrounded). `nil` when the earlier days have no data.
    var change: Double?
    var best: HistoryDay?

    /// Within this many percent either way reads "about the same".
    static let sameBand = 3.0

    /// `current` is the shown days, `previous` the ones before, both without
    /// the no-data days. Today is still going, so it's left out of the
    /// average (unless it's the only day) but counts for goal and best day.
    /// When today is left out, the matching day `range` days earlier is left
    /// out of the comparison too, so finished days are compared with the
    /// same weekdays one period before (N−1 against N−1).
    static func compute(current: [HistoryDay], previous: [HistoryDay], range: Int, today: String, withGoal: Bool) -> HistoryTrend? {
        guard !current.isEmpty else { return nil }
        let finished = current.filter { $0.day != today }
        let todayLeftOut = !finished.isEmpty && finished.count < current.count
        let averaged = finished.isEmpty ? current : finished
        let average = Self.average(averaged)
        var compared = previous
        if todayLeftOut, let matching = Self.day(range, before: today) {
            compared.removeAll { $0.day == matching }
        }
        var change: Double?
        let earlier = Self.average(compared)
        if !compared.isEmpty, earlier > 0 {
            change = (Double(average) - Double(earlier)) / Double(earlier) * 100
        }
        // The most recent of equal best days.
        let best = current.reduce(nil as HistoryDay?) { best, day in
            guard let best else { return day }
            return day.steps >= best.steps ? day : best
        }
        return HistoryTrend(
            range: range,
            goalHits: withGoal ? current.filter(\.hit).count : nil,
            countedDays: current.count,
            dailyAverage: average,
            change: change,
            best: (best?.steps ?? 0) > 0 ? best : nil
        )
    }

    /// The Nepal day `count` days before `day`.
    private static func day(_ count: Int, before day: String) -> String? {
        guard let start = NepalDay.start(of: day),
              let earlier = NepalDay.calendar.date(byAdding: .day, value: -count, to: start) else { return nil }
        return NepalDay.string(for: earlier)
    }

    private static func average(_ days: [HistoryDay]) -> Int {
        guard !days.isEmpty else { return 0 }
        return Int((Double(days.reduce(0) { $0 + $1.steps }) / Double(days.count)).rounded())
    }

    /// "Goal reached on 4 of 7 days", "Daily average 48,200", "Up 12% on the
    /// previous 7 days", "Best day: Sat 15 Nov · 61,400". Supportive: a drop
    /// is said plainly, never as a failure.
    func lines(locale: Locale = .current) -> [String] {
        var lines: [String] = []
        if let goalHits {
            lines.append(countedDays == 1
                ? String(localized: "Goal reached on \(goalHits) of 1 day")
                : String(localized: "Goal reached on \(goalHits) of \(countedDays) days"))
        }
        lines.append(String(localized: "Daily average \(StepFormatter.count(dailyAverage, locale: locale))"))
        if let change {
            let percent = Int(abs(change).rounded())
            if abs(change) <= Self.sameBand {
                lines.append(String(localized: "About the same as the previous \(range) days"))
            } else if change > 0 {
                lines.append(String(localized: "Up \(percent)% on the previous \(range) days"))
            } else {
                lines.append(String(localized: "Down \(percent)% on the previous \(range) days"))
            }
        }
        if let best {
            let date = HistoryFormat.shortDate(best.day, locale: locale)
            lines.append(String(localized: "Best day: \(date) · \(StepFormatter.count(best.steps, locale: locale))"))
        }
        return lines
    }
}

/// Nepal-day labels for History.
enum HistoryFormat {
    /// "Sat 15 Nov" (in the phone's language order).
    static func shortDate(_ day: String, locale: Locale = .current) -> String {
        guard let date = NepalDay.start(of: day) else { return day }
        return date.formatted(Date.FormatStyle(locale: locale, timeZone: NepalDay.timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "15 Nov".
    static func dayMonth(_ day: String, locale: Locale = .current) -> String {
        guard let date = NepalDay.start(of: day) else { return day }
        return date.formatted(Date.FormatStyle(locale: locale, timeZone: NepalDay.timeZone).day().month(.abbreviated))
    }

    /// "Sat", or "S" when space is tight.
    static func weekday(_ day: String, narrow: Bool = false, locale: Locale = .current) -> String {
        guard let date = NepalDay.start(of: day) else { return day }
        return date.formatted(Date.FormatStyle(locale: locale, timeZone: NepalDay.timeZone).weekday(narrow ? .narrow : .abbreviated))
    }

    /// "Saturday 15 November".
    static func longDate(_ day: String, locale: Locale = .current) -> String {
        guard let date = NepalDay.start(of: day) else { return day }
        return date.formatted(Date.FormatStyle(locale: locale, timeZone: NepalDay.timeZone).weekday(.wide).day().month(.wide))
    }
}

/// The History screen: the family's daily totals (backend) or your own
/// steps (Apple Health on this phone, no backend call), over 7, 30 or 90
/// Nepal days, with trend lines.
@MainActor
@Observable
final class HistoryModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
        /// Nothing to chart, said in a plain sentence (no Health access, no
        /// steps yet). Not an error.
        case empty(String)
    }

    struct Key: Hashable {
        var tab: HistoryTab
        var range: HistoryRange
    }

    private struct Content {
        var phase: Phase
        var days: [HistoryDay] = []
        var trend: HistoryTrend?
    }

    var tab: HistoryTab = .family
    var range: HistoryRange = .week
    private(set) var phase: Phase = .loading
    /// The shown days, oldest first, without no-data days.
    private(set) var days: [HistoryDay] = []
    private(set) var trend: HistoryTrend?

    private let service: any FamilyService
    private let familyId: String
    private let source: any StepSource
    private let now: @Sendable () -> Date
    @ObservationIgnored private var cache: [Key: Content] = [:]

    init(service: any FamilyService, familyId: String, source: any StepSource, now: @escaping @Sendable () -> Date = { .now }) {
        self.service = service
        self.familyId = familyId
        self.source = source
        self.now = now
    }

    var key: Key { Key(tab: tab, range: range) }
    var trendLines: [String] { trend?.lines() ?? [] }

    /// The family goal line: the latest shown day's goal.
    var goal: Int? { tab == .family ? days.last?.goal : nil }

    /// Loads the selected tab and range (cached until `reload`).
    func load() async {
        let key = key
        if let cached = cache[key] {
            apply(cached)
            return
        }
        if phase != .loading { phase = .loading }
        let content: Content
        do {
            switch key.tab {
            case .family: content = try await loadFamily(key.range)
            case .me: content = await loadMe(key.range)
            }
        } catch is CancellationError {
            return
        } catch let error as FamilyServiceError {
            content = Content(phase: .failed(error.message))
        } catch {
            content = Content(phase: .failed(FamilyServiceError.unavailable("").message))
        }
        guard !Task.isCancelled else { return }
        if case .loaded = content.phase { cache[key] = content }
        if key == self.key { apply(content) }
    }

    /// Pull to refresh: forgets everything loaded and loads again.
    func reload() async {
        cache = [:]
        await load()
    }

    private func apply(_ content: Content) {
        phase = content.phase
        days = content.days
        trend = content.trend
    }

    private func loadFamily(_ range: HistoryRange) async throws -> Content {
        let history = try await service.familyHistory(familyId: familyId, days: range.days)
        let (current, previous) = Self.split(history, range: range.days)
        let trend = HistoryTrend.compute(current: current, previous: previous, range: range.days, today: history.today, withGoal: true)
        return Content(phase: .loaded, days: current, trend: trend)
    }

    private func loadMe(_ range: HistoryRange) async -> Content {
        guard source.isAvailable else {
            return Content(phase: .empty(String(localized: "Apple Health isn't on this device, so there are no steps of yours to show here.")))
        }
        guard await source.hasRequestedAuthorization() else {
            return Content(phase: .empty(String(localized: "Let Hamro Steps read your steps in Apple Health to see them here.")))
        }
        let date = now()
        let calendar = NepalDay.calendar
        let count = 2 * range.days
        let start = StepHistory.windowStart(days: count, endingAt: date, calendar: calendar)
        let totals: [Date: Int]
        do {
            totals = try await source.dailyStepTotals(from: start, to: date, calendar: calendar)
        } catch {
            return Content(phase: .empty(String(localized: "We couldn't read your steps from Apple Health just now. Pull down to try again.")))
        }
        let daily = StepHistory.lastDays(count, endingAt: date, calendar: calendar, totals: totals)
        let recorded = Set(totals.keys.map { NepalDay.string(for: calendar.startOfDay(for: $0)) })
        let (current, previous) = Self.split(daily, recorded: recorded, range: range.days)
        guard !current.isEmpty else {
            return Content(phase: .empty(String(localized: "No steps from Apple Health for these days yet. If you turned off access, you can turn it back on in the Health app.")))
        }
        let trend = HistoryTrend.compute(current: current, previous: previous, range: range.days, today: NepalDay.string(for: date), withGoal: false)
        return Content(phase: .loaded, days: current, trend: trend)
    }

    /// The last `range` days and the `range` before them, without days from
    /// before the family existed.
    nonisolated static func split(_ history: FamilyHistory, range: Int) -> (current: [HistoryDay], previous: [HistoryDay]) {
        let all = history.days.map { (isBefore: $0.isBeforeFamily, day: HistoryDay(day: $0.day, steps: $0.total, goal: $0.goal, hit: $0.hit)) }
        let current = all.suffix(range).filter { !$0.isBefore }.map { $0.day }
        let previous = all.dropLast(range).suffix(range).filter { !$0.isBefore }.map { $0.day }
        return (current, previous)
    }

    /// The same for your own steps. `recorded` is the Nepal days Health
    /// returned an entry for (even 0 steps). Days before the first recorded
    /// day in the window count as no data (a new phone, or Health turned on
    /// later), so they don't drag the average down; after it, every day is
    /// data, zeros included. No recorded day at all means no data.
    nonisolated static func split(_ daily: [DailySteps], recorded: Set<String>, range: Int) -> (current: [HistoryDay], previous: [HistoryDay]) {
        guard let first = daily.firstIndex(where: { recorded.contains(NepalDay.string(for: $0.date)) }) else { return ([], []) }
        let days = daily.enumerated().map { index, entry in
            (hasData: index >= first, day: HistoryDay(day: NepalDay.string(for: entry.date), steps: entry.steps, goal: nil, hit: false))
        }
        let current = days.suffix(range).filter { $0.hasData }.map { $0.day }
        let previous = days.dropLast(range).suffix(range).filter { $0.hasData }.map { $0.day }
        return (current, previous)
    }
}
