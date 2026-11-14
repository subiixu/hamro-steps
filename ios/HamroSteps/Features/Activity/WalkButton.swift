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
    private var storedNotice: WalkNotice?
    /// When the service said `walk_limit_reached`; the limit resets at the
    /// next Nepal midnight.
    private var limitReachedAt: Date?

    @ObservationIgnored private let service: any ActivityService
    @ObservationIgnored private let now: @Sendable () -> Date

    init(
        service: any ActivityService,
        walk: ActiveWalk? = nil,
        notice: WalkNotice? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.service = service
        self.walk = walk
        self.now = now
        self.storedNotice = notice
        if notice == .limitReached { limitReachedAt = now() }
    }

    /// The limit notice only lasts until Nepal midnight, when the daily
    /// allowance resets.
    var notice: WalkNotice? {
        if storedNotice == .limitReached, !limitIsToday { return nil }
        return storedNotice
    }

    private var limitIsToday: Bool {
        guard let limitReachedAt else { return false }
        return ActivityTime.nepalCalendar.isDate(limitReachedAt, inSameDayAs: now())
    }

    /// Drops a limit notice from an earlier Nepal day. Runs on every sync and
    /// before starting; call it on foreground too.
    func expireStaleNotice() {
        guard storedNotice == .limitReached, !limitIsToday else { return }
        storedNotice = nil
        limitReachedAt = nil
    }

    private func show(_ notice: WalkNotice?) {
        storedNotice = notice
        limitReachedAt = notice == .limitReached ? now() : nil
    }

    /// Keeps in step with `familyToday` (the viewer's `walkingSince` and
    /// `walkEndsAt`).
    func sync(walkingSince: EpochMillis?, walkEndsAt: EpochMillis?) {
        walk = ActiveWalk(walkingSince: walkingSince, walkEndsAt: walkEndsAt)
        expireStaleNotice()
        if walk != nil, storedNotice == .alreadyWalking { show(nil) }
    }

    func start() async {
        expireStaleNotice()
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            walk = ActiveWalk(try await service.startWalk())
            show(nil)
        } catch ActivityError.walkLimitReached {
            show(.limitReached)
        } catch ActivityError.alreadyWalking {
            show(.alreadyWalking)
        } catch {
            show(.failed)
        }
    }

    func stop() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.stopWalk()
            walk = nil
            if notice != .limitReached { show(nil) }
        } catch {
            show(.failed)
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
        VStack(spacing: 10) {
            Button(action: onStart) {
                HStack(spacing: 10) {
                    if isWorking {
                        OrbLoader(compact: true).accessibilityHidden(true)
                    } else {
                        Icon.walking.size(26)
                    }
                    Text("I'm walking")
                        .font(.title3.weight(.bold))
                        // One line even at the largest sizes on a narrow phone.
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
            .disabled(isWorking || notice == .limitReached)
            .accessibilityHint(Text("Lets your family know you're out for a walk."))

            Group {
                if let notice {
                    Text(notice.message)
                } else {
                    Text("Your family gets an alert, so they can walk with you or give you a call.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
        }
    }

    private func walking(_ walk: ActiveWalk, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                WalkingBadge(label: "You're walking")
                Text(ActivityFormat.walkingFor(walk, now: now))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Icon.clock.size(clockSize)
                    Text(ActivityFormat.autoStop(walk))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(.secondaryText)
            }
            .accessibilityElement(children: .combine)

            if let notice, notice != .limitReached {
                Text(notice.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onStop) {
                HStack(spacing: 8) {
                    if isWorking {
                        OrbLoader(compact: true).accessibilityHidden(true)
                    } else {
                        Icon.stop.size(20)
                    }
                    Text("Stop walk")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            // Neutral words: stopping is calm, not an accent action.
            .tint(.primary)
            .disabled(isWorking)
        }
        .padding(Bento.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Soft orange on white, so the tile reads the same on any canvas.
        .bentoSurface(Color.accent.opacity(0.08))
        .background(.surface, in: .rect(cornerRadius: Bento.radius, style: .continuous))
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
