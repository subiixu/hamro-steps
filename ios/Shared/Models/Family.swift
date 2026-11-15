import Foundation

// Codable mirrors of the Convex backend contract
// (handoffs/briefs/2026-11-14-1415-convex-core.md). Keys match the backend's
// JSON so the Convex phase can decode straight into these.

/// The signed-in person: `me()` (and what `/auth/apple` tells us).
struct AppUser: Codable, Hashable, Sendable, Identifiable {
    let userId: String
    /// `nil` until they've told us what to call them (Apple only sends a name
    /// on the very first sign-in).
    var name: String?
    var needsName: Bool
    var timezone: String?
    /// Milliseconds since 1970.
    var lastSyncedAt: Double?
    /// Their profile photo; `nil` shows their initial instead.
    var photoUrl: String?
    /// "Lives in": a place they typed, never device location.
    var city: String?
    /// "YYYY-MM-DD", or `nil` when they haven't given one.
    var birthday: String?

    var id: String { userId }
    var displayName: String { name ?? "" }

    init(userId: String, name: String?, needsName: Bool, timezone: String? = nil, lastSyncedAt: Double? = nil,
         photoUrl: String? = nil, city: String? = nil, birthday: String? = nil) {
        self.userId = userId
        self.name = name
        self.needsName = needsName
        self.timezone = timezone
        self.lastSyncedAt = lastSyncedAt
        self.photoUrl = photoUrl
        self.city = city
        self.birthday = birthday
    }
}

/// The backend's `FamilyView`: `createFamily`, `joinFamily`, `updateFamily`,
/// `familyToday(...).family`, and (with `isOrganiser` and `position`)
/// `myFamilies()` items. Named `FamilySummary` here so it isn't mistaken for
/// a SwiftUI view.
struct FamilySummary: Codable, Hashable, Sendable, Identifiable {
    let familyId: String
    var name: String
    var dailyGoal: Int
    var inviteCode: String
    var organiserId: String
    var memberCount: Int
    var isFull: Bool
    /// Only in `myFamilies()`.
    var isOrganiser: Bool?
    /// Only in `myFamilies()`: this person's place in the family.
    var position: Int?

    var id: String { familyId }
}

/// `previewInvite({code})`: what the join screen shows before joining.
struct InvitePreview: Codable, Hashable, Sendable {
    let familyId: String
    var name: String
    var memberCount: Int
    var isFull: Bool
    var alreadyMember: Bool
}

/// One person in a family, in fixed family order (`position`), never ranked.
struct FamilyMember: Codable, Hashable, Sendable, Identifiable {
    let userId: String
    /// Empty when the person hasn't given a name yet (`null` from the backend).
    var name: String
    var position: Int
    var isOrganiser: Bool
    /// Today's steps. `nil` means "not synced yet", which is not the same as 0.
    var steps: Int?
    /// Milliseconds since 1970, as Convex sends it.
    var lastSyncedAt: Double?
    /// Milliseconds since 1970; set while the member is out on a walk.
    var walkingSince: EpochMillis?
    /// When the server closes the walk; `nil` while not walking.
    var walkEndsAt: EpochMillis?
    /// The member's status; the server sends `nil` once it has expired.
    var status: MemberStatus?
    var photoUrl: String?
    /// "Lives in", as they typed it.
    var city: String?
    /// IANA identifier of their phone's time zone, for "their time now".
    var timezone: String?
    /// "YYYY-MM-DD"; only `familyToday` sends it.
    var birthday: String?

    var id: String { userId }

    /// The walk in progress, or `nil` when not walking.
    var activeWalk: ActiveWalk? {
        ActiveWalk(walkingSince: walkingSince, walkEndsAt: walkEndsAt)
    }

    var lastSynced: Date? {
        lastSyncedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    init(userId: String, name: String, position: Int, isOrganiser: Bool, steps: Int?, lastSyncedAt: Double?,
         walkingSince: EpochMillis? = nil, walkEndsAt: EpochMillis? = nil, status: MemberStatus? = nil,
         photoUrl: String? = nil, city: String? = nil, timezone: String? = nil, birthday: String? = nil) {
        self.userId = userId
        self.name = name
        self.photoUrl = photoUrl
        self.city = city
        self.timezone = timezone
        self.birthday = birthday
        self.position = position
        self.isOrganiser = isOrganiser
        self.steps = steps
        self.lastSyncedAt = lastSyncedAt
        self.walkingSince = walkingSince
        self.walkEndsAt = walkEndsAt
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case userId, name, position, isOrganiser, steps, lastSyncedAt
        case walkingSince, walkEndsAt, status
        case photoUrl, city, timezone, birthday
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        position = try c.decode(Int.self, forKey: .position)
        isOrganiser = try c.decode(Bool.self, forKey: .isOrganiser)
        steps = try c.decodeIfPresent(Int.self, forKey: .steps)
        lastSyncedAt = try c.decodeIfPresent(Double.self, forKey: .lastSyncedAt)
        walkingSince = try c.decodeIfPresent(EpochMillis.self, forKey: .walkingSince)
        walkEndsAt = try c.decodeIfPresent(EpochMillis.self, forKey: .walkEndsAt)
        status = try c.decodeIfPresent(MemberStatus.self, forKey: .status)
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        birthday = try c.decodeIfPresent(String.self, forKey: .birthday)
    }
}

/// `familyToday({familyId})`: the family's progress for the current Nepal day.
struct FamilyToday: Codable, Hashable, Sendable {
    var family: FamilySummary
    /// Nepal day, "YYYY-MM-DD".
    var day: String
    var goal: Int
    var total: Int
    /// Whole percent of the goal; not capped at 100.
    var percent: Int
    var members: [FamilyMember]
}

/// `familyWeek({familyId})`: Monday to Sunday of the current Nepal week.
struct FamilyWeek: Codable, Hashable, Sendable {
    /// Nepal day, "YYYY-MM-DD".
    var today: String
    var weekStart: String
    /// Epoch milliseconds of Monday's Nepal midnight.
    var startsAt: Double
    var days: [FamilyWeekDay]
}

struct FamilyWeekDay: Codable, Hashable, Sendable, Identifiable {
    /// Nepal day, "YYYY-MM-DD".
    var day: String
    var total: Int
    var goal: Int
    var hit: Bool
    var isFuture: Bool
    /// Before the family existed: shown greyed out, not as a missed day.
    var isBeforeFamily: Bool

    var id: String { day }
}

/// One entry of the `syncSteps({days})` payload.
struct StepDay: Codable, Hashable, Sendable {
    /// Nepal day, "YYYY-MM-DD".
    var day: String
    var steps: Int
}

/// What `syncSteps` returns.
struct SyncStepsResult: Codable, Hashable, Sendable {
    /// Epoch milliseconds.
    var lastSyncedAt: Double
    /// Nepal day the server considers today.
    var today: String
}

/// The backend's stable error codes (`ConvexError({code})`), plus a catch-all
/// for anything else (offline, server trouble).
enum FamilyServiceError: Error, Hashable, Sendable {
    case notAuthenticated
    case invalidCode
    case familyFull
    case notMember
    case notOrganiser
    case invalidGoal
    case invalidName
    case invalidSteps
    case invalidDay
    case cannotRemoveSelf
    case invalidToken
    case invalidPhoto
    case invalidCity
    case invalidBirthday
    case unavailable(String)

    init(code: String) {
        switch code {
        case "not_authenticated": self = .notAuthenticated
        case "invalid_code": self = .invalidCode
        case "family_full": self = .familyFull
        case "not_member": self = .notMember
        case "not_organiser": self = .notOrganiser
        case "invalid_goal": self = .invalidGoal
        case "invalid_name": self = .invalidName
        case "invalid_steps": self = .invalidSteps
        case "invalid_day": self = .invalidDay
        case "cannot_remove_self": self = .cannotRemoveSelf
        case "invalid_token": self = .invalidToken
        case "invalid_photo": self = .invalidPhoto
        case "invalid_city": self = .invalidCity
        case "invalid_birthday": self = .invalidBirthday
        default: self = .unavailable(code)
        }
    }

    var code: String {
        switch self {
        case .notAuthenticated: "not_authenticated"
        case .invalidCode: "invalid_code"
        case .familyFull: "family_full"
        case .notMember: "not_member"
        case .notOrganiser: "not_organiser"
        case .invalidGoal: "invalid_goal"
        case .invalidName: "invalid_name"
        case .invalidSteps: "invalid_steps"
        case .invalidDay: "invalid_day"
        case .cannotRemoveSelf: "cannot_remove_self"
        case .invalidToken: "invalid_token"
        case .invalidPhoto: "invalid_photo"
        case .invalidCity: "invalid_city"
        case .invalidBirthday: "invalid_birthday"
        case .unavailable(let code): code
        }
    }

    /// Plain, friendly words for a parent. Never blames the person.
    var message: String {
        switch self {
        case .invalidCode:
            String(localized: "We couldn't find a family with that code. Check it with the person who sent it.")
        case .familyFull:
            String(localized: "This family already has 8 people, the most a family can have. Ask whoever invited you about it.")
        case .invalidName:
            String(localized: "Please use a name between 1 and 40 letters.")
        case .invalidGoal:
            String(localized: "Pick a daily goal between 1,000 and 1,000,000 steps.")
        case .notOrganiser:
            String(localized: "Only the family organiser can change this.")
        case .notMember:
            String(localized: "You're no longer in this family.")
        case .notAuthenticated, .invalidToken:
            String(localized: "Please sign in again.")
        case .cannotRemoveSelf:
            String(localized: "To take yourself out of the family, use Leave family instead.")
        case .invalidPhoto:
            String(localized: "That photo didn't work. Please try a different one.")
        case .invalidCity:
            String(localized: "Please keep the place to 40 letters or fewer.")
        case .invalidBirthday:
            String(localized: "Please pick a birthday that's already happened.")
        case .invalidSteps, .invalidDay, .unavailable:
            String(localized: "Something went wrong. Please try again in a moment.")
        }
    }
}

/// Limits the backend enforces, mirrored so forms can check before sending.
enum FamilyRules {
    static let goalRange = 1_000...1_000_000
    static let suggestedGoal = 50_000
    static let goalPresets = [30_000, 50_000, 75_000, 100_000]
    static let nameLength = 1...40
    static let cityMaxLength = 40
    static let maxMembers = 8
    static let stepsRange = 0...200_000

    static func cleanName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidName(_ name: String) -> Bool {
        nameLength.contains(cleanName(name).count)
    }

    /// Trimmed; empty means "no city".
    static func cleanCity(_ city: String) -> String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidCity(_ city: String) -> Bool {
        cleanCity(city).count <= cityMaxLength
    }
}

// `FamilyMember` is Hashable and carries a status. Written out by hand
// because Swift only synthesises it in the file that declares the type.
extension MemberStatus: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(preset)
        hasher.combine(text)
        hasher.combine(expiresAt)
    }
}
