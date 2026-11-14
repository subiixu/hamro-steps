import Foundation

/// `ActivityService` against the Convex backend (`convex/walks.ts`,
/// `status.ts`, `feed.ts`, `notifications.ts`). Contract codes come out as
/// `ActivityError`; everything else as the connection's `FamilyServiceError`
/// (`notAuthenticated`, `unavailable(…)`).
///
/// `registerDevice` and `unregisterDevice` throw `CancellationError` as soon
/// as their task is cancelled, even when the network call never comes back,
/// so `PushRegistrar`'s timeout can't leave its serial queue stuck.
struct ConvexActivityService: ActivityService {
    let connection: ConvexConnection

    // MARK: Walks

    func startWalk() async throws -> WalkStart {
        try await mutation("walks:startWalk", [:])
    }

    func stopWalk() async throws {
        let _: ConvexNull = try await mutation("walks:stopWalk", [:])
    }

    // MARK: Status

    /// Only the set fields are sent: the backend tells "no preset" from a
    /// missing key, not from `null`.
    func setStatus(_ input: StatusInput) async throws {
        var args: [String: ConvexArg] = [:]
        if let preset = input.preset { args["preset"] = .string(preset.rawValue) }
        if let text = input.text { args["text"] = .string(text) }
        if let expiresAt = input.expiresAt { args["expiresAt"] = .number(expiresAt) }
        struct StatusSet: Decodable, Sendable {}
        let _: StatusSet = try await mutation("status:setStatus", args)
    }

    func clearStatus() async throws {
        let _: ConvexNull = try await mutation("status:clearStatus", [:])
    }

    // MARK: Feed and reactions

    func feed(familyId: String) async throws -> [FeedEvent] {
        try await query("feed:feed", ["familyId": .string(familyId)])
    }

    func react(eventId: String, emoji: Reaction) async throws {
        struct Reacted: Decodable, Sendable { let myReaction: String? }
        let _: Reacted = try await mutation("feed:react", ["eventId": .string(eventId), "emoji": .string(emoji.rawValue)])
    }

    // MARK: Notifications

    func notificationPrefs() async throws -> NotificationPrefs {
        try await query("notifications:notificationPrefs", [:])
    }

    func setNotificationPrefs(_ patch: NotificationPrefsPatch) async throws {
        var args: [String: ConvexArg] = [:]
        if let value = patch.walkStarted { args["walkStarted"] = .bool(value) }
        if let value = patch.goalHit { args["goalHit"] = .bool(value) }
        if let value = patch.reactions { args["reactions"] = .bool(value) }
        if let value = patch.eveningNudge { args["eveningNudge"] = .bool(value) }
        let _: NotificationPrefs = try await mutation("notifications:setNotificationPrefs", args)
    }

    func registerDevice(apnsToken: String, environment: APNsEnvironment) async throws {
        try await Self.returningOnCancel {
            let _: ConvexNull = try await mutation("notifications:registerDevice", [
                "apnsToken": .string(apnsToken),
                "environment": .string(environment.rawValue),
            ])
        }
    }

    func unregisterDevice(apnsToken: String) async throws {
        try await Self.returningOnCancel {
            let _: ConvexNull = try await mutation("notifications:unregisterDevice", ["apnsToken": .string(apnsToken)])
        }
    }

    // MARK: Plumbing

    private func query<T: Decodable & Sendable>(_ name: String, _ args: [String: ConvexArg]) async throws -> T {
        do {
            return try await connection.run { try await $0.query(name, args: args) }
        } catch {
            throw Self.activityError(error)
        }
    }

    private func mutation<T: Decodable & Sendable>(_ name: String, _ args: [String: ConvexArg]) async throws -> T {
        do {
            return try await connection.run { try await $0.mutation(name, args: args) }
        } catch {
            throw Self.activityError(error)
        }
    }

    /// A contract code from the activity functions becomes `ActivityError`;
    /// anything else stays as the connection threw it.
    static func activityError(_ error: any Error) -> any Error {
        guard let error = error as? FamilyServiceError else { return error }
        return ActivityError(rawValue: error.code) ?? error
    }

    /// Runs `operation` in a task of its own and returns with its result, or
    /// throws `CancellationError` the moment the calling task is cancelled,
    /// whichever comes first. A cancelled operation is cancelled too, but not
    /// waited for: a transport that ignores cancellation only leaks that
    /// call, never the caller.
    static func returningOnCancel(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation()
        let race = Race()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                race.install(continuation)
                race.start(Task {
                    do {
                        try await operation()
                        race.finish(.success(()))
                    } catch {
                        race.finish(.failure(error))
                    }
                })
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
            race.cancel()
        }
    }

    /// The one continuation, resumed once by whichever side gets there first.
    /// The cancel handler can run before the continuation exists (or the
    /// operation can finish before it does), so the result waits for it.
    private final class Race: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, any Error>?
        private var result: Result<Void, any Error>?
        private var task: Task<Void, Never>?
        private var isCancelled = false

        func install(_ continuation: CheckedContinuation<Void, any Error>) {
            let ready: Result<Void, any Error>? = lock.withLock {
                if let result { return result }
                self.continuation = continuation
                return nil
            }
            if let ready { continuation.resume(with: ready) }
        }

        func finish(_ outcome: Result<Void, any Error>) {
            let waiting: CheckedContinuation<Void, any Error>? = lock.withLock {
                guard result == nil else { return nil }
                result = outcome
                defer { continuation = nil }
                return continuation
            }
            waiting?.resume(with: outcome)
        }

        func start(_ task: Task<Void, Never>) {
            let cancelNow = lock.withLock {
                self.task = task
                return isCancelled
            }
            if cancelNow { task.cancel() }
        }

        func cancel() {
            let running = lock.withLock {
                isCancelled = true
                return task
            }
            running?.cancel()
        }
    }
}
