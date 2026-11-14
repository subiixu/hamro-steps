import Foundation

/// The APNs device token as the backend wants it, and which APNs gateway it
/// belongs to.
enum DeviceToken {
    /// Lowercase hex, two characters per byte, no separators.
    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// Debug builds are signed for the APNs sandbox; everything else
    /// (TestFlight, App Store) for production.
    static func environment(isDebug: Bool) -> APNsEnvironment {
        isDebug ? .sandbox : .production
    }

    static var currentEnvironment: APNsEnvironment {
        #if DEBUG
        environment(isDebug: true)
        #else
        environment(isDebug: false)
        #endif
    }
}

/// Remembers every token this phone may have registered for the signed-in
/// account (APNs can hand out a new one while an older registration is
/// still on its way), so sign-out can take all of them back. Also remembers
/// a sign-out whose cleanup hadn't finished, so the next launch finishes it.
struct DeviceTokenStore {
    static let key = "push.deviceTokens"
    static let signOutKey = "push.signOutPending"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Oldest first.
    var tokens: [String] {
        get { defaults.stringArray(forKey: Self.key) ?? [] }
        nonmutating set {
            if newValue.isEmpty { defaults.removeObject(forKey: Self.key) } else { defaults.set(newValue, forKey: Self.key) }
        }
    }

    var lastToken: String? { tokens.last }

    func add(_ token: String) {
        tokens = tokens.filter { $0 != token } + [token]
    }

    func remove(_ token: String) {
        tokens = tokens.filter { $0 != token }
    }

    func clear() {
        tokens = []
    }

    var signOutPending: Bool {
        get { defaults.bool(forKey: Self.signOutKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.signOutKey) }
    }
}
