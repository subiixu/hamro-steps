import Foundation

/// The 6-character family code. Typing or pasting it ignores case, spaces
/// and dashes, the same as the backend's `joinFamily`.
enum InviteCode {
    /// No 0/O, 1/I/L: easy to read aloud over the phone.
    static let alphabet = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 6

    /// Upper-cased with spaces and dashes removed: " k7m-2qx " → "K7M2QX".
    static func normalise(_ text: String) -> String {
        text.uppercased().filter { !$0.isWhitespace && !isDash($0) }
    }

    static func isValid(_ text: String) -> Bool {
        let code = normalise(text)
        return code.count == length && code.allSatisfy(alphabet.contains)
    }

    /// The code from whatever was pasted: the bare code, or the whole invite
    /// message (where the code is the one upper-case 6-character word).
    static func extract(from text: String) -> String? {
        if isValid(text) { return normalise(text) }
        let words = text.split(whereSeparator: { $0.isWhitespace || ":.,!?()\"'".contains($0) })
        for word in words {
            let candidate = normalise(String(word))
            // Only upper-case words in a longer message, so ordinary words
            // like "family" are never mistaken for a code.
            if String(word) == String(word).uppercased(), isValid(candidate) { return candidate }
        }
        return nil
    }

    /// For showing in big type: "K7M 2QX".
    static func display(_ code: String) -> String {
        let clean = normalise(code)
        guard clean.count == length else { return clean }
        return "\(clean.prefix(3)) \(clean.suffix(3))"
    }

    private static func isDash(_ c: Character) -> Bool {
        c == "-" || c == "‐" || c == "‑" || c == "–" || c == "—"
    }
}

/// The invite message people forward on WhatsApp or Messenger.
enum InviteMessage {
    /// The hosted invite page (web/invite): shows the code and the TestFlight install link.
    static let invitePage = URL(string: "https://subiixu.github.io/hamro-steps/invite/")!

    static func installURL(code: String) -> URL {
        var parts = URLComponents(url: invitePage, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "code", value: InviteCode.normalise(code))]
        return parts.url!
    }

    static func text(familyName: String, code: String) -> String {
        """
        Join \(familyName) on Hamro Steps, so we can walk together every day.

        1. Install the app: \(installURL(code: code).absoluteString)
        2. Open it, sign in, and enter our family code: \(InviteCode.normalise(code))
        """
    }
}
