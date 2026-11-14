import Foundation

extension PushInbox {
    /// A tapped notification: show its family on Home. Does nothing until
    /// Home is showing with its family list (the tap may come during
    /// sign-in or onboarding), and keeps the tap for the next try; RootView
    /// tries again on every tap, family list change and route change. A
    /// family the person isn't in leaves Home as it was.
    func open(session: SessionStore, home: HomeModel) async {
        guard pending != nil, session.route == .main, !home.families.isEmpty else { return }
        guard case .family(let familyId, _) = take(familyIds: session.families.map(\.id)) else { return }
        // Home has no hook to scroll to a feed event yet, so the event id
        // goes unused for now.
        if home.selectedFamilyId != familyId { await home.select(familyId) }
    }
}
