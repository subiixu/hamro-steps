import Foundation
import Testing
@testable import HamroSteps

/// 2026-11-14 10:00 in Kathmandu (UTC+5:45).
let activityTestNow = ISO8601DateFormatter().date(from: "2026-11-14T04:15:00Z")!

struct StatusValidationTests {
    let now = activityTestNow

    @Test func presetAloneIsValid() throws {
        let input = try StatusInput.validated(preset: .atWork, text: nil, expiresAt: nil, now: now)
        #expect(input == StatusInput(preset: .atWork, text: nil, expiresAt: nil))
    }

    @Test func textAloneIsTrimmed() throws {
        let input = try StatusInput.validated(preset: nil, text: "  Visiting Pokhara \n", expiresAt: nil, now: now)
        #expect(input.text == "Visiting Pokhara")
        #expect(input.preset == nil)
    }

    @Test func blankTextWithPresetCountsAsPresetOnly() throws {
        let input = try StatusInput.validated(preset: .resting, text: "   ", expiresAt: nil, now: now)
        #expect(input.text == nil)
        #expect(input.preset == .resting)
    }

    @Test(arguments: [
        (StatusPreset?.some(.atWork), String?.some("At the office")),
        (nil, nil),
        (nil, "    "),
    ])
    func notExactlyOneIsInvalid(_ preset: StatusPreset?, _ text: String?) {
        #expect(throws: ActivityError.invalidStatus) {
            try StatusInput.validated(preset: preset, text: text, expiresAt: nil, now: now)
        }
    }

    @Test func thirtyCharactersIsTheLimit() throws {
        let thirty = String(repeating: "a", count: 30)
        #expect(try StatusInput.validated(preset: nil, text: thirty, expiresAt: nil, now: now).text == thirty)
        #expect(throws: ActivityError.invalidStatus) {
            try StatusInput.validated(preset: nil, text: thirty + "b", expiresAt: nil, now: now)
        }
    }

    @Test func lengthIsCountedLikeTheServer() throws {
        // An emoji is 2 UTF-16 units, as JavaScript's `.length` counts it.
        #expect(StatusInput.length(of: "😄") == 2)
        let fifteen = String(repeating: "😄", count: 15)
        #expect(try StatusInput.validated(preset: nil, text: fifteen, expiresAt: nil, now: now).text == fifteen)
        #expect(throws: ActivityError.invalidStatus) {
            try StatusInput.validated(preset: nil, text: fifteen + "😄", expiresAt: nil, now: now)
        }
    }

    @Test func clampingKeepsWholeCharacters() {
        #expect(StatusInput.clamped(String(repeating: "a", count: 40)).count == 30)
        // 29 letters + an emoji would be 31 units, so the emoji is dropped whole.
        let clamped = StatusInput.clamped(String(repeating: "a", count: 29) + "😄")
        #expect(clamped == String(repeating: "a", count: 29))
        #expect(StatusInput.clamped("नमस्ते") == "नमस्ते")
    }

    @Test func expiryMustBeInTheFutureAndWithinSevenDays() throws {
        let week = now.addingTimeInterval(7 * 24 * 3600)
        let ok = try StatusInput.validated(preset: .atHome, text: nil, expiresAt: week, now: now)
        #expect(ok.expiresAt == ActivityTime.millis(week))
        for bad in [now, now.addingTimeInterval(-60), week.addingTimeInterval(1)] {
            #expect(throws: ActivityError.invalidExpiry) {
                try StatusInput.validated(preset: .atHome, text: nil, expiresAt: bad, now: now)
            }
        }
    }

    @Test func encodesOnlyTheFieldsThatAreSet() throws {
        let json = try JSONEncoder().encode(StatusInput(preset: .onAHike, text: nil, expiresAt: nil))
        #expect(String(decoding: json, as: UTF8.self) == #"{"preset":"on_a_hike"}"#)
    }

    @Test func presetKeysMatchTheContract() {
        #expect(StatusPreset.allCases.map(\.rawValue) == [
            "at_work", "at_home", "commuting", "working_out", "on_a_hike", "resting", "travelling",
        ])
        #expect(StatusPreset.allCases.map(\.label) == [
            "At work", "At home", "Commuting", "Working out", "On a hike", "Resting", "Travelling",
        ])
    }

    @Test func expiredStatusShowsNothing() {
        let status = MemberStatus(preset: .atWork, expiresAt: ActivityTime.millis(now))
        #expect(!status.isActive(at: now))
        #expect(status.isActive(at: now.addingTimeInterval(-1)))
    }
}

struct StatusExpiryTests {
    var calendar: Calendar = ActivityTime.nepalCalendar

    @Test func choicesFromMorning() throws {
        let now = activityTestNow
        #expect(StatusExpiry.default == .day)
        #expect(StatusExpiry.day.expiry(from: now, calendar: calendar) == now.addingTimeInterval(24 * 3600))
        #expect(StatusExpiry.oneHour.expiry(from: now, calendar: calendar) == now.addingTimeInterval(3600))
        #expect(StatusExpiry.fourHours.expiry(from: now, calendar: calendar) == now.addingTimeInterval(4 * 3600))
        let tonight = try #require(StatusExpiry.tonight.expiry(from: now, calendar: calendar))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: tonight) == DateComponents(day: 14, hour: 21, minute: 0))
        #expect(StatusExpiry.available(at: now, calendar: calendar) == StatusExpiry.allCases)
    }

    @Test func tonightIsHiddenFromNineOnwards() {
        let nine = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: activityTestNow)!
        #expect(StatusExpiry.tonight.expiry(from: nine, calendar: calendar) == nil)
        #expect(!StatusExpiry.available(at: nine.addingTimeInterval(60), calendar: calendar).contains(.tonight))
        #expect(StatusExpiry.available(at: nine.addingTimeInterval(-60), calendar: calendar).contains(.tonight))
    }
}

struct FeedEventTextTests {
    let mum = FeedActor(userId: "u-mum", name: "Mum")
    let us = Locale(identifier: "en_US")

    private func event(_ type: FeedEventType, _ actor: FeedActor?) -> FeedEvent {
        FeedEvent(id: "e", type: type, actor: actor, day: "2026-11-14", createdAt: 0)
    }

    @Test func eachTypeInPlainWords() {
        #expect(event(.member5k, mum).text(viewerId: "me", locale: us) == "Mum passed 5,000 steps")
        #expect(event(.member10k, mum).text(viewerId: "me", locale: us) == "Mum passed 10,000 steps")
        #expect(event(.family50, nil).text(viewerId: "me", locale: us) == "The family is halfway to today's goal!")
        #expect(event(.family100, nil).text(viewerId: "me", locale: us) == "The family reached today's goal!")
        #expect(event(.walkStarted, mum).text(viewerId: "me", locale: us) == "Mum started a walk")
    }

    @Test func myOwnEventsSayYou() {
        #expect(event(.member5k, mum).text(viewerId: "u-mum", locale: us) == "You passed 5,000 steps")
        #expect(event(.member10k, mum).text(viewerId: "u-mum", locale: us) == "You passed 10,000 steps")
        #expect(event(.walkStarted, mum).text(viewerId: "u-mum", locale: us) == "You started a walk")
    }

    @Test func missingActorAndUnknownType() {
        #expect(event(.member5k, nil).text(viewerId: nil, locale: us) == "Someone passed 5,000 steps")
        #expect(event(.unknown, mum).text(viewerId: nil) == "")
        #expect(!event(.unknown, mum).isDisplayable)
        #expect(event(.family100, nil).isDisplayable)
    }

    @Test func decodesTheContractShape() throws {
        let json = """
        [{"id":"k1","type":"walk_started","actor":{"userId":"u1","name":"Ram","avatarColor":"#3BB273"},
          "day":"2026-11-14","createdAt":1794638100000,"data":{"walkId":"w1"},
          "reactions":[{"emoji":"👏","count":2},{"emoji":"\u{2764}","count":1},{"emoji":"🦄","count":5}],
          "myReaction":"\u{2764}"},
         {"id":"k2","type":"family_100","actor":null,"day":"2026-11-14","createdAt":1794638000000,
          "data":{},"reactions":[],"myReaction":null},
         {"id":"k3","type":"member_25k","actor":null,"day":"2026-11-14","createdAt":1,"data":{},"reactions":[],"myReaction":null}]
        """
        let events = try JSONDecoder().decode([FeedEvent].self, from: Data(json.utf8))
        #expect(events.count == 3)
        #expect(events[0].type == .walkStarted)
        #expect(events[0].data?.walkId == "w1")
        #expect(events[0].reactions == [ReactionCount(emoji: .clap, count: 2), ReactionCount(emoji: .heart, count: 1)])
        #expect(events[0].myReaction == .heart)
        #expect(events[1].actor == nil)
        #expect(events[1].myReaction == nil)
        #expect(events[2].type == .unknown)
    }
}

struct ReactionLogicTests {
    let base = FeedEvent(
        id: "e", type: .member5k, actor: nil, day: "2026-11-14", createdAt: 0,
        reactions: [ReactionCount(emoji: .clap, count: 2), ReactionCount(emoji: .fire, count: 1)]
    )

    @Test func theFixedFiveInOrder() {
        #expect(Reaction.allCases.map(\.rawValue) == ["👏", "❤️", "🙌", "🔥", "😄"])
    }

    @Test func addThenRemoveWithTheSameEmoji() {
        let added = base.reacting(with: .heart)
        #expect(added.myReaction == .heart)
        #expect(added.count(for: .heart) == 1)
        #expect(added.reactions.map(\.emoji) == [.clap, .heart, .fire])
        let removed = added.reacting(with: .heart)
        #expect(removed.myReaction == nil)
        #expect(removed.reactions == base.reactions)
    }

    @Test func aDifferentEmojiReplaces() {
        let replaced = base.reacting(with: .fire).reacting(with: .clap)
        #expect(replaced.myReaction == .clap)
        #expect(replaced.count(for: .clap) == 3)
        #expect(replaced.count(for: .fire) == 1)
    }

    @Test func zeroCountsAreDropped() {
        let mine = FeedEvent(id: "e", type: .family50, actor: nil, day: "d", createdAt: 0,
                             reactions: [ReactionCount(emoji: .laugh, count: 1)], myReaction: .laugh)
        let swapped = mine.reacting(with: .raisedHands)
        #expect(swapped.reactions == [ReactionCount(emoji: .raisedHands, count: 1)])
    }
}

struct NotificationPrefsTests {
    @Test func defaultsMatchTheContract() {
        #expect(NotificationPrefs.defaults == NotificationPrefs(walkStarted: true, goalHit: true, reactions: true, eveningNudge: false))
    }

    @Test func patchSendsOnlyOneField() throws {
        let json = try JSONEncoder().encode(NotificationPrefsPatch(.eveningNudge, true))
        #expect(String(decoding: json, as: UTF8.self) == #"{"eveningNudge":true}"#)
        #expect(NotificationPrefs.defaults.applying(NotificationPrefsPatch(.walkStarted, false)).walkStarted == false)
    }

    @Test func subscriptCoversEveryKind() {
        var prefs = NotificationPrefs.defaults
        for kind in NotificationKind.allCases { prefs[kind] = false }
        #expect(prefs == NotificationPrefs(walkStarted: false, goalHit: false, reactions: false, eveningNudge: false))
    }
}

struct ActivityStyleTests {
    @Test func galleryLaunchArgument() {
        #expect(ActivityGalleryLaunch.parse(["app"]) == nil)
        #expect(ActivityGalleryLaunch.parse(["app", "-activityGallery"])?.page == nil)
        #expect(ActivityGalleryLaunch.parse(["app", "-activityGallery", "feed"])?.page == .feed)
        #expect(ActivityGalleryLaunch.parse(["app", "-activityGallery", "-mockSteps"])?.page == nil)
    }
}
