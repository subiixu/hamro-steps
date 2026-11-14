import SwiftUI

extension View {
    /// Debug builds only: with the `-activityGallery` launch argument the app
    /// shows the activity component gallery instead of its normal screens.
    /// Add a page name to open one page directly, e.g.
    /// `-activityGallery feed` (pages: walk, members, status, feed,
    /// notifications). In release builds this does nothing.
    func activityGalleryOnLaunch() -> some View {
        modifier(ActivityGalleryLaunchModifier())
    }
}

private struct ActivityGalleryLaunchModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if let launch = ActivityGalleryLaunch.current {
            ActivityGalleryView(startPage: launch.page)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if DEBUG
enum ActivityGalleryPage: String, CaseIterable, Identifiable, Hashable {
    case walk, members, status, feed, notifications

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .walk: "Walk button"
        case .members: "Walking badge and status"
        case .status: "Status picker"
        case .feed: "Feed and reactions"
        case .notifications: "Notification settings"
        }
    }
}

struct ActivityGalleryLaunch {
    var page: ActivityGalleryPage?

    static var current: ActivityGalleryLaunch? {
        parse(ProcessInfo.processInfo.arguments)
    }

    static func parse(_ args: [String]) -> ActivityGalleryLaunch? {
        guard let index = args.firstIndex(of: "-activityGallery") else { return nil }
        let next = args.indices.contains(index + 1) ? args[index + 1] : nil
        return ActivityGalleryLaunch(page: next.flatMap(ActivityGalleryPage.init(rawValue:)))
    }
}

/// Every activity component on mock data, for design review and
/// screenshots.
struct ActivityGalleryView: View {
    let startPage: ActivityGalleryPage?

    @State private var path: [ActivityGalleryPage]
    private let service = MockActivityService(latency: .milliseconds(500))

    init(startPage: ActivityGalleryPage?) {
        self.startPage = startPage
        _path = State(initialValue: startPage.map { [$0] } ?? [])
    }

    var body: some View {
        if startPage == .status {
            // The sheet's content full screen, for screenshots.
            StatusPicker(
                current: MemberStatus(preset: .atWork, expiresAt: ActivityTime.millis(.now.addingTimeInterval(3 * 3600))),
                onSave: { try await service.setStatus($0) },
                onClear: { try await service.clearStatus() }
            )
        } else {
            NavigationStack(path: $path) {
                List(ActivityGalleryPage.allCases) { page in
                    NavigationLink(value: page) { Text(page.title) }
                }
                .navigationTitle("Activity gallery")
                .navigationDestination(for: ActivityGalleryPage.self) { page in
                    ActivityGalleryPageView(page: page, service: service)
                }
            }
        }
    }
}

private struct ActivityGalleryPageView: View {
    let page: ActivityGalleryPage
    let service: MockActivityService

    var body: some View {
        switch page {
        case .walk: GalleryWalkPage(service: service)
        case .members: GalleryMembersPage()
        case .status: GalleryStatusPage(service: service)
        case .feed: GalleryFeedPage(service: service)
        case .notifications: NotificationSettingsView(model: NotificationSettingsModel(service: service))
        }
    }
}

private struct GallerySection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryText)
                .textCase(.uppercase)
            content
        }
    }
}

private struct GalleryWalkPage: View {
    @State private var live: WalkController

    init(service: MockActivityService) {
        _live = State(initialValue: WalkController(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                GallerySection(title: "Live (mock service)") {
                    WalkButton(controller: live)
                }
                GallerySection(title: "Walking, 12 minutes in") {
                    WalkButton(
                        walk: ActiveWalk(startedAt: .now.addingTimeInterval(-12 * 60), endsAt: .now.addingTimeInterval(108 * 60)),
                        onStart: {}, onStop: {}
                    )
                }
                GallerySection(title: "3 walks shared today") {
                    WalkButton(walk: nil, notice: .limitReached, onStart: {}, onStop: {})
                }
            }
            .padding(20)
        }
        .background(.canvas)
        .navigationTitle("Walk button")
    }
}

private struct GalleryMembersPage: View {
    private struct Member: Identifiable {
        let actor: FeedActor
        let steps: Int
        let status: MemberStatus?
        let walking: Bool
        var id: String { actor.userId }
    }

    private var members: [Member] {
        let later = ActivityTime.millis(.now.addingTimeInterval(3 * 3600))
        return [
            Member(actor: MockActivityService.mum, steps: 5_240, status: MemberStatus(preset: .atHome, expiresAt: later), walking: true),
            Member(actor: MockActivityService.dad, steps: 3_100, status: MemberStatus(preset: .resting, expiresAt: later), walking: false),
            Member(actor: MockActivityService.ram, steps: 8_930, status: MemberStatus(preset: .onAHike, expiresAt: later), walking: true),
            Member(actor: MockActivityService.priya, steps: 6_475, status: MemberStatus(text: "Visiting Pokhara", expiresAt: later), walking: false),
            Member(actor: MockActivityService.me, steps: 10_210, status: nil, walking: false),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GallerySection(title: "Member rows (placement is a later phase)") {
                    VStack(spacing: 0) {
                        ForEach(members) { member in
                            row(member)
                                .padding(.vertical, 12)
                            if member.id != members.last?.id { TileDivider() }
                        }
                    }
                    .padding(.horizontal, Bento.padding)
                    .bentoSurface()
                }
                GallerySection(title: "Walking dot on its own") {
                    WalkingDot()
                }
            }
            .padding(20)
        }
        .background(.canvas)
        .navigationTitle("Members")
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility text sizes the steps move under the name, so
    /// nothing gets squeezed.
    private func row(_ member: Member) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ActivityAvatar(content: .member(member.actor), size: 44)
                .overlay(alignment: .bottomTrailing) {
                    if member.walking { WalkingDot().offset(x: 4, y: 4) }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(member.actor.name).font(.headline)
                if typeSize.isAccessibilitySize { steps(member) }
                StatusLabel(status: member.status)
                if member.walking {
                    Text("Walking now")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.accentText)
                }
            }
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize { steps(member) }
        }
    }

    private func steps(_ member: Member) -> some View {
        Text(StepFormatter.withUnit(member.steps))
            .font(.headline)
            .monospacedDigit()
            .fixedSize()
    }
}

private struct GalleryStatusPage: View {
    let service: MockActivityService
    @State private var showPicker = false
    @State private var status: MemberStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GallerySection(title: "My status") {
                    if status == nil {
                        Text("No status").foregroundStyle(.secondaryText)
                    }
                    StatusLabel(status: status)
                }
                Button("Change status") { showPicker = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.accent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.canvas)
        .navigationTitle("Status picker")
        .sheet(isPresented: $showPicker, onDismiss: refresh) {
            StatusPicker(
                current: status,
                onSave: { try await service.setStatus($0) },
                onClear: { try await service.clearStatus() }
            )
        }
        .task { refresh() }
    }

    private func refresh() {
        Task { status = await service.currentStatus() }
    }
}

private struct GalleryFeedPage: View {
    @State private var model: FeedModel

    init(service: MockActivityService) {
        _model = State(initialValue: FeedModel(
            service: service, familyId: MockActivityService.familyId, viewerId: MockActivityService.me.userId
        ))
    }

    var body: some View {
        ScrollView {
            FeedList(model: model)
                .padding(.horizontal, 16)
                .background(.surface, in: .rect(cornerRadius: 24))
                .padding(20)
        }
        .background(.canvas)
        .refreshable { await model.load() }
        .navigationTitle("Family news")
    }
}

#Preview {
    ActivityGalleryView(startPage: nil)
}
#endif
