import Foundation

/// A flag kept outside the Keychain: "this phone signed out, but the
/// Keychain may still hold that session". While it's set, `ConvexSession`
/// treats the Keychain's session and cached person as gone and keeps trying
/// to remove them, so a Keychain that refuses a delete can't sign the person
/// back in, not even after a restart.
protocol SignOutMarkerStoring: Sendable {
    var isSet: Bool { get }
    func set(_ value: Bool)
}

/// The marker in `UserDefaults`. It goes with the app on deletion while the
/// Keychain stays, but by then the logout has had its chance to revoke the
/// session on the backend.
struct UserDefaultsSignOutMarker: SignOutMarkerStoring {
    static let key = "convex.signOutPending"

    var isSet: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    func set(_ value: Bool) {
        if value {
            UserDefaults.standard.set(true, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
