import SwiftUI

/// Create a family or join one with a code. Used after onboarding (no family
/// yet) and from Home's family switcher (another family).
struct FamilySetupView: View {
    let isFirstFamily: Bool
    /// The family that was created or joined.
    var onFinished: (FamilySummary) -> Void

    enum Step: Hashable {
        case createName
        case createGoal(name: String)
        case invite(FamilySummary)
        case join
    }

    @State private var path: [Step] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Bento.gap) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isFirstFamily ? "Your family" : "Another family")
                            .font(.largeTitle.bold())
                        Text("One person starts the family and shares a code. Everyone else joins with it.")
                            .font(.body)
                            .foregroundStyle(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    choice(
                        icon: .share,
                        title: "Join with a code",
                        detail: "Someone sent you a 6-letter code.",
                        step: .join
                    )
                    choice(
                        icon: .plus,
                        title: "Start a family",
                        detail: "Name it, pick a daily goal, and invite everyone.",
                        step: .createName
                    )
                }
                .padding(.horizontal, Bento.margin)
                .padding(.bottom, 16)
            }
            .background(.canvas)
            .toolbar {
                if !isFirstFamily {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Icon.close.image }
                            .accessibilityLabel("Close")
                    }
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .createName:
                    CreateFamilyNameView { path.append(.createGoal(name: $0)) }
                case .createGoal(let name):
                    CreateGoalView(familyName: name) { path.append(.invite($0)) }
                case .invite(let family):
                    InviteCodeView(family: family) { onFinished(family) }
                case .join:
                    JoinFamilyView { onFinished($0) }
                }
            }
        }
    }

    private func choice(icon: Icon, title: LocalizedStringKey, detail: LocalizedStringKey, step: Step) -> some View {
        Button {
            path.append(step)
        } label: {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    icon.size(28)
                        .foregroundStyle(.accentText)
                        .frame(width: 56, height: 56)
                        .background(Color.accent.opacity(0.14), in: .circle)
                    Spacer(minLength: 0)
                    Icon.chevronRight.size(20).foregroundStyle(.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(.surfaceMuted, in: .circle)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title2.weight(.bold)).foregroundStyle(.primary)
                    Text(detail).font(.body).foregroundStyle(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Bento.padding)
            .padding(.vertical, 4)
            .choiceTile(selected: false, radius: Bento.radius)
        }
        .buttonStyle(.plain)
    }
}

/// Create, step 1: the family's name.
struct CreateFamilyNameView: View {
    var onNext: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                SetupHeading(step: 1, title: "Name your family", detail: "Everyone will see this at the top of their screen.")
                TextField("Thapa Family", text: $name)
                    .font(.title2)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focused)
                    .fieldTile()
                    .onSubmit(next)
                    .onChange(of: name) { _, value in
                        if value.count > FamilyRules.nameLength.upperBound {
                            name = String(value.prefix(FamilyRules.nameLength.upperBound))
                        }
                    }
            }
            .padding(.horizontal, Bento.margin)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Next", isEnabled: FamilyRules.isValidName(name), action: next)
                .padding(.horizontal, Bento.margin)
                .padding(.vertical, 16)
                .background(.canvas)
        }
        .background(.canvas)
        .onAppear { focused = true }
    }

    private func next() {
        guard FamilyRules.isValidName(name) else { return }
        onNext(FamilyRules.cleanName(name))
    }
}

/// Create, step 2: the daily goal (50,000 suggested), then create.
struct CreateGoalView: View {
    let familyName: String
    var onCreated: (FamilySummary) -> Void

    @Environment(\.familyService) private var service
    @State private var goal = Self.initialGoal
    @State private var isCreating = false

    /// Debug screenshots can start at another goal with `-goal 1000000`.
    private static var initialGoal: Int {
        #if DEBUG
        let override = UserDefaults.standard.integer(forKey: "goal")
        if FamilyRules.goalRange.contains(override) { return override }
        #endif
        return FamilyRules.suggestedGoal
    }
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                SetupHeading(step: 2, title: "Pick a daily goal", detail: "Everyone's steps add up to this one number each day. You can change it later.")
                GoalPicker(goal: $goal)
                if let message { Notice(text: message) }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isCreating {
                    OrbLoader(activity: .saving)
                } else {
                    PrimaryButton(title: "Create family", action: create)
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
            .background(.canvas)
        }
        .background(.canvas)
    }

    private func create() {
        isCreating = true
        message = nil
        Task {
            do {
                onCreated(try await service.createFamily(name: familyName, dailyGoal: goal))
            } catch let error as FamilyServiceError {
                message = error.message
            } catch {
                message = FamilyServiceError.unavailable("").message
            }
            isCreating = false
        }
    }
}

/// The goal in big type, simple presets, and a gentle +/- by 5,000.
struct GoalPicker: View {
    @Binding var goal: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    private let step = 5_000

    var body: some View {
        VStack(spacing: Bento.gap) {
            Group {
                if typeSize.isAccessibilitySize {
                    // Large text: the number gets the full width, buttons below.
                    VStack(spacing: 16) {
                        goalValue
                        HStack(spacing: 24) {
                            adjust(.minus, by: -step)
                            adjust(.plus, by: step)
                        }
                    }
                } else {
                    HStack(spacing: 16) {
                        adjust(.minus, by: -step)
                        goalValue
                        adjust(.plus, by: step)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Bento.padding)
            .bentoSurface()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Daily goal"))
            .accessibilityValue(Text(StepFormatter.withUnit(goal)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: change(by: step)
                case .decrement: change(by: -step)
                @unknown default: break
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Bento.gap), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: Bento.gap) {
                ForEach(FamilyRules.goalPresets, id: \.self) { preset in
                    let selected = goal == preset
                    Button {
                        withAnimation { goal = preset }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(StepFormatter.count(preset))
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(selected ? Color.accentText : Color.primary)
                                Spacer(minLength: 4)
                                if selected {
                                    Icon.check.size(18)
                                        .foregroundStyle(.accentText)
                                        .accessibilityHidden(true)
                                }
                            }
                            // Every tile keeps the line, so the grid stays even.
                            Text("Suggested")
                                .font(.footnote)
                                .foregroundStyle(.secondaryText)
                                .opacity(preset == FamilyRules.suggestedGoal ? 1 : 0)
                                .accessibilityHidden(preset != FamilyRules.suggestedGoal)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .padding(.horizontal, Bento.smallPadding)
                        .padding(.vertical, 14)
                        .choiceTile(selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var goalValue: some View {
        VStack(spacing: 2) {
            Text(StepFormatter.count(goal))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(goal)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("steps a day")
                .font(.body)
                .foregroundStyle(.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func adjust(_ icon: Icon, by amount: Int) -> some View {
        Button {
            change(by: amount)
        } label: {
            icon.size(22)
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(amount < 0 ? goal <= FamilyRules.goalRange.lowerBound : goal >= FamilyRules.goalRange.upperBound)
        .accessibilityHidden(true)
    }

    private func change(by amount: Int) {
        let next = (goal + amount) / 1_000 * 1_000
        withAnimation { goal = min(max(next, FamilyRules.goalRange.lowerBound), FamilyRules.goalRange.upperBound) }
    }
}

/// The top of a setup or edit screen: optional "Step N of 2", the title,
/// and one line under it.
struct SetupHeading: View {
    var step: Int?
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let step { StepCount(step: step, total: 2) }
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

#Preview("Goal") {
    NavigationStack { CreateGoalView(familyName: "Thapa Family") { _ in } }
}
