import SwiftUI

/// Every icon in the app. All are Hugeicons free set, stroke-rounded, 1.5
/// stroke, stored as template SVGs in SharedAssets.xcassets/Icons, so they
/// take the surrounding foreground colour like `currentColor` on the web.
///
/// Use `Icon.home` as a view (24pt by default, `.size(_:)` to change), or
/// `Icon.home.image` where SwiftUI needs a bare `Image` (tab items, `Label`).
enum Icon: String, CaseIterable, Sendable {
    case home = "icon-home"                  // footprints: the Home tab
    case family = "icon-family"              // user-group
    case profile = "icon-profile"            // user: the Me tab
    case settings = "icon-settings"          // settings-01: family settings
    case plus = "icon-plus"                  // add-01
    case minus = "icon-minus"                // minus-sign
    case chevronRight = "icon-chevron-right" // arrow-right-01
    case chevronDown = "icon-chevron-down"   // arrow-down-01: family switcher
    case goal = "icon-goal"                  // target-02: daily goal
    case share = "icon-share"                // share-08: invites
    case copy = "icon-copy"                  // copy-01
    case refresh = "icon-refresh"            // refresh-01: new invite code
    case health = "icon-health"              // health: Apple Health
    case clock = "icon-clock"                // clock-01: last synced, walk timer, expiry
    case tick = "icon-tick"                  // tick-02: goal hit, selected family
    case celebrate = "icon-celebrate"        // party: goal reached
    case organiser = "icon-organiser"        // crown-02: subtle organiser mark
    case edit = "icon-edit"                  // pencil-edit-01
    case userRemove = "icon-user-remove"     // user-remove-01
    case logout = "icon-logout"              // logout-01: sign out, leave family
    case delete = "icon-delete"              // delete-02: delete account
    case close = "icon-close"                // cancel-01: close a sheet
    case calendar = "icon-calendar"          // calendar-03: "This week"
    case moments = "icon-moments"            // favourite: "Family moments"

    // Activity: walks, status, feed, notifications
    case walking = "icon-walking"            // walking: "I'm walking", badge
    case stop = "icon-stop"                  // stop: "Stop walk"
    case notification = "icon-notification"  // notification-01
    case check = "icon-check"                // tick-02: selected option
    case clear = "icon-clear"                // cancel-01: clear status
    case statusWork = "icon-status-work"             // briefcase-01
    case statusHome = "icon-status-home"             // home-01
    case statusCommuting = "icon-status-commuting"   // bus-01
    case statusWorkout = "icon-status-workout"       // dumbbell-01
    case statusHike = "icon-status-hike"             // mountain
    case statusResting = "icon-status-resting"       // sofa-01
    case statusTravelling = "icon-status-travelling" // airplane-01
    case statusCustom = "icon-status-custom"         // message-01: custom text

    var image: Image {
        Image(rawValue).renderingMode(.template)
    }

    func size(_ points: CGFloat) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(width: points, height: points)
            .accessibilityHidden(true)
    }
}

extension Icon: View {
    var body: some View { size(24) }
}
