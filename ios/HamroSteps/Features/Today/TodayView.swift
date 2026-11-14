import SwiftUI

struct TodayView: View {
    @Environment(StepStore.self) private var steps

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(.canvas)
            .navigationTitle("Today")
            .refreshable { await steps.refresh() }
        }
        .task { await steps.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch steps.phase {
        case .idle, .loading, .connecting:
            if let summary = steps.summary {
                loaded(summary)
            } else {
                OrbLoader(activity: steps.phase == .connecting ? .connectingHealth : .readingSteps)
                    .frame(maxWidth: .infinity, minHeight: 320)
            }
        case .loaded(let summary):
            loaded(summary)
        case .unavailable:
            Card {
                Text("Apple Health isn't available on this device, so there are no steps to show.")
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Couldn't read your steps just now.")
                        .font(.headline)
                    Button("Try again") { Task { await steps.refresh() } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func loaded(_ summary: StepSummary) -> some View {
        TodayHeroCard(summary: summary)
        WeekCard(days: summary.days)
        Card {
            PlaceholderRow(icon: .goal, tint: .goal, title: "Family goal",
                           detail: "Walk together towards one daily target.")
        }
        Card {
            PlaceholderRow(icon: .fire, tint: .streak, title: "Your streak",
                           detail: "Hit your goal on consecutive days to build it.")
        }
    }
}

struct TodayHeroCard: View {
    let summary: StepSummary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Icon.home.size(20)
                    Text("Steps today")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.accent)

                Text(StepFormatter.count(summary.today))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if summary.isAllZero {
                    Text("Seeing zeros? Open the Health app, go to Sharing › Apps › Hamro Steps, and turn on Steps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(StepFormatter.withUnit(summary.total)) this week")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

struct WeekCard: View {
    let days: [DailySteps]

    private var peak: Int { max(days.map(\.steps).max() ?? 0, 1) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last 7 days")
                    .font(.headline)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(days) { day in
                        bar(for: day, isToday: day.id == days.last?.id)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private func bar(for day: DailySteps, isToday: Bool) -> some View {
        VStack(spacing: 6) {
            Text(StepFormatter.compact(day.steps))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { proxy in
                VStack {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(isToday ? Color.accent : Color.accent.opacity(0.35))
                        .frame(height: max(6, proxy.size.height * CGFloat(day.steps) / CGFloat(peak)))
                }
            }
            Text(day.date, format: .dateTime.weekday(.narrow))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide)))
        .accessibilityValue(Text(StepFormatter.withUnit(day.steps)))
    }
}

#Preview("Loaded") {
    TodayView()
        .environment(StepStore(source: MockStepSource.sampleWeek()))
}

#Preview("Loading") {
    TodayView()
        .environment(StepStore(source: MockStepSource(delay: .seconds(3600))))
}

#Preview("Zeros (denied)") {
    TodayView()
        .environment(StepStore(source: MockStepSource()))
}
