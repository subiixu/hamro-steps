import Charts
import SwiftUI

/// Opened from Home's "This week" card: the family's daily total, or your
/// own steps, over 7, 30 or 90 Nepal days, with a few trend lines.
struct HistoryView: View {
    let familyId: String

    @Environment(\.familyService) private var service
    @Environment(StepSync.self) private var stepSync
    @Environment(\.now) private var now
    @State private var model: HistoryModel?

    var body: some View {
        ScrollView {
            if let model {
                HistoryContent(model: model)
                    .padding(.horizontal, Bento.margin)
                    .padding(.bottom, 24)
            }
        }
        // Room below the last card so the floating tab bar never sits on it.
        .contentMargins(.bottom, 72, for: .scrollContent)
        .background(.canvas)
        .refreshable { await model?.reload() }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbarVisibility(.visible, for: .navigationBar)
        .onAppear {
            if model == nil {
                model = HistoryModel(service: service, familyId: familyId, source: stepSync.source, now: now)
            }
        }
    }
}

private struct HistoryContent: View {
    @Bindable var model: HistoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: Bento.gap) {
            ChoiceRow(options: HistoryTab.allCases, selection: $model.tab, title: \.title, label: "Whose steps")
            ChoiceRow(options: HistoryRange.allCases, selection: $model.range, title: \.title, label: "How many days")
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        TileLabel(model.tab == .family ? "Family steps each day" : "Your steps each day", icon: .calendar)
                        if model.tab == .me {
                            Text("From Apple Health on this phone. Only you see this.")
                                .font(.footnote)
                                .foregroundStyle(.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    chartArea
                }
            }
            if model.phase == .loaded, !model.trendLines.isEmpty {
                Card(title: "How it's going", icon: .celebrate) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.trendLines, id: \.self) { line in
                            Text(line)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .task(id: model.key) { await model.load() }
    }

    @ViewBuilder
    private var chartArea: some View {
        switch model.phase {
        case .loading:
            OrbLoader(activity: model.tab == .family ? .loadingFamily : .connectingHealth)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        case .failed(let message):
            Notice(text: message) { Task { await model.reload() } }
        case .empty(let message):
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded:
            HistoryChart(days: model.days, goal: model.goal, range: model.range, showsGoal: model.tab == .family)
        }
    }
}

/// Daily bars. Family: goal-reached days in the goal colour, other days a
/// soft accent tint, and a dashed goal line. Me: accent bars. Never red.
private struct HistoryChart: View {
    let days: [HistoryDay]
    let goal: Int?
    let range: HistoryRange
    let showsGoal: Bool

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 220

    /// Grows a little with text size, capped so the trend lines stay close.
    private var height: CGFloat { min(scaledHeight, 320) }

    /// Every n-th day gets an axis label, counted back from today.
    private var labelStep: Int {
        let large = typeSize.isAccessibilitySize
        switch range {
        case .week: return large ? 2 : 1
        case .month: return large ? 14 : 7
        case .quarter: return large ? 45 : 30
        }
    }

    private var labelledDays: [String] {
        let ids = days.map(\.day)
        return stride(from: ids.count - 1, through: 0, by: -labelStep).map { ids[$0] }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.day),
                    y: .value("Steps", day.steps)
                )
                .foregroundStyle(color(day))
                .cornerRadius(range == .week ? 6 : 2)
                .accessibilityLabel(HistoryFormat.longDate(day.day))
                .accessibilityValue(accessibilityValue(day))
            }
            if showsGoal, let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Color.goalText.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("Goal \(StepFormatter.compact(goal))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.goalText)
                    }
                    .accessibilityLabel(Text("Daily goal"))
                    .accessibilityValue(Text(StepFormatter.withUnit(goal)))
            }
        }
        .chartXScale(domain: days.map(\.day))
        .chartXAxis {
            AxisMarks(values: labelledDays) { value in
                AxisValueLabel {
                    if let day = value.as(String.self) {
                        Text(axisLabel(day))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let steps = value.as(Int.self) {
                        Text(StepFormatter.compact(steps))
                    }
                }
            }
        }
        .frame(height: height)
    }

    private func axisLabel(_ day: String) -> String {
        range == .week
            ? HistoryFormat.weekday(day, narrow: typeSize.isAccessibilitySize)
            : HistoryFormat.dayMonth(day)
    }

    private func color(_ day: HistoryDay) -> Color {
        guard showsGoal else { return .accent }
        return day.hit ? .goal : Color.accent.opacity(0.35)
    }

    private func accessibilityValue(_ day: HistoryDay) -> String {
        let steps = StepFormatter.withUnit(day.steps)
        return showsGoal && day.hit ? String(localized: "\(steps), goal reached") : steps
    }
}

/// A row of large pill buttons (Family | Me, 7 | 30 | 90 days) that stacks
/// when the text is too big to fit side by side, so nothing is cut off.
private struct ChoiceRow<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: KeyPath<Option, String>
    let label: LocalizedStringKey

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(alignment: .leading, spacing: 8) { buttons }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
    }

    private var buttons: some View {
        ForEach(options) { option in
            let selected = option == selection
            Button {
                selection = option
            } label: {
                Text(option[keyPath: title])
                    .font(.body.weight(.semibold))
                    .fixedSize()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? Color.accentText : Color.surface, in: .capsule)
                    .overlay(Capsule().strokeBorder(Bento.edge, lineWidth: 1))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

#Preview {
    let service = MockFamilyService.preview
    NavigationStack {
        HistoryView(familyId: "f_thapa")
    }
    .environment(StepSync(source: MockStepSource.sampleWeek(calendar: NepalDay.calendar), service: service))
    .environment(\.familyService, service)
}
