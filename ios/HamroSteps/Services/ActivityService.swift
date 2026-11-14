import Foundation

/// Walks, status, feed, reactions and notification settings (PRD F9–F16),
/// one method per function in `docs/contract-activity.md`. Contract errors
/// come back as `ActivityError`; anything else (network, auth) as whatever
/// the transport throws.
///
/// Who is walking and each member's status arrive with `familyToday`
/// (`walkingSince`, `walkEndsAt`, `status`), which is the family service's
/// job, not this one's.
protocol ActivityService: Sendable {
    // Walks (F9–F11)
    func startWalk() async throws -> WalkStart
    func stopWalk() async throws

    // Status (F12)
    func setStatus(_ input: StatusInput) async throws
    func clearStatus() async throws

    // Feed and reactions (F13, F14)
    func feed(familyId: String) async throws -> [FeedEvent]
    func react(eventId: String, emoji: Reaction) async throws

    // Notifications (F15, F16)
    func notificationPrefs() async throws -> NotificationPrefs
    func setNotificationPrefs(_ patch: NotificationPrefsPatch) async throws
    func registerDevice(apnsToken: String, environment: APNsEnvironment) async throws
    func unregisterDevice(apnsToken: String) async throws
}
