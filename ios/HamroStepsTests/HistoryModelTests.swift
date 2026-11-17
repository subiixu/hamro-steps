import Foundation
import Testing
@testable import HamroSteps

@MainActor
struct HistoryModelTests {
    /// Tuesday 17 Nov 2026, 3pm in Nepal.
    nonisolated private static let now = TestTime.date("Asia/Kathmandu", 2026, 11, 17, 15)
    nonisolated private static let gb = Locale(identifier: "en_GB")

    private func day(_ offset: Int) -> String {
        let start = NepalDay.start(of: NepalDay.string(for: Self.now))!
        return NepalDay.string(for: NepalDay.calendar.date(byAdding: .day, value: -offset, to: start)!)
    }

    private func bar(_ offset: Int, _ steps: Int, goal: Int? = 50_000) -> HistoryDay {
        HistoryDay(day: day(offset), steps: steps, goal: goal, hit: goal.map { steps >= $0 } ?? false)
    }

    // MARK: Trend numbers

    @Test func averageLeavesOutTodayAndCountsGoalDays() throws {
        let current = [bar(6, 40_000), bar(5, 50_000), bar(4, 60_000), bar(3, 45_000), bar(2, 55_000), bar(1, 50_000), bar(0, 10_000)]
        let trend = try #require(HistoryTrend.compute(current: current, previous: [], range: 7, today: day(0), withGoal: true))
        #expect(trend.dailyAverage == 50_000)
        #expect(trend.goalHits == 4)
        #expect(trend.countedDays == 7)
        #expect(trend.best?.day == day(4))
    }

    @Test func onlyTodayIsAveragedWhenItIsTheOnlyDay() throws {
        let trend = try #require(HistoryTrend.compute(current: [bar(0, 12_000)], previous: [], range: 7, today: day(0), withGoal: true))
        #expect(trend.dailyAverage == 12_000)
        #expect(trend.lines(locale: Self.gb).first == "Goal reached on 0 of 1 day")
    }

    @Test func changeAgainstThePreviousDays() throws {
        let previous = (7...13).map { bar($0, 40_000) }
        let up = try #require(HistoryTrend.compute(current: [bar(2, 44_800), bar(1, 44_800), bar(0, 1_000)], previous: previous, range: 7, today: day(0), withGoal: true))
        #expect(up.lines(locale: Self.gb).contains("Up 12% on the previous 7 days"))

        let down = try #require(HistoryTrend.compute(current: [bar(1, 36_800)], previous: previous, range: 7, today: day(0), withGoal: true))
        #expect(down.lines(locale: Self.gb).contains("Down 8% on the previous 7 days"))
    }

    @Test func withinThreePercentIsAboutTheSame() throws {
        let previous = (30...59).map { bar($0, 40_000) }
        for steps in [38_800, 40_000, 41_200] {
            let trend = try #require(HistoryTrend.compute(current: [bar(1, steps)], previous: previous, range: 30, today: day(0), withGoal: false))
            #expect(trend.lines(locale: Self.gb).contains("About the same as the previous 30 days"))
        }
        let justOver = try #require(HistoryTrend.compute(current: [bar(1, 41_400)], previous: previous, range: 30, today: day(0), withGoal: false))
        #expect(justOver.lines(locale: Self.gb).contains("Up 4% on the previous 30 days"))
    }

    @Test func noEarlierDataLeavesTheComparisonOut() throws {
        let none = try #require(HistoryTrend.compute(current: [bar(1, 30_000)], previous: [], range: 7, today: day(0), withGoal: true))
        #expect(none.change == nil)
        let zeros = try #require(HistoryTrend.compute(current: [bar(1, 30_000)], previous: [bar(8, 0)], range: 7, today: day(0), withGoal: true))
        #expect(zeros.change == nil)
        #expect(!zeros.lines(locale: Self.gb).contains { $0.contains("previous") })
    }

    @Test func bestDayIsTheMostRecentOfEqualDaysAndSkippedWhenZero() throws {
        let tie = try #require(HistoryTrend.compute(current: [bar(3, 61_400), bar(2, 61_400), bar(1, 20_000)], previous: [], range: 7, today: day(0), withGoal: true))
        #expect(tie.best?.day == day(2))
        let empty = try #require(HistoryTrend.compute(current: [bar(1, 0), bar(0, 0)], previous: [], range: 7, today: day(0), withGoal: false))
        #expect(empty.best == nil)
    }

    @Test func linesInPlainWords() throws {
        let previous = (7...13).map { bar($0, 43_036) }
        let current = [bar(6, 40_000), bar(5, 52_000), bar(3, 61_400), bar(2, 45_000), bar(1, 42_600), bar(0, 8_000)]
        let trend = try #require(HistoryTrend.compute(current: current, previous: previous, range: 7, today: day(0), withGoal: true))
        // Saturday 14 Nov is 3 days before Tuesday 17 Nov.
        #expect(trend.lines(locale: Self.gb) == [
            "Goal reached on 2 of 6 days",
            "Daily average 48,200",
            "Up 12% on the previous 7 days",
            "Best day: Sat 14 Nov · 61,400",
        ])
        let me = try #require(HistoryTrend.compute(current: current.map { HistoryDay(day: $0.day, steps: $0.steps, goal: nil, hit: false) }, previous: [], range: 7, today: day(0), withGoal: false))
        #expect(me.lines(locale: Self.gb) == ["Daily average 48,200", "Best day: Sat 14 Nov · 61,400"])
    }

    // MARK: Splitting the backend's 2 × N days

    @Test func beforeFamilyDaysAreSkipped() {
        let days = (0..<14).reversed().map { offset in
            FamilyHistoryDay(day: day(offset), total: offset > 9 ? 0 : 50_000 + offset, goal: 50_000, hit: offset <= 9, isBeforeFamily: offset > 9)
        }
        let (current, previous) = HistoryModel.split(FamilyHistory(today: day(0), days: days), range: 7)
        #expect(current.map(\.day) == (0...6).reversed().map(day))
        #expect(previous.map(\.day) == (7...9).reversed().map(day))
    }

    @Test func meSkipsDaysBeforeHealthHadSteps() {
        let daily = (0..<14).reversed().map { offset in
            DailySteps(date: NepalDay.start(of: day(offset))!, steps: offset > 8 ? 0 : 5_000)
        }
        let recorded = Set((0...8).map(day))
        let (current, previous) = HistoryModel.split(daily, recorded: recorded, range: 7)
        #expect(current.count == 7)
        #expect(previous.map(\.day) == [day(8), day(7)])
        #expect(HistoryModel.split(daily.map { DailySteps(date: $0.date, steps: 0) }, recorded: [], range: 7).current.isEmpty)
    }

    @Test func meKeepsLeadingRecordedZeroDays() {
        // Health has entries from 10 days ago; the first two are 0 steps.
        let daily = (0..<14).reversed().map { offset in
            DailySteps(date: NepalDay.start(of: day(offset))!, steps: offset > 8 ? 0 : 5_000)
        }
        let (current, previous) = HistoryModel.split(daily, recorded: Set((0...10).map(day)), range: 7)
        #expect(current.count == 7)
        #expect(previous.map(\.day) == [day(10), day(9), day(8), day(7)])
        #expect(previous.prefix(2).allSatisfy { $0.steps == 0 })
    }

    // MARK: Comparing like with like

    @Test func sameWeeklyPatternIsAboutTheSame() throws {
        // Six 10,000 days and today at 1,000; a week earlier the same, with
        // the 1,000 on the matching weekday.
        let current = (1...6).reversed().map { bar($0, 10_000) } + [bar(0, 1_000)]
        let previous = (8...13).reversed().map { bar($0, 10_000) } + [bar(7, 1_000)]
        let trend = try #require(HistoryTrend.compute(current: current, previous: previous, range: 7, today: day(0), withGoal: true))
        #expect(trend.dailyAverage == 10_000)
        #expect(trend.lines(locale: Self.gb).contains("About the same as the previous 7 days"))
        #expect(trend.goalHits == 0)
        #expect(trend.countedDays == 7)
    }

    @Test func withoutTodayThePreviousPeriodIsKeptWhole() throws {
        // Today not shown: nothing is dropped from the earlier days.
        let previous = (7...13).reversed().map { bar($0, 10_000) }
        let lowLast = previous.dropLast() + [bar(7, 3_000)]
        let trend = try #require(HistoryTrend.compute(current: (1...6).map { bar($0, 9_000) }, previous: Array(lowLast), range: 7, today: day(0), withGoal: false))
        // 9,000 against (6 × 10,000 + 3,000) / 7 = 9,000.
        #expect(trend.lines(locale: Self.gb).contains("About the same as the previous 7 days"))
        let onlyToday = try #require(HistoryTrend.compute(current: [bar(0, 9_000)], previous: Array(lowLast), range: 7, today: day(0), withGoal: false))
        #expect(onlyToday.lines(locale: Self.gb).contains("About the same as the previous 7 days"))
    }

    // MARK: The model

    @Test func familyTabLoadsFromTheService() async throws {
        let service = MockFamilyService.sample(signedIn: true, now: { Self.now })
        let model = HistoryModel(service: service, familyId: "f_thapa", source: MockStepSource(), now: { Self.now })
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.days.count == 7)
        #expect(model.days.last?.day == day(0))
        #expect(model.goal == 50_000)
        let trend = try #require(model.trend)
        // Sample week: 52,300 / 41,200 / 55,800 / 60,150 / 38,400 / 50,900, today below goal.
        #expect(trend.goalHits == 4)
        #expect(trend.dailyAverage == 49_792)
        #expect(trend.best?.steps == 60_150)
        #expect(trend.change != nil)
        #expect(await service.calls.contains("familyHistory"))
    }

    @Test func ninetyDaysStartWhenTheFamilyDid() async throws {
        let service = MockFamilyService.sample(signedIn: true, now: { Self.now })
        let model = HistoryModel(service: service, familyId: "f_thapa", source: MockStepSource(), now: { Self.now })
        model.range = .quarter
        await model.load()
        #expect(model.phase == .loaded)
        // The sample family started 60 days ago: no bars before that, and
        // nothing earlier to compare with.
        #expect(model.days.count == 61)
        #expect(model.trend?.change == nil)
    }

    @Test func meTabReadsHealthByNepalDay() async throws {
        let samples = (0...9).map { offset in
            StepSample(date: NepalDay.start(of: day(offset))!.addingTimeInterval(10 * 3600), steps: offset == 0 ? 2_000 : 6_000 + offset * 100)
        }
        let model = HistoryModel(service: MockFamilyService.sample(signedIn: true, now: { Self.now }), familyId: "f_thapa", source: MockStepSource(samples: samples), now: { Self.now })
        model.tab = .me
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.days.map(\.day) == (0...6).reversed().map(day))
        #expect(model.goal == nil)
        let trend = try #require(model.trend)
        #expect(trend.goalHits == nil)
        #expect(trend.dailyAverage == 6_350)
        #expect(trend.change != nil)
    }

    @Test func meTabWithRecordedZerosShowsTheChart() async throws {
        let samples = (0...13).map { offset in
            StepSample(date: NepalDay.start(of: day(offset))!.addingTimeInterval(10 * 3600), steps: 0)
        }
        let model = HistoryModel(service: MockFamilyService.sample(signedIn: true, now: { Self.now }), familyId: "f_thapa", source: MockStepSource(samples: samples), now: { Self.now })
        model.tab = .me
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.days.count == 7)
        #expect(model.days.allSatisfy { $0.steps == 0 })
        let trend = try #require(model.trend)
        #expect(trend.dailyAverage == 0)
        #expect(!model.trendLines.isEmpty)
    }

    @Test func meTabWithAnEmptyResponseIsNoData() async {
        let model = HistoryModel(service: MockFamilyService.sample(signedIn: true, now: { Self.now }), familyId: "f_thapa", source: MockStepSource(samples: []), now: { Self.now })
        model.tab = .me
        await model.load()
        guard case .empty = model.phase else {
            Issue.record("expected no data, got \(model.phase)")
            return
        }
    }

    @Test func meTabWithoutHealthSaysSoPlainly() async {
        var notAsked = MockStepSource(samples: [])
        notAsked.alreadyRequested = false
        for source in [notAsked, MockStepSource(isAvailable: false), MockStepSource(samples: [])] {
            let model = HistoryModel(service: MockFamilyService.sample(signedIn: true, now: { Self.now }), familyId: "f_thapa", source: source, now: { Self.now })
            model.tab = .me
            await model.load()
            guard case .empty(let message) = model.phase else {
                Issue.record("expected a plain sentence, got \(model.phase)")
                continue
            }
            #expect(!message.isEmpty)
            #expect(model.trendLines.isEmpty)
        }
    }

    @Test func failureIsANeutralMessage() async {
        let model = HistoryModel(service: MockFamilyService.sample(signedIn: true, now: { Self.now }), familyId: "f_nope", source: MockStepSource(), now: { Self.now })
        await model.load()
        #expect(model.phase == .failed(FamilyServiceError.notMember.message))
    }
}
