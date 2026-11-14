import Foundation

// Models for walks, status, feed, reactions and notification settings
// (PRD F9–F16). They match `docs/contract-activity.md` exactly: field names,
// enum keys and timestamps (milliseconds since 1970, as Convex sends them).
// Foundation only, so a widget target can compile this file too.

/// Milliseconds since 1970, as Convex sends timestamps.
typealias EpochMillis = Double

/// Converts between Convex timestamps and `Date`.
enum ActivityTime {
    static func date(_ millis: EpochMillis) -> Date {
        Date(timeIntervalSince1970: millis / 1000)
    }

    static func millis(_ date: Date) -> EpochMillis {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    /// Every "day" in the contract is a Nepal day.
    static let nepal = TimeZone(identifier: "Asia/Kathmandu")!

    static var nepalCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = nepal
        return calendar
    }
}

// MARK: - Errors

/// The `ConvexError({code})` codes from the contract.
enum ActivityError: String, Error, Codable, Sendable, Equatable {
    case alreadyWalking = "already_walking"
    case walkLimitReached = "walk_limit_reached"
    case invalidStatus = "invalid_status"
    case invalidExpiry = "invalid_expiry"
    case invalidEmoji = "invalid_emoji"
    case notMember = "not_member"
}

// MARK: - Walks (F9–F11)

enum WalkRules {
    /// A walk ends by itself 2 hours after it starts.
    static let duration: TimeInterval = 2 * 60 * 60
    /// Walk alerts a member can start per Nepal day.
    static let dailyLimit = 3
}

/// `startWalk()` result.
struct WalkStart: Codable, Equatable, Sendable {
    var walkId: String
    var startedAt: EpochMillis
    var endsAt: EpochMillis
}

/// A walk in progress, from `startWalk()` or from a member's
/// `walkingSince` / `walkEndsAt` in `familyToday`.
struct ActiveWalk: Equatable, Sendable {
    var startedAt: Date
    var endsAt: Date

    init(startedAt: Date, endsAt: Date) {
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    init(_ start: WalkStart) {
        self.init(startedAt: ActivityTime.date(start.startedAt), endsAt: ActivityTime.date(start.endsAt))
    }

    /// From `familyToday.members[]`. Nil when the member isn't walking.
    init?(walkingSince: EpochMillis?, walkEndsAt: EpochMillis?) {
        guard let walkingSince else { return nil }
        let start = ActivityTime.date(walkingSince)
        let end = walkEndsAt.map(ActivityTime.date) ?? start.addingTimeInterval(WalkRules.duration)
        self.init(startedAt: start, endsAt: end)
    }

    /// The server closes the walk at `endsAt`; the app stops showing it then
    /// too, without waiting for the next refresh.
    func isOver(at now: Date) -> Bool { now >= endsAt }
}

// MARK: - Status (F12)

enum StatusPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case atWork = "at_work"
    case atHome = "at_home"
    case commuting
    case workingOut = "working_out"
    case onAHike = "on_a_hike"
    case resting
    case travelling

    var id: String { rawValue }

    /// The PRD's labels.
    var label: String {
        switch self {
        case .atWork: String(localized: "At work")
        case .atHome: String(localized: "At home")
        case .commuting: String(localized: "Commuting")
        case .workingOut: String(localized: "Working out")
        case .onAHike: String(localized: "On a hike")
        case .resting: String(localized: "Resting")
        case .travelling: String(localized: "Travelling")
        }
    }
}

/// `familyToday.members[].status`.
struct MemberStatus: Codable, Equatable, Sendable {
    var preset: StatusPreset?
    var text: String?
    var expiresAt: EpochMillis

    init(preset: StatusPreset? = nil, text: String? = nil, expiresAt: EpochMillis) {
        self.preset = preset
        self.text = text
        self.expiresAt = expiresAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown preset key (a newer server) reads as no preset rather
        // than failing the whole family screen.
        preset = try c.decodeIfPresent(String.self, forKey: .preset).flatMap(StatusPreset.init(rawValue:))
        text = try c.decodeIfPresent(String.self, forKey: .text)
        expiresAt = try c.decode(EpochMillis.self, forKey: .expiresAt)
    }

    var expiresDate: Date { ActivityTime.date(expiresAt) }

    func isActive(at now: Date) -> Bool { expiresDate > now }

    /// What a member row shows: the preset label or the custom text.
    var displayText: String? {
        if let preset { return preset.label }
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        return nil
    }
}

/// `setStatus` arguments. Build it with `validated(…)`, which applies the
/// same rules as the server, so the picker can explain a problem before
/// sending.
struct StatusInput: Codable, Equatable, Sendable {
    var preset: StatusPreset?
    var text: String?
    var expiresAt: EpochMillis?

    static let maxTextLength = 30
    static let defaultDuration: TimeInterval = 24 * 60 * 60
    static let maxDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Length as the server counts it (a JavaScript string's `.length`,
    /// UTF-16 code units), so the counter and the server always agree.
    static func length(of text: String) -> Int { text.utf16.count }

    /// Cuts text to the limit without splitting a character.
    static func clamped(_ text: String) -> String {
        guard length(of: text) > maxTextLength else { return text }
        var result = ""
        for character in text {
            guard length(of: result) + String(character).utf16.count <= maxTextLength else { break }
            result.append(character)
        }
        return result
    }

    /// Exactly one of `preset` / `text` (text is trimmed, blank counts as
    /// none, at most 30 long); `expiresAt`, when given, in the future and at
    /// most 7 days ahead. Nil `expiresAt` lets the server default to 24 h.
    static func validated(preset: StatusPreset?, text: String?, expiresAt: Date?, now: Date) throws(ActivityError) -> StatusInput {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard (preset == nil) != (cleanText == nil) else { throw .invalidStatus }
        if let cleanText, length(of: cleanText) > maxTextLength { throw .invalidStatus }
        if let expiresAt {
            guard expiresAt > now, expiresAt <= now.addingTimeInterval(maxDuration) else { throw .invalidExpiry }
        }
        return StatusInput(preset: preset, text: cleanText, expiresAt: expiresAt.map(ActivityTime.millis))
    }
}

/// The expiry choices in the status picker.
enum StatusExpiry: String, CaseIterable, Identifiable, Sendable {
    case day
    case tonight
    case oneHour
    case fourHours

    static let `default`: StatusExpiry = .day
    /// "Until tonight" means 21:00 local time.
    static let tonightHour = 21

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: String(localized: "24 hours")
        case .tonight: String(localized: "Until tonight")
        case .oneHour: String(localized: "1 hour")
        case .fourHours: String(localized: "4 hours")
        }
    }

    /// When a status set at `now` clears. Nil for "until tonight" once
    /// 21:00 has passed, so the picker hides that option.
    func expiry(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .day: return now.addingTimeInterval(StatusInput.defaultDuration)
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .fourHours: return now.addingTimeInterval(4 * 60 * 60)
        case .tonight:
            guard let tonight = calendar.date(bySettingHour: Self.tonightHour, minute: 0, second: 0, of: now),
                  tonight > now else { return nil }
            return tonight
        }
    }

    static func available(at now: Date, calendar: Calendar = .current) -> [StatusExpiry] {
        allCases.filter { $0.expiry(from: now, calendar: calendar) != nil }
    }
}

// MARK: - Reactions (F14)

/// The fixed set of 5. These are user content (PRD), not icons.
enum Reaction: String, Codable, CaseIterable, Identifiable, Sendable {
    case clap = "👏"
    case heart = "❤️"
    case raisedHands = "🙌"
    case fire = "🔥"
    case laugh = "😄"

    var id: String { rawValue }

    /// Accepts the plain heart without the emoji variation selector too.
    init?(emoji: String) {
        if let match = Reaction(rawValue: emoji) {
            self = match
        } else if emoji == "\u{2764}" {
            self = .heart
        } else {
            return nil
        }
    }

    /// What VoiceOver reads.
    var spokenName: String {
        switch self {
        case .clap: String(localized: "Clap")
        case .heart: String(localized: "Love")
        case .raisedHands: String(localized: "Raised hands")
        case .fire: String(localized: "Fire")
        case .laugh: String(localized: "Laugh")
        }
    }
}

struct ReactionCount: Codable, Equatable, Sendable {
    var emoji: Reaction
    var count: Int
}

// MARK: - Feed (F13)

enum FeedEventType: String, Codable, Sendable {
    case member5k = "member_5k"
    case member10k = "member_10k"
    case family50 = "family_50"
    case family100 = "family_100"
    case walkStarted = "walk_started"
    /// A type this version of the app doesn't know; the feed skips it.
    case unknown

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FeedEventType(rawValue: raw) ?? .unknown
    }
}

struct FeedActor: Codable, Equatable, Sendable {
    var userId: String
    var name: String
    /// Hex, e.g. "#E4572E", from the backend's 8-colour palette.
    var avatarColor: String
}

struct FeedEventData: Codable, Equatable, Sendable {
    var walkId: String?
}

struct FeedEvent: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var type: FeedEventType
    var actor: FeedActor?
    /// Nepal day, "YYYY-MM-DD".
    var day: String
    var createdAt: EpochMillis
    var data: FeedEventData?
    var reactions: [ReactionCount]
    var myReaction: Reaction?

    init(id: String, type: FeedEventType, actor: FeedActor?, day: String, createdAt: EpochMillis,
         data: FeedEventData? = nil, reactions: [ReactionCount] = [], myReaction: Reaction? = nil) {
        self.id = id
        self.type = type
        self.actor = actor
        self.day = day
        self.createdAt = createdAt
        self.data = data
        self.reactions = reactions
        self.myReaction = myReaction
    }

    private struct RawReactionCount: Decodable {
        var emoji: String
        var count: Int
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(FeedEventType.self, forKey: .type)
        actor = try c.decodeIfPresent(FeedActor.self, forKey: .actor)
        day = try c.decode(String.self, forKey: .day)
        createdAt = try c.decode(EpochMillis.self, forKey: .createdAt)
        data = try? c.decodeIfPresent(FeedEventData.self, forKey: .data)
        // Emoji outside the fixed set are dropped rather than failing the feed.
        let raw = try c.decodeIfPresent([RawReactionCount].self, forKey: .reactions) ?? []
        reactions = raw.compactMap { item in
            Reaction(emoji: item.emoji).map { ReactionCount(emoji: $0, count: item.count) }
        }
        myReaction = try c.decodeIfPresent(String.self, forKey: .myReaction).flatMap(Reaction.init(emoji:))
    }

    var createdDate: Date { ActivityTime.date(createdAt) }

    /// Whether this app knows how to show the event.
    var isDisplayable: Bool { type != .unknown }

    func count(for emoji: Reaction) -> Int {
        reactions.first { $0.emoji == emoji }?.count ?? 0
    }

    /// The contract's rule for one viewer: the same emoji again removes it,
    /// a different one replaces it, otherwise it's added. Counts stay in the
    /// fixed emoji order and zero counts are dropped.
    func reacting(with emoji: Reaction) -> FeedEvent {
        var counts = Dictionary(uniqueKeysWithValues: Reaction.allCases.map { ($0, count(for: $0)) })
        var copy = self
        if let current = myReaction {
            counts[current] = max(0, (counts[current] ?? 0) - 1)
        }
        if myReaction == emoji {
            copy.myReaction = nil
        } else {
            counts[emoji, default: 0] += 1
            copy.myReaction = emoji
        }
        copy.reactions = Reaction.allCases.compactMap { emoji in
            let n = counts[emoji] ?? 0
            return n > 0 ? ReactionCount(emoji: emoji, count: n) : nil
        }
        return copy
    }

    /// The event in plain words: "Mum passed 5,000 steps", "You started a
    /// walk", "The family reached today's goal!".
    func text(viewerId: String?, locale: Locale = .current) -> String {
        let isMe = actor != nil && actor?.userId == viewerId
        let name = actor?.name ?? String(localized: "Someone")
        switch type {
        case .member5k:
            let steps = StepFormatter.count(5_000, locale: locale)
            return isMe ? String(localized: "You passed \(steps) steps") : String(localized: "\(name) passed \(steps) steps")
        case .member10k:
            let steps = StepFormatter.count(10_000, locale: locale)
            return isMe ? String(localized: "You passed \(steps) steps") : String(localized: "\(name) passed \(steps) steps")
        case .family50:
            return String(localized: "The family is halfway to today's goal!")
        case .family100:
            return String(localized: "The family reached today's goal!")
        case .walkStarted:
            return isMe ? String(localized: "You started a walk") : String(localized: "\(name) started a walk")
        case .unknown:
            return ""
        }
    }
}

// MARK: - Notifications (F15, F16)

/// `notificationPrefs()`.
struct NotificationPrefs: Codable, Equatable, Sendable {
    var walkStarted: Bool
    var goalHit: Bool
    var reactions: Bool
    var eveningNudge: Bool

    static let defaults = NotificationPrefs(walkStarted: true, goalHit: true, reactions: true, eveningNudge: false)

    subscript(kind: NotificationKind) -> Bool {
        get {
            switch kind {
            case .walkStarted: walkStarted
            case .goalHit: goalHit
            case .reactions: reactions
            case .eveningNudge: eveningNudge
            }
        }
        set {
            switch kind {
            case .walkStarted: walkStarted = newValue
            case .goalHit: goalHit = newValue
            case .reactions: reactions = newValue
            case .eveningNudge: eveningNudge = newValue
            }
        }
    }

    func applying(_ patch: NotificationPrefsPatch) -> NotificationPrefs {
        NotificationPrefs(
            walkStarted: patch.walkStarted ?? walkStarted,
            goalHit: patch.goalHit ?? goalHit,
            reactions: patch.reactions ?? reactions,
            eveningNudge: patch.eveningNudge ?? eveningNudge
        )
    }
}

/// `setNotificationPrefs(partial)`: only the set fields are sent.
struct NotificationPrefsPatch: Codable, Equatable, Sendable {
    var walkStarted: Bool?
    var goalHit: Bool?
    var reactions: Bool?
    var eveningNudge: Bool?

    init(walkStarted: Bool? = nil, goalHit: Bool? = nil, reactions: Bool? = nil, eveningNudge: Bool? = nil) {
        self.walkStarted = walkStarted
        self.goalHit = goalHit
        self.reactions = reactions
        self.eveningNudge = eveningNudge
    }

    init(_ kind: NotificationKind, _ value: Bool) {
        self.init()
        switch kind {
        case .walkStarted: walkStarted = value
        case .goalHit: goalHit = value
        case .reactions: reactions = value
        case .eveningNudge: eveningNudge = value
        }
    }
}

enum NotificationKind: String, CaseIterable, Identifiable, Sendable {
    case walkStarted
    case goalHit
    case reactions
    case eveningNudge

    var id: String { rawValue }
}

/// `registerDevice(apnsToken, environment)`.
enum APNsEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}
