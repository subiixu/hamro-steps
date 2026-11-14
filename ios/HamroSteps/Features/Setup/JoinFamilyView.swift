import SwiftUI

/// Join with the 6-character code. Case, spaces and dashes don't matter, and
/// pasting the whole invite message finds the code in it. Once the code is
/// complete, the family's name shows before joining (`previewInvite`).
struct JoinFamilyView: View {
    var onJoined: (FamilySummary) -> Void

    @Environment(\.familyService) private var service
    @State private var code = ""
    @State private var preview: InvitePreview?
    @State private var isChecking = false
    @State private var isJoining = false
    @State private var message: String?
    @FocusState private var focused: Bool

    private var cleanCode: String { InviteCode.normalise(code) }
    private var canJoin: Bool {
        InviteCode.isValid(code) && preview.map { !$0.isFull || $0.alreadyMember } == true && !isJoining && !isChecking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                SetupHeading(title: "Join your family", detail: "Type the code from the invite message, or paste it.")

                TextField("ABC 123", text: $code)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.join)
                    .focused($focused)
                    .padding(.vertical, 8)
                    .fieldTile()
                    .onSubmit(join)
                    .accessibilityLabel("Family code")

                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        if let found = InviteCode.extract(from: text) {
                            code = found
                        } else {
                            message = String(localized: "That doesn't look like a family code. It has 6 letters and numbers.")
                        }
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                if isChecking {
                    OrbLoader(activity: .joining, compact: true)
                        .frame(maxWidth: .infinity)
                } else if let preview {
                    previewCard(preview)
                }
                if let message { Notice(text: message) }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isJoining {
                    OrbLoader(activity: .joining)
                } else {
                    PrimaryButton(title: "Join family", isEnabled: canJoin, action: join)
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
            .background(.canvas)
        }
        .background(.canvas)
        .onAppear { focused = true }
        .task(id: cleanCode) { await check() }
    }

    private func previewCard(_ preview: InvitePreview) -> some View {
        HStack(spacing: 16) {
            Icon.family.size(28)
                .foregroundStyle(.accentText)
                .frame(width: 56, height: 56)
                .background(Color.accent.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.name).font(.title3.weight(.semibold))
                Text(preview.alreadyMember
                     ? String(localized: "You're already in this family.")
                     : preview.memberCount == 1
                        ? String(localized: "1 person so far")
                        : String(localized: "\(preview.memberCount) people so far"))
                    .font(.body)
                    .foregroundStyle(.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Bento.padding)
        .bentoSurface()
        .accessibilityElement(children: .combine)
    }

    /// Looks the code up as soon as it's complete.
    private func check() async {
        preview = nil
        message = nil
        guard InviteCode.isValid(code) else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let found = try await service.previewInvite(code: cleanCode)
            guard !Task.isCancelled else { return }
            preview = found
            if found.isFull && !found.alreadyMember { message = FamilyServiceError.familyFull.message }
        } catch is CancellationError {
            return
        } catch let error as FamilyServiceError {
            message = error.message
        } catch {
            message = FamilyServiceError.unavailable("").message
        }
    }

    private func join() {
        guard canJoin else { return }
        isJoining = true
        message = nil
        Task {
            do {
                onJoined(try await service.joinFamily(code: cleanCode))
            } catch let error as FamilyServiceError {
                message = error.message
            } catch {
                message = FamilyServiceError.unavailable("").message
            }
            isJoining = false
        }
    }
}

#Preview {
    NavigationStack { JoinFamilyView { _ in } }
}
