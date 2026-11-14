import SwiftUI

/// The status sheet: 7 presets or a few words of your own (30 characters at
/// most), when it clears (24 hours unless you pick otherwise), and Clear.
/// Present it in a `.sheet`; it dismisses itself after saving or clearing.
struct StatusPicker: View {
    let current: MemberStatus?
    let onSave: (StatusInput) async throws -> Void
    let onClear: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preset: StatusPreset?
    @State private var text: String
    @State private var expiry: StatusExpiry = .default
    @State private var isSaving = false
    @State private var problem: LocalizedStringKey?
    @FocusState private var textFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    init(current: MemberStatus?,
         onSave: @escaping (StatusInput) async throws -> Void,
         onClear: @escaping () async throws -> Void) {
        self.current = current
        self.onSave = onSave
        self.onClear = onClear
        let active = current?.isActive(at: .now) == true ? current : nil
        _preset = State(initialValue: active?.preset)
        _text = State(initialValue: active?.preset == nil ? (active?.text ?? "") : "")
    }

    private var canSave: Bool {
        (try? StatusInput.validated(preset: preset, text: text, expiresAt: nil, now: .now)) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    presets
                    customText
                    expiryChoices
                    if let problem {
                        Text(problem)
                            .font(.subheadline)
                            .foregroundStyle(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if current?.isActive(at: .now) == true {
                        clearButton
                    }
                }
                .padding(.horizontal, Bento.margin)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvas)
            .safeAreaInset(edge: .bottom) { saveButton }
            .navigationTitle("Your status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("What are you up to?")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2),
                spacing: 10
            ) {
                ForEach(StatusPreset.allCases) { option in
                    let selected = preset == option
                    Button {
                        preset = option
                        text = ""
                        textFocused = false
                        problem = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                option.icon.size(24)
                                    .foregroundStyle(.accentText)
                                Spacer(minLength: 4)
                                if selected {
                                    Icon.check.size(20)
                                        .foregroundStyle(.accentText)
                                }
                            }
                            .accessibilityHidden(true)
                            Text(option.label)
                                .font(.body.weight(selected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(16)
                        .choiceTile(selected: selected, radius: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var customText: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Or write your own")
            HStack(spacing: 12) {
                Icon.statusCustom.size(24)
                    .foregroundStyle(.accentText)
                    .accessibilityHidden(true)
                TextField("For example: Visiting Pokhara", text: $text)
                    .focused($textFocused)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .choiceTile(selected: !text.isEmpty, radius: 20)
            Text("\(StatusInput.length(of: text))/\(StatusInput.maxTextLength)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 4)
                .accessibilityLabel(Text("\(StatusInput.length(of: text)) of \(StatusInput.maxTextLength) characters used"))
        }
        .onChange(of: text) { _, new in
            let clamped = StatusInput.clamped(new)
            if clamped != new { text = clamped }
            if !clamped.trimmingCharacters(in: .whitespaces).isEmpty { preset = nil }
            problem = nil
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.headline)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var expiryChoices: some View {
        TimelineView(.everyMinute) { context in
            let options = StatusExpiry.available(at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Clear it after")
                ActivityWrapLayout(spacing: 8) {
                    ForEach(options) { option in
                        Button {
                            expiry = option
                        } label: {
                            // White on accentText passes AA; on accent it doesn't.
                            Text(option.label)
                                .font(.body.weight(expiry == option ? .semibold : .regular))
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .foregroundStyle(expiry == option ? Color.white : Color.primary)
                                .background(expiry == option ? Color.accentText : Color.surface, in: .capsule)
                                .overlay {
                                    if expiry != option {
                                        Capsule().strokeBorder(Bento.edge, lineWidth: 1)
                                    }
                                }
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(expiry == option ? .isSelected : [])
                    }
                }
                if let date = (options.contains(expiry) ? expiry : .default).expiry(from: context.date) {
                    HStack(spacing: 6) {
                        Icon.clock.size(16)
                        Text(ActivityFormat.statusUntil(date, now: context.date))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondaryText)
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .onChange(of: options) { _, new in
                if !new.contains(expiry) { expiry = .default }
            }
        }
    }

    private var clearButton: some View {
        Button {
            Task { await clear() }
        } label: {
            HStack(spacing: 10) {
                Icon.clear.size(20)
                Text("Clear my status")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.primary)
        .disabled(isSaving)
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    OrbLoader(compact: true).accessibilityHidden(true)
                }
                Text("Set status")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            // The glass style adds about 12pt of padding: 60pt in all.
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .contentShape(.rect(cornerRadius: Bento.radius, style: .continuous))
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: Bento.radius))
        .tint(.accent)
        .disabled(!canSave || isSaving)
        .padding(.horizontal, Bento.margin)
        .padding(.vertical, 12)
        .background(.canvas)
    }

    // MARK: Actions

    private func save() async {
        let now = Date.now
        // 24 hours is the server's default, so it isn't sent: a phone clock
        // that's a little off can't make it invalid.
        let expiresAt = expiry == .default ? nil : expiry.expiry(from: now)
        let input: StatusInput
        do {
            input = try StatusInput.validated(preset: preset, text: text, expiresAt: expiresAt, now: now)
        } catch {
            problem = Self.message(for: error)
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(input)
            dismiss()
        } catch {
            problem = Self.message(for: error)
        }
    }

    private func clear() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onClear()
            dismiss()
        } catch {
            problem = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> LocalizedStringKey {
        switch error as? ActivityError {
        case .invalidStatus: "Pick a status, or write one of up to 30 characters."
        case .invalidExpiry: "That time has already passed. Pick another one."
        default: "We couldn't save your status just now. Check your connection and try again."
        }
    }
}

#Preview {
    StatusPicker(
        current: MemberStatus(preset: .atWork, expiresAt: ActivityTime.millis(.now.addingTimeInterval(3600))),
        onSave: { _ in }, onClear: {}
    )
}
