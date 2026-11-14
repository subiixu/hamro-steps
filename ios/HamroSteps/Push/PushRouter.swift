import Foundation
import Observation

/// What a push carries besides its text (`docs/contract-activity.md`,
/// "Notifications"): `{type, familyId, eventId?}`.
struct PushPayload: Equatable, Sendable {
    enum Kind: String, Sendable {
        case walkStarted = "walk_started"
        case family100 = "family_100"
        case reaction
        case eveningNudge = "evening_nudge"
    }

    let kind: Kind
    let familyId: String
    let eventId: String?
}

/// Where a tapped notification takes the person.
enum PushRoute: Equatable, Sendable {
    /// Home as it was.
    case home
    /// Home, showing this family; `eventId` is the feed event the push was
    /// about, for when Home can scroll to it.
    case family(id: String, eventId: String?)
}

enum PushRouter {
    /// `nil` for anything that isn't one of ours: an unknown `type`, or no
    /// `familyId`.
    static func payload(from userInfo: [AnyHashable: Any]) -> PushPayload? {
        guard let rawType = userInfo["type"] as? String,
              let kind = PushPayload.Kind(rawValue: rawType),
              let familyId = userInfo["familyId"] as? String, !familyId.isEmpty
        else { return nil }
        let eventId = (userInfo["eventId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // The nudge is about the family, never one event.
        return PushPayload(kind: kind, familyId: familyId, eventId: kind == .eveningNudge ? nil : eventId)
    }

    /// A family the person isn't in (left, removed, or another account's
    /// push) opens Home unchanged.
    static func route(_ payload: PushPayload?, familyIds: [String]) -> PushRoute {
        guard let payload, familyIds.contains(payload.familyId) else { return .home }
        return .family(id: payload.familyId, eventId: payload.eventId)
    }
}

/// Holds the last tapped notification until Home is ready to show it (a tap
/// can cold-start the app before the session has loaded).
@MainActor
@Observable
final class PushInbox {
    private(set) var pending: PushPayload?
    /// Bumped on every tap, so a tap on Home (no payload, or the same one
    /// twice) still brings the Home tab forward.
    private(set) var tapCount = 0

    /// A tapped notification, already parsed (`nil`: not one of ours).
    func received(_ payload: PushPayload?) {
        pending = payload
        tapCount += 1
    }

    /// Hands over the pending tap, once.
    func take(familyIds: [String]) -> PushRoute {
        defer { pending = nil }
        return PushRouter.route(pending, familyIds: familyIds)
    }
}
