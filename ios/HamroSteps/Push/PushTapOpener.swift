import Foundation

extension PushInbox {
    /// A tapped notification: show its family on Home. Does nothing until
    /// Home is showing with its family list (the tap may come during
    /// sign-in or onboarding), and keeps the tap for the next try; RootView
    /// tries again on every tap, family list change and route change. A
    /// family the person isn't in leaves Home as it was. A tap about one
    /// event (a reaction, a walk) also asks Home to bring it into view.
    func open(session: SessionStore, home: HomeModel) async {
        guard pending != nil, session.route == .main, !home.families.isEmpty else { return }
        guard case .family(let familyId, let eventId) = take(familyIds: session.families.map(\.id)) else { return }
        if home.selectedFamilyId != familyId { await home.select(familyId) }
        // Home scrolls to the event once the family's feed has it; an event
        // that isn't there just leaves the family showing.
        if let eventId { home.focus(eventId: eventId) }
    }
}
