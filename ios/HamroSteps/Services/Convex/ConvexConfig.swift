import Foundation

/// Where the Convex backend lives. Both values come from build settings
/// (`CONVEX_URL`, `CONVEX_SITE_URL` in project.yml) through Info.plist, so each
/// environment sets its own without code changes.
struct ConvexConfig: Hashable, Sendable {
    /// The deployment URL the Convex client connects to (`https://<name>.convex.cloud`).
    var deploymentURL: URL
    /// Where our HTTP actions live (`https://<name>.convex.site`): `/auth/*`.
    var siteURL: URL

    static let deploymentURLKey = "ConvexURL"
    static let siteURLKey = "ConvexSiteURL"

    /// Reads both URLs from `info` (the app's Info.plist by default). `nil` when
    /// either is missing, malformed or still the project.yml placeholder.
    init?(info: [String: Any]? = Bundle.main.infoDictionary) {
        guard
            let deployment = Self.url(info?[Self.deploymentURLKey]),
            let site = Self.url(info?[Self.siteURLKey])
        else { return nil }
        self.init(deploymentURL: deployment, siteURL: site)
    }

    init(deploymentURL: URL, siteURL: URL) {
        self.deploymentURL = deploymentURL
        self.siteURL = siteURL
    }

    private static func url(_ value: Any?) -> URL? {
        guard
            let string = (value as? String)?.trimmingCharacters(in: .whitespaces),
            !string.isEmpty,
            !string.contains("placeholder"),
            !string.contains("$("),
            let url = URL(string: string),
            url.scheme == "https" || url.scheme == "http",
            url.host() != nil
        else { return nil }
        return url
    }
}
