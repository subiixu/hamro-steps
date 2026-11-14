import Foundation

/// The Convex-backed `AuthService` and `FamilyService`, sharing one client
/// and one session.
struct ConvexServices: Sendable {
    let auth: ConvexAuthService
    let family: ConvexFamilyService

    init(connection: ConvexConnection) {
        auth = ConvexAuthService(connection: connection)
        family = ConvexFamilyService(connection: connection)
    }

    /// The real thing: the SDK client against `config`, the session in the
    /// system Keychain.
    static func live(config: ConvexConfig) -> ConvexServices {
        let session = ConvexSession(
            endpoints: URLSessionAuthEndpoints(siteURL: config.siteURL),
            keychain: SystemKeychain(),
            marker: UserDefaultsSignOutMarker()
        )
        let transport = LiveConvexTransport(deploymentURL: config.deploymentURL, session: session)
        return ConvexServices(connection: ConvexConnection(transport: transport, session: session))
    }
}
