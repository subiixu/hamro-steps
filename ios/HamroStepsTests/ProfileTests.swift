import Foundation
import Testing
import UIKit
@testable import HamroSteps

/// Collapses the narrow/no-break spaces some locales put before "pm".
private func plain(_ text: String?) -> String? {
    text?.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

private let australia = Locale(identifier: "en_AU")
/// 15 Nov 2026, 10:41 UTC: 9:41 pm in Sydney (AEDT), 4:26 pm in Kathmandu.
private let instant = Date(timeIntervalSince1970: 1_794_739_260)

struct BirthdayFormatTests {
    @Test func showsDayAndMonthWithoutTheYear() {
        #expect(ProfileFormat.birthday("1990-03-12", locale: australia) == "12 March")
        #expect(ProfileFormat.birthday("1962-08-24", locale: Locale(identifier: "en_US")) == "August 24")
        #expect(ProfileFormat.birthday("1990-03-12", locale: australia)?.contains("1990") == false)
    }

    @Test func sameDayInEveryTimeZone() {
        // Stored as a calendar day, so a phone far from GMT doesn't shift it.
        let date = ProfileFormat.pickerDate(forBirthday: "1990-03-12", in: TestTime.calendar("Pacific/Kiritimati"))!
        #expect(ProfileFormat.birthdayString(from: date, in: TestTime.calendar("Pacific/Kiritimati")) == "1990-03-12")
        let la = ProfileFormat.pickerDate(forBirthday: "1990-01-01", in: TestTime.calendar("America/Los_Angeles"))!
        #expect(ProfileFormat.birthdayString(from: la, in: TestTime.calendar("America/Los_Angeles")) == "1990-01-01")
    }

    @Test func birthdayCalendarIsGregorianInThePhonesZone() {
        let calendar = ProfileFormat.birthdayCalendar()
        #expect(calendar.identifier == .gregorian)
        #expect(calendar.timeZone == .current)
        // The defaults round-trip whatever calendar the phone is set to.
        let date = ProfileFormat.pickerDate(forBirthday: "1990-03-12")!
        #expect(ProfileFormat.birthdayString(from: date) == "1990-03-12")
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .japanese])
    func phoneCalendarDoesNotChangeTheYear(_ phoneCalendar: Calendar.Identifier) {
        // A phone set to Buddhist or Japanese still stores 1990: the picker
        // runs in `birthdayCalendar()`, and the phone's own calendar would not.
        var phone = Calendar(identifier: phoneCalendar)
        phone.timeZone = .current
        let date = ProfileFormat.pickerDate(forBirthday: "1990-03-12")!
        #expect(ProfileFormat.birthdayString(from: date) == "1990-03-12")
        #expect(ProfileFormat.birthdayString(from: date, in: phone) != "1990-03-12")
        #expect(ProfileFormat.birthday(ProfileFormat.birthdayString(from: date), locale: australia) == "12 March")
    }

    @Test(arguments: ["2025-02-30", "1990-3-12", "12-03-1990", "", "abcd-ef-gh", "1990-13-01"])
    func unreadableIsNil(_ text: String) {
        #expect(ProfileFormat.birthday(text, locale: australia) == nil)
    }

    @Test func validBirthdays() {
        let sydney = TestTime.calendar("Australia/Sydney")
        #expect(ProfileFormat.isValidBirthday("1990-03-12", today: instant, in: sydney))
        #expect(ProfileFormat.isValidBirthday("1900-01-01", today: instant, in: sydney))
        // Today counts; tomorrow and 1899 don't.
        #expect(ProfileFormat.isValidBirthday("2026-11-15", today: instant, in: sydney))
        #expect(!ProfileFormat.isValidBirthday("2026-11-16", today: instant, in: sydney))
        #expect(!ProfileFormat.isValidBirthday("1899-12-31", today: instant, in: sydney))
        #expect(!ProfileFormat.isValidBirthday("2023-02-29", today: instant, in: sydney))
    }
}

struct LocalTimeTests {
    @Test func timeInTheirZone() {
        #expect(plain(ProfileFormat.localTime(timezone: "Australia/Sydney", now: instant, locale: australia)) == "9:41 pm")
        #expect(plain(ProfileFormat.localTime(timezone: "Asia/Kathmandu", now: instant, locale: australia)) == "4:26 pm")
    }

    @Test func cityAndTime() {
        #expect(plain(ProfileFormat.placeLine(city: "Sydney", timezone: "Australia/Sydney", now: instant, locale: australia)) == "Sydney · 9:41 pm")
        #expect(plain(ProfileFormat.placeLine(city: "  Sydney ", timezone: "Australia/Sydney", now: instant, locale: australia)) == "Sydney · 9:41 pm")
    }

    @Test(arguments: [nil, "", "Not/AZone"] as [String?])
    func unknownZoneShowsCityOnly(_ zone: String?) {
        #expect(ProfileFormat.localTime(timezone: zone, now: instant, locale: australia) == nil)
        #expect(ProfileFormat.placeLine(city: "Sydney", timezone: zone, now: instant, locale: australia) == "Sydney")
    }

    @Test func noCity() {
        #expect(ProfileFormat.placeLine(city: nil, timezone: nil, now: instant, locale: australia) == nil)
        #expect(ProfileFormat.placeLine(city: "   ", timezone: "Bad/Zone", now: instant, locale: australia) == nil)
        #expect(plain(ProfileFormat.placeLine(city: "", timezone: "Australia/Sydney", now: instant, locale: australia))?.contains("9:41 pm") == true)
    }
}

struct ProfilePhotoTests {
    private func image(width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func sizes() {
        #expect(ProfilePhoto.scaledSize(for: CGSize(width: 4032, height: 3024)) == CGSize(width: 512, height: 384))
        #expect(ProfilePhoto.scaledSize(for: CGSize(width: 3024, height: 4032)) == CGSize(width: 384, height: 512))
        #expect(ProfilePhoto.scaledSize(for: CGSize(width: 300, height: 200)) == CGSize(width: 300, height: 200))
        #expect(ProfilePhoto.scaledSize(for: CGSize(width: 9999, height: 1)).width <= 512)
    }

    @Test(arguments: [(2000.0, 1000.0, 1.0), (1000.0, 1500.0, 3.0), (512.0, 512.0, 1.0), (120.0, 80.0, 2.0)])
    func jpegStaysWithin512(_ width: Double, _ height: Double, _ scale: Double) throws {
        let jpeg = try #require(ProfilePhoto.jpeg(from: image(width: width, height: height, scale: scale)))
        let decoded = try #require(UIImage(data: jpeg))
        let pixels = CGSize(width: decoded.size.width * decoded.scale, height: decoded.size.height * decoded.scale)
        #expect(max(pixels.width, pixels.height) <= 512)
        #expect(max(pixels.width, pixels.height) >= min(512, max(width, height) * scale) - 1)
    }

    @Test func veryNarrowPhotoKeepsAPixel() throws {
        #expect(ProfilePhoto.scaledSize(for: CGSize(width: 9999, height: 1)) == CGSize(width: 512, height: 1))
        #expect(ProfilePhoto.scaledSize(for: CGSize(width: 1, height: 9999)) == CGSize(width: 1, height: 512))
        let jpeg = try #require(ProfilePhoto.jpeg(from: image(width: 9999, height: 1)))
        let decoded = try #require(UIImage(data: jpeg))
        #expect(decoded.size.width * decoded.scale == 512)
        #expect(decoded.size.height * decoded.scale >= 1)
    }

    @Test func emptyImageIsNil() {
        #expect(ProfilePhoto.downscaled(UIImage()) == nil)
        #expect(ProfilePhoto.jpeg(from: UIImage()) == nil)
    }

    @Test func unreadableDataIsNil() {
        #expect(ProfilePhoto.jpeg(from: Data("not a photo".utf8)) == nil)
    }
}

struct MockProfileTests {
    private func signedIn() -> (MockFamilyService, MockAuthService) {
        let backend = MockFamilyService.sample(signedIn: true)
        return (backend, MockAuthService(backend: backend, defaults: nil))
    }

    private func me(in backend: MockFamilyService) async throws -> FamilyMember {
        try #require(try await backend.familyToday(familyId: "f_thapa").members.first { $0.userId == MockFamilyService.sampleUserId })
    }

    @Test func cityAndBirthdayRoundTrip() async throws {
        let (backend, auth) = signedIn()
        let user = try await auth.updateProfile(ProfileUpdate(name: " Priya ", city: "  Brisbane ", birthday: "1988-07-04"))
        #expect(user.name == "Priya")
        #expect(user.city == "Brisbane")
        #expect(user.birthday == "1988-07-04")
        let member = try await me(in: backend)
        #expect(member.city == "Brisbane")
        #expect(member.birthday == "1988-07-04")
        #expect(member.timezone == "Australia/Sydney")

        let cleared = try await auth.updateProfile(ProfileUpdate(name: "Priya", city: "", birthday: nil))
        #expect(cleared.city == nil)
        #expect(cleared.birthday == nil)
        #expect(try await me(in: backend).city == nil)
    }

    @Test func rejectsBadValuesWithTheirOwnErrors() async throws {
        let (_, auth) = signedIn()
        await #expect(throws: FamilyServiceError.invalidCity) {
            try await auth.updateProfile(ProfileUpdate(name: "Priya", city: String(repeating: "a", count: 41), birthday: nil))
        }
        await #expect(throws: FamilyServiceError.invalidBirthday) {
            try await auth.updateProfile(ProfileUpdate(name: "Priya", city: "", birthday: "2999-01-01"))
        }
        await #expect(throws: FamilyServiceError.invalidBirthday) {
            try await auth.updateProfile(ProfileUpdate(name: "Priya", city: "", birthday: "1990-02-30"))
        }
        await #expect(throws: FamilyServiceError.invalidPhoto) {
            try await auth.setPhoto(jpeg: Data("nope".utf8), userId: MockFamilyService.sampleUserId)
        }
    }

    @Test func photoRoundTrip() async throws {
        let (backend, auth) = signedIn()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600), format: format).image { _ in }
        let jpeg = try #require(ProfilePhoto.jpeg(from: picture))

        let user = try await auth.setPhoto(jpeg: jpeg, userId: MockFamilyService.sampleUserId)
        let address = try #require(user.photoUrl)
        let url = try #require(URL(string: address))
        #expect(FileManager.default.contents(atPath: url.path()) == jpeg)
        #expect(try await me(in: backend).photoUrl == address)

        let removed = try await auth.removePhoto(userId: MockFamilyService.sampleUserId)
        #expect(removed.photoUrl == nil)
        #expect(try await me(in: backend).photoUrl == nil)
    }

    @Test func sampleFamilyHasProfiles() async throws {
        let backend = MockFamilyService.sample(signedIn: true)
        let members = try await backend.familyToday(familyId: "f_thapa").members
        let aama = try #require(members.first { $0.userId == "u_aama" })
        #expect(aama.city == "Kathmandu")
        #expect(aama.birthday == "1962-08-24")
        #expect(aama.timezone == "Asia/Kathmandu")
        #expect(aama.photoUrl != nil)
    }
}

struct ProfileDecodingTests {
    @Test func memberWithProfile() throws {
        let json = """
        {"userId":"u1","name":"Aama","avatarColor":"#2C9A76","position":0,"isOrganiser":false,"steps":null,"lastSyncedAt":null,"status":null,
         "photoUrl":"https://example.com/p.jpg","city":"Kathmandu","timezone":"Asia/Kathmandu","birthday":"1962-08-24"}
        """
        let member = try JSONDecoder().decode(FamilyMember.self, from: Data(json.utf8))
        #expect(member.photoUrl == "https://example.com/p.jpg")
        #expect(member.city == "Kathmandu")
        #expect(member.timezone == "Asia/Kathmandu")
        #expect(member.birthday == "1962-08-24")
    }

    @Test func olderShapesStillDecode() throws {
        let member = try JSONDecoder().decode(FamilyMember.self, from: Data("""
        {"userId":"u1","name":null,"avatarColor":"#2C9A76","position":0,"isOrganiser":false}
        """.utf8))
        #expect(member.photoUrl == nil && member.city == nil && member.timezone == nil && member.birthday == nil)
        let actor = try JSONDecoder().decode(FeedActor.self, from: Data("""
        {"userId":"u1","name":"Ram","avatarColor":"#3BB273","photoUrl":null,"city":"Pokhara","timezone":null}
        """.utf8))
        #expect(actor == FeedActor(userId: "u1", name: "Ram", city: "Pokhara"))
    }

    @Test func meWithProfile() throws {
        let user = try JSONDecoder().decode(AppUser.self, from: Data("""
        {"userId":"user_1","name":"Sita","needsName":false,"avatarColor":"#E07A5F","timezone":"Asia/Kathmandu","lastSyncedAt":null,
         "photoUrl":"https://example.com/s.jpg","city":"Pokhara","birthday":null}
        """.utf8))
        #expect(user == AppUser(userId: "user_1", name: "Sita", needsName: false, timezone: "Asia/Kathmandu",
                                photoUrl: "https://example.com/s.jpg", city: "Pokhara", birthday: nil))
    }

    @Test(arguments: [("invalid_photo", FamilyServiceError.invalidPhoto), ("invalid_city", .invalidCity), ("invalid_birthday", .invalidBirthday)])
    func profileErrorCodes(_ code: String, _ error: FamilyServiceError) {
        #expect(FamilyServiceError(code: code) == error)
        #expect(error.code == code)
        #expect(!error.message.isEmpty)
        #expect(error.message != FamilyServiceError.unavailable("").message)
    }

    @Test func uploadAnswer() throws {
        #expect(try URLSessionPhotoUploader.storageId(from: Data(#"{"storageId":"kg2abc"}"#.utf8)) == "kg2abc")
        #expect(throws: FamilyServiceError.unavailable("upload_failed")) {
            try URLSessionPhotoUploader.storageId(from: Data("<html>".utf8))
        }
    }
}

/// Records uploads instead of sending them.
final class FakePhotoUploader: PhotoUploading, @unchecked Sendable {
    private let lock = NSLock()
    private var _uploads: [(Data, URL)] = []
    var uploads: [(Data, URL)] { lock.withLock { _uploads } }
    /// When set, each upload waits here after it's recorded.
    private let gate: TestGate?

    init(gate: TestGate? = nil) { self.gate = gate }

    func upload(_ jpeg: Data, to url: URL) async throws -> String {
        lock.withLock { _uploads.append((jpeg, url)) }
        await gate?.wait()
        return "kg_storage_1"
    }
}

struct ConvexProfileTests {
    private func auth(_ h: ConvexHarness, uploader: FakePhotoUploader = FakePhotoUploader()) -> ConvexAuthService {
        ConvexAuthService(connection: ConvexConnection(transport: h.transport, session: h.session), uploader: uploader)
    }

    @Test func updateProfileSendsEverythingThenReadsMe() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("users:updateProfile", json: "null")
        h.transport.respond("users:me", json: Fixtures.me())
        _ = try await auth(h).updateProfile(ProfileUpdate(name: " Sita ", city: " Pokhara ", birthday: nil))
        #expect(h.transport.calls.contains(.init(kind: "mutation", name: "users:updateProfile", args: [
            "name": .string("Sita"), "city": .string("Pokhara"), "birthday": .null,
        ])))

        h.transport.respond("users:updateProfile", json: "null")
        h.transport.respond("users:me", json: Fixtures.me())
        _ = try await auth(h).updateProfile(ProfileUpdate(name: "Sita", city: "", birthday: "1990-03-12"))
        #expect(h.transport.calls.contains(.init(kind: "mutation", name: "users:updateProfile", args: [
            "name": .string("Sita"), "city": .string(""), "birthday": .string("1990-03-12"),
        ])))
    }

    @Test func setPhotoUploadsThenSetsAvatar() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        let uploader = FakePhotoUploader()
        h.transport.respond("users:generateAvatarUploadUrl", json: #""https://upload.example/abc""#)
        h.transport.respond("users:setAvatar", json: "null")
        h.transport.respond("users:me", json: Fixtures.me())
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        _ = try await auth(h, uploader: uploader).setPhoto(jpeg: jpeg, userId: "user_1")
        #expect(uploader.uploads.count == 1)
        #expect(uploader.uploads.first?.0 == jpeg)
        #expect(uploader.uploads.first?.1 == URL(string: "https://upload.example/abc"))
        #expect(h.transport.calls.contains(.init(kind: "mutation", name: "users:setAvatar", args: [
            "storageId": .string("kg_storage_1"), "userId": .string("user_1"),
        ])))
    }

    @Test func rejectedPhotoComesBackGently() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("users:generateAvatarUploadUrl", json: #""https://upload.example/abc""#)
        h.transport.fail("users:setAvatar", .convex(code: "invalid_photo"))
        await #expect(throws: FamilyServiceError.invalidPhoto) {
            try await auth(h).setPhoto(jpeg: Data([1]), userId: "user_1")
        }
    }

    @Test func photoFromAnEndedSessionIsNotSet() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        let gate = TestGate()
        let uploader = FakePhotoUploader(gate: gate)
        let service = auth(h, uploader: uploader)
        h.transport.respond("users:generateAvatarUploadUrl", json: #""https://upload.example/abc""#)
        let upload = Task { try await service.setPhoto(jpeg: Data([0xFF, 0xD8]), userId: "user_1") }
        try await waitFor { await gate.waiting == 1 }

        // Sign out and back in while the photo is still uploading.
        await h.auth.signOut()
        try await h.signIn(name: "Rohan")
        await gate.open()

        await #expect(throws: CancellationError.self) { try await upload.value }
        #expect(!h.transport.calls.contains { $0.name == "users:setAvatar" })
    }

    @Test func photoAfterSignOutIsNotSet() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        let gate = TestGate()
        let service = auth(h, uploader: FakePhotoUploader(gate: gate))
        h.transport.respond("users:generateAvatarUploadUrl", json: #""https://upload.example/abc""#)
        let upload = Task { try await service.setPhoto(jpeg: Data([0xFF, 0xD8]), userId: "user_1") }
        try await waitFor { await gate.waiting == 1 }

        await h.auth.signOut()
        await gate.open()

        await #expect(throws: CancellationError.self) { try await upload.value }
        #expect(!h.transport.calls.contains { $0.name == "users:setAvatar" })
    }

    /// The server refuses a photo change sent with another account's token
    /// (e.g. an auth retry that ran as the next account): no notice.
    @Test func serverRefusalForAnotherAccountIsACancellation() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("users:generateAvatarUploadUrl", json: #""https://upload.example/abc""#)
        h.transport.fail("users:setAvatar", .convex(code: "not_authorized"))
        await #expect(throws: CancellationError.self) {
            try await auth(h).setPhoto(jpeg: Data([1]), userId: "user_1")
        }
        h.transport.fail("users:removeAvatar", .convex(code: "not_authorized"))
        await #expect(throws: CancellationError.self) {
            try await auth(h).removePhoto(userId: "user_1")
        }
    }

    @Test func photoForAnotherAccountIsNeverSent() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        await #expect(throws: CancellationError.self) {
            try await auth(h).setPhoto(jpeg: Data([1]), userId: "user_someone_else")
        }
        await #expect(throws: CancellationError.self) {
            try await auth(h).removePhoto(userId: "user_someone_else")
        }
        #expect(!h.transport.calls.contains { $0.name.hasPrefix("users:generateAvatarUploadUrl") || $0.name.hasSuffix("Avatar") })
    }

    @Test func removePhotoAndTimeZone() async throws {
        let h = await ConvexHarness()
        try await h.signIn()
        h.transport.respond("users:removeAvatar", json: "null")
        h.transport.respond("users:me", json: Fixtures.me())
        _ = try await auth(h).removePhoto(userId: "user_1")
        #expect(h.transport.calls.contains(.init(kind: "mutation", name: "users:removeAvatar", args: ["userId": .string("user_1")])))

        h.transport.respond("users:updateProfile", json: "null")
        h.transport.respond("users:me", json: Fixtures.me())
        try await auth(h).updateTimeZone("Australia/Sydney")
        #expect(h.transport.calls.contains(.init(kind: "mutation", name: "users:updateProfile", args: ["timezone": .string("Australia/Sydney")])))
    }
}

@MainActor
struct TimeZoneSyncTests {
    @Test func storesANewZoneOnceAndSkipsTheSameOne() async throws {
        let auth = StubAuthService(user: AppUser(userId: "u1", name: "Priya", needsName: false, timezone: "Asia/Kathmandu"))
        let session = SessionStore(auth: auth, service: StubFamilyService(), defaults: TestTime.defaults())
        await session.start()

        await session.syncTimeZone("Asia/Kathmandu")
        #expect(await auth.calls.isEmpty)

        await session.syncTimeZone("Australia/Sydney")
        #expect(await auth.calls == ["updateTimeZone Australia/Sydney"])
        #expect(session.user?.timezone == "Australia/Sydney")

        await session.syncTimeZone("Australia/Sydney")
        #expect(await auth.calls.count == 1)
    }

    @Test func photoFinishingAfterAnAccountChangeIsDropped() async throws {
        let gate = TestGate()
        let first = AppUser(userId: "u1", name: "Priya", needsName: false)
        let auth = StubAuthService(user: first, photoGate: gate)
        let session = SessionStore(auth: auth, service: StubFamilyService(), defaults: TestTime.defaults())
        await session.start()

        let upload = Task { try await session.setPhoto(jpeg: Data([1]), userId: "u1") }
        try await waitFor { await gate.waiting == 1 }
        await session.signOut()
        await auth.setUser(AppUser(userId: "u2", name: "Rohan", needsName: false))
        try await session.signIn(identityToken: "t", authorizationCode: "c", fullName: nil)
        await gate.open()

        await #expect(throws: CancellationError.self) { try await upload.value }
        #expect(session.user?.id == "u2")
    }

    @Test func photoFinishingAfterSignOutLeavesItSignedOut() async throws {
        let gate = TestGate()
        let auth = StubAuthService(user: AppUser(userId: "u1", name: "Priya", needsName: false), photoGate: gate)
        let session = SessionStore(auth: auth, service: StubFamilyService(), defaults: TestTime.defaults())
        await session.start()

        let upload = Task { try await session.setPhoto(jpeg: Data([1]), userId: "u1") }
        try await waitFor { await gate.waiting == 1 }
        await session.signOut()
        await gate.open()

        await #expect(throws: CancellationError.self) { try await upload.value }
        #expect(session.user == nil)
    }

    /// Mirrors the edit screen: the account is noted when the photo action
    /// starts, then the picker load pauses while A signs out and B signs in.
    @Test func photoPickedAsOneAccountIsNotSentForTheNext() async throws {
        let load = TestGate()
        let auth = StubAuthService(user: AppUser(userId: "u1", name: "Priya", needsName: false))
        let session = SessionStore(auth: auth, service: StubFamilyService(), defaults: TestTime.defaults())
        await session.start()

        let startedAs = try #require(session.user?.id)
        let upload = Task {
            await load.wait() // loadTransferable + downscale
            try await session.setPhoto(jpeg: Data([1]), userId: startedAs)
        }
        try await waitFor { await load.waiting == 1 }
        await session.signOut()
        await auth.setUser(AppUser(userId: "u2", name: "Rohan", needsName: false))
        try await session.signIn(identityToken: "t", authorizationCode: "c", fullName: nil)
        await load.open()

        await #expect(throws: CancellationError.self) { try await upload.value }
        #expect(!(await auth.calls).contains { $0.hasPrefix("setPhoto") })
        await #expect(throws: CancellationError.self) { try await session.removePhoto(userId: startedAs) }
        #expect(!(await auth.calls).contains { $0.hasPrefix("removePhoto") })
        #expect(session.user?.id == "u2")
    }

    @Test func signedOutDoesNothing() async {
        let auth = StubAuthService(user: nil)
        let session = SessionStore(auth: auth, service: StubFamilyService(), defaults: TestTime.defaults())
        await session.start()
        await session.syncTimeZone("Australia/Sydney")
        #expect(await auth.calls.isEmpty)
    }
}

/// Polls until `condition` holds or 2 s pass.
private func waitFor(_ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while await !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
}
