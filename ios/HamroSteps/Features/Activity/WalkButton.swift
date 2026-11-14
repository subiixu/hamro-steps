import SwiftUI

/// Something the walk button needs to tell the walker.
enum WalkNotice: Equatable, Sendable {
    /// `walk_limit_reached`: 3 walks shared today.
    case limitReached
    /// `already_walking`: a walk is open (another device, or stale state).
    case alreadyWalking
    /// Anything else: offline, server down.
    case failed

    var message: LocalizedStringKey {
        switch self {
        case .limitReached:
            "You've shared 3 walks today. Your steps still count for the family, and you can share a walk again tomorrow."
        case .alreadyWalking:
            "You're already sharing a walk. Your family can see it."
        case .failed:
            "We couldn't tell your family just now. Check your connection and try again."
        }
    }
}

/// Drives `WalkButton`: starts and stops walks through the service and turns
/// contract errors into friendly notices.
@MainActor @Observable
final class WalkController {
    private(set) var walk: ActiveWalk?
    private(set) var isWorking = false
    private(set) var notice: WalkNotice?

    @ObservationIgnored private let service: any ActivityService

    init(service: any ActivityService, walk: ActiveWalk? = nil, notice: WalkNotice? = nil) {
        self.service = service
        self.walk = walk
        self.notice = notice
    }

    /// Keeps in step with `familyToday` (the viewer's `walkingSince` and
    /// `walkEndsAt`).
    func sync(walkingSince: EpochMillis?, walkEndsAt: EpochMillis?) {
        walk = ActiveWalk(walkingSince: walkingSince, walkEndsAt: walkEndsAt)
        if walk != nil, notice == .alreadyWalking { notice = nil }
    }

    func start() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            walk = ActiveWalk(try await service.startWalk())
            notice = nil
        } catch ActivityError.walkLimitReached {
            notice = .limitReached
        } catch ActivityError.alreadyWalking {
            notice = .alreadyWalking
        } catch {
            notice = .failed
        }
    }

    func stop() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.stopWalk()
            walk = nil
            if notice != .limitReached { notice = nil }
        } catch {
            notice = .failed
        }
    }
}

/// The big "I'm walking" button. While walking it shows how long, when the
/// walk stops by itself, and "Stop walk". A walk past its end time shows as
/// finished straight away.
struct WalkButton: View {
    let walk: ActiveWalk?
    var isWorking = false
    var notice: WalkNotice?
    let onStart: () -> Void
    let onStop: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var clockSize: CGFloat = 18

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let current = walk.flatMap { $0.isOver(at: context.date) ? nil : $0 }
            Group {
                if let current {
                    walking(current, now: context.date)
                } else {
                    idle
                }
            }
            .sensoryFeedback(.success, trigger: current?.startedAt) { _, new in new != nil }
        }
    }

    private var idle: some View {
        VStack(spacing: 12) {
            Button(action: onStart) {
                HStack(spacing: 12) {
                    if isWorking {
                        OrbLoader(compact: true).accessibilityHidden(true)
                    } else {
                        Icon.walking.size(28)
                    }
                    Text("I'm walking")
                        .font(.title2.weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .foregroundStyle(.white)
                .background(.accent, in: .rect(cornerRadius: 24))
                .contentShape(.rect(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .disabled(isWorking || notice == .limitReached)
            .opacity(notice == .limitReached ? 0.45 : 1)
            .accessibilityHint(Text("Lets your family know you're out for a walk."))

            Group {
                if let notice {
                    Text(notice.message)
                } else {
                    Text("Your family gets an alert, so they can walk with you or give you a call.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func walking(_ walk: ActiveWalk, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                WalkingBadge(label: "You're walking")
                Text(ActivityFormat.walkingFor(walk, now: now))
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Icon.clock.size(clockSize)
                    Text(ActivityFormat.autoStop(walk))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if let notice, notice != .limitReached {
                Text(notice.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onStop) {
                HStack(spacing: 10) {
                    if isWorking {
                        OrbLoader(compact: true).accessibilityHidden(true)
                    } else {
                        Icon.stop.size(22)
                    }
                    Text("Stop walk")
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .foregroundStyle(.primary)
                .background(.surface, in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.secondary.opacity(0.35), lineWidth: 1.5))
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.12), in: .rect(cornerRadius: 24))
    }
}

extension WalkButton {
    /// The button wired to a controller.
    init(controller: WalkController) {
        self.init(
            walk: controller.walk,
            isWorking: controller.isWorking,
            notice: controller.notice,
            onStart: { Task { await controller.start() } },
            onStop: { Task { await controller.stop() } }
        )
    }
}

#Preview("Walk button") {
    ScrollView {
        VStack(spacing: 32) {
            WalkButton(walk: nil, onStart: {}, onStop: {})
            WalkButton(
                walk: ActiveWalk(startedAt: .now.addingTimeInterval(-12 * 60), endsAt: .now.addingTimeInterval(108 * 60)),
                onStart: {}, onStop: {}
            )
            WalkButton(walk: nil, notice: .limitReached, onStart: {}, onStop: {})
        }
        .padding()
    }
    .background(.canvas)
}
