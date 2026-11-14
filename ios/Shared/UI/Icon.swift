import SwiftUI

/// Every icon in the app. All are Hugeicons free set, stroke-rounded, 1.5
/// stroke, stored as template SVGs in SharedAssets.xcassets/Icons, so they
/// take the surrounding foreground colour like `currentColor` on the web.
///
/// Use `Icon.home` as a view (24pt by default, `.size(_:)` to change), or
/// `Icon.home.image` where SwiftUI needs a bare `Image` (tab items, `Label`).
enum Icon: String, CaseIterable, Sendable {
    case home = "icon-home"                  // footprints: the Today tab
    case family = "icon-family"              // user-group
    case profile = "icon-profile"            // user
    case settings = "icon-settings"          // settings-01
    case plus = "icon-plus"                  // add-01
    case chevronRight = "icon-chevron-right" // arrow-right-01
    case fire = "icon-fire"                  // streaks
    case cheer = "icon-cheer"                // clapping-01
    case goal = "icon-goal"                  // target-02
    case share = "icon-share"                // share-08: invites

    // Activity: walks, status, feed, notifications
    case walking = "icon-walking"            // walking: "I'm walking", badge
    case stop = "icon-stop"                  // stop: "Stop walk"
    case clock = "icon-clock"                // clock-01: walk timer, expiry
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
