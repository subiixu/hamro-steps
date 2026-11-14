import Foundation
import Observation
import UIKit
import UserNotifications

/// The system side of push, behind a protocol so tests can see whether the
/// permission prompt was shown without a real device.
@MainActor
protocol PushAuthorizer {
    func status() async -> UNAuthorizationStatus
    /// Shows the system prompt (alert, sound, badge); true when allowed.
    func requestAuthorization() async -> Bool
    /// Asks APNs for a token; it arrives at the app delegate.
    func registerForRemoteNotifications()
}

struct SystemPushAuthorizer: PushAuthorizer {
    func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

/// Asks for notification permission at the right moment, hands the APNs
/// token to the backend, and takes it back before the account leaves the
/// phone.
///
/// - The prompt only shows once the person is signed in and in a family
///   (the first time Home appears), never at a cold start before sign-in.
/// - While signed in, every launch registers again: tokens change.
/// - Sign-out, account switch and deletion unregister first, so the old
///   account's pushes stop reaching a phone that changed hands.
///
/// Everything that talks to the backend about devices or changes who is
/// signed in runs on one `PushQueue`, one job at a time: registrations,
/// unregistrations, the whole sign-out (including `auth.signOut()`), sign-in
/// and account deletion. A job for one account always finishes before the
/// next account's sign-in starts, so nothing from the old account can land
/// after it. Nothing is ever abandoned: each device call has its own
/// request timeout instead, which cancels the call and waits for it to end.
@MainActor
@Observable
final class PushRegistrar {
    static let requestTimeout: Duration = .seconds(10)

    @ObservationIgnored private let activity: any ActivityService
    @ObservationIgnored private let authorizer: any PushAuthorizer
    @ObservationIgnored private let tokens: DeviceTokenStore
    @ObservationIgnored private let environment: APNsEnvironment
    @ObservationIgnored private let requestTimeout: Duration
    @ObservationIgnored private let queue = PushQueue()
    /// Whether new tokens should be registered right now.
    @ObservationIgnored private var signedIn = false

    init(
        activity: any ActivityService,
        authorizer: any PushAuthorizer = SystemPushAuthorizer(),
        tokens: DeviceTokenStore = DeviceTokenStore(),
        environment: APNsEnvironment = DeviceToken.currentEnvironment,
        requestTimeout: Duration = PushRegistrar.requestTimeout
    ) {
        self.activity = activity
        self.authorizer = authorizer
        self.tokens = tokens
        self.environment = environment
        self.requestTimeout = requestTimeout
    }

    var lastToken: String? { tokens.lastToken }

    /// A sign-out from an earlier launch that never finished.
    var hasUnfinishedSignOut: Bool { tokens.signOutPending }

    /// Call whenever sign-in or the family list changes, and at launch.
    func sessionChanged(signedIn: Bool, inFamily: Bool) async {
        self.signedIn = signedIn
        guard signedIn else { return }
        var status = await authorizer.status()
        if status == .notDetermined {
            guard inFamily else { return }
            status = await authorizer.requestAuthorization() ? .authorized : .denied
        }
        guard self.signedIn, Self.allowsPush(status) else { return }
        authorizer.registerForRemoteNotifications()
    }

    /// From `didRegisterForRemoteNotificationsWithDeviceToken`.
    func didReceive(token: Data) async {
        let hex = DeviceToken.hex(token)
        guard signedIn else { return }
        // Remembered before the call is queued: once it goes out, it may
        // reach the backend whatever happens next.
        tokens.add(hex)
        let activity = activity
        let environment = environment
        await queue.perform { [self] in
            // Queued before a sign-out or deletion started: not worth sending.
            guard signedIn else { return }
            // Best effort: the next launch tries again.
            try? await request { try await activity.registerDevice(apnsToken: hex, environment: environment) }
        }
    }

    /// Signs in through the queue, so it starts only once the previous
    /// account's sign-out (cleanup and `auth.signOut()`) has fully finished.
    func signIn<User: Sendable>(_ signIn: @escaping @MainActor () async throws -> User) async throws -> User {
        try await queue.run(signIn)
    }

    /// Sign-out (also the first half of an account switch): after any
    /// registration still on its way, unregisters every token this phone
    /// may have registered for the account, then runs `endSession` (the
    /// backend sign-out). Returns once all of that is done. Unregister
    /// errors and timeouts are ignored: they never keep anyone signed in.
    func signOut(endingWith endSession: @escaping @MainActor () async -> Void) async {
        signedIn = false
        tokens.signOutPending = true
        await queue.perform { [self] in
            await unregisterAll()
            await endSession()
            tokens.clear()
            tokens.signOutPending = false
        }
    }

    /// Account deletion: after any registration still on its way,
    /// unregisters every token, then runs `delete`. If that throws, the
    /// person is still here: call `restore()`.
    func deleteAccount(_ delete: @escaping @MainActor () async throws -> Void) async throws {
        signedIn = false
        try await queue.run { [self] in
            await unregisterAll()
            try await delete()
            tokens.clear()
        }
    }

    /// Account deletion failed: register the phone again. The registration
    /// queues behind the cleanup, so the cleanup can't undo it.
    func restore() async {
        await sessionChanged(signedIn: true, inFamily: false)
    }

    /// Nobody is signed in any more (the session had already ended): a
    /// sign-out left over from an earlier launch has nothing left to do.
    func forgetUnfinishedSignOut() {
        tokens.clear()
        tokens.signOutPending = false
    }

    /// Best effort, each one: errors and timeouts are ignored.
    private func unregisterAll() async {
        let activity = activity
        for token in tokens.tokens {
            try? await request { try await activity.unregisterDevice(apnsToken: token) }
        }
    }

    private func request(_ call: @escaping @Sendable () async throws -> Void) async throws {
        try await Self.withTimeout(requestTimeout, call)
    }

    /// Runs `operation`, cancelling it once `timeout` passes. Either way it
    /// returns only after the operation has ended, so a cancelled call can't
    /// land later, behind whatever runs next.
    nonisolated static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw PushRequestTimeout()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw PushRequestTimeout() }
            return first
        }
    }

    nonisolated static func allowsPush(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }
}

struct PushRequestTimeout: Error {}

/// Runs jobs one at a time, each to the end, in the order they were asked
/// for. A caller that stops waiting doesn't stop its job.
actor PushQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ job: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await job()
        }
        tail = Task { _ = await task.result }
        return try await task.value
    }

    func perform(_ job: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let task = Task<Void, Never> {
            await previous?.value
            await job()
        }
        tail = task
        await task.value
    }
}
