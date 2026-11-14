import SwiftUI

/// Loads a family's feed and sends reactions. A reaction shows at once and
/// is put back if the server refuses it.
@MainActor @Observable
final class FeedModel {
    enum Phase: Equatable { case loading, loaded, failed }

    private(set) var events: [FeedEvent] = []
    private(set) var phase: Phase = .loading

    let familyId: String
    let viewerId: String?
    @ObservationIgnored private let service: any ActivityService

    init(service: any ActivityService, familyId: String, viewerId: String?) {
        self.service = service
        self.familyId = familyId
        self.viewerId = viewerId
    }

    func load() async {
        if events.isEmpty { phase = .loading }
        do {
            events = try await service.feed(familyId: familyId).filter(\.isDisplayable)
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    func react(_ emoji: Reaction, to eventId: String) async {
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { return }
        let before = events[index]
        events[index] = before.reacting(with: emoji)
        do {
            try await service.react(eventId: eventId, emoji: emoji)
        } catch {
            if let i = events.firstIndex(where: { $0.id == eventId }) { events[i] = before }
        }
    }
}

/// The family feed, newest first. Not scrollable by itself, so it can sit
/// inside a screen's ScrollView.
struct FeedList: View {
    let model: FeedModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if model.events.isEmpty {
            switch model.phase {
            case .loading:
                ActivityLoadingRow(message: "Getting the family news…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .failed:
                retry
            case .loaded:
                VStack(spacing: 10) {
                    Icon.cheer.size(32)
                        .foregroundStyle(.cheer)
                    Text("Nothing here yet today. When someone passes 5,000 steps or starts a walk, you'll see it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }
        } else {
            VStack(spacing: 0) {
                if model.phase == .failed { retry.padding(.bottom, 8) }
                ForEach(model.events) { event in
                    FeedRow(event: event, viewerId: model.viewerId, now: now) { emoji in
                        Task { await model.react(emoji, to: event.id) }
                    }
                    .padding(.vertical, 14)
                    if event.id != model.events.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var retry: some View {
        VStack(spacing: 10) {
            Text("We couldn't get the latest family news.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await model.load() } }
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// One feed event: who, what in plain words, when, and the reactions.
struct FeedRow: View {
    let event: FeedEvent
    let viewerId: String?
    var now: Date = .now
    let onReact: (Reaction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ActivityAvatar(content: event.actor.map(ActivityAvatar.Content.member) ?? .family)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.text(viewerId: viewerId))
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ActivityFormat.relative(event.createdDate, now: now))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                ReactionBar(event: event, onReact: onReact)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The 5 fixed emoji as one-tap chips with counts; mine is highlighted.
struct ReactionBar: View {
    let event: FeedEvent
    let onReact: (Reaction) -> Void

    var body: some View {
        ActivityWrapLayout(spacing: 6) {
            ForEach(Reaction.allCases) { emoji in
                ReactionChip(emoji: emoji, count: event.count(for: emoji), isMine: event.myReaction == emoji) {
                    onReact(emoji)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: event.myReaction)
    }
}

struct ReactionChip: View {
    let emoji: Reaction
    let count: Int
    let isMine: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(emoji.rawValue)
                    .font(.title3)
                if count > 0 {
                    Text(count, format: .number)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isMine ? Color.accent : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 40)
            .background(isMine ? Color.accent.opacity(0.16) : Color.surfaceMuted, in: .capsule)
            .overlay {
                if isMine { Capsule().strokeBorder(.accent, lineWidth: 1.5) }
            }
            .contentShape(.capsule)
            .animation(.snappy, value: count)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(emoji.spokenName))
        .accessibilityValue(Text(isMine ? "\(count) reactions, including yours" : "\(count) reactions"))
        .accessibilityAddTraits(isMine ? .isSelected : [])
    }
}

#Preview {
    ScrollView {
        FeedList(model: FeedModel(
            service: MockActivityService(), familyId: MockActivityService.familyId,
            viewerId: MockActivityService.me.userId
        ))
        .padding()
    }
}
