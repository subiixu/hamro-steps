import Testing
@testable import HamroSteps

struct InviteCodeTests {
    @Test(arguments: [
        ("K7M2QX", "K7M2QX"),
        ("k7m2qx", "K7M2QX"),
        (" k7m-2qx ", "K7M2QX"),
        ("K7M 2QX", "K7M2QX"),
        ("k-7-m 2 q-x", "K7M2QX"),
        ("K7M–2QX", "K7M2QX"),
    ])
    func normalisationIgnoresCaseSpacesAndDashes(input: String, expected: String) {
        #expect(InviteCode.normalise(input) == expected)
        #expect(InviteCode.isValid(input))
    }

    @Test(arguments: ["K7M2Q", "K7M2QXX", "K7M2Q0", "IOL123", ""])
    func wrongLengthOrConfusableCharactersAreInvalid(input: String) {
        #expect(!InviteCode.isValid(input))
    }

    @Test func extractsTheCodeFromTheWholeInviteMessage() {
        let message = InviteMessage.text(familyName: "Thapa Family", code: "K7M2QX")
        #expect(message.contains("https://testflight.apple.com/join/XXXX"))
        #expect(InviteCode.extract(from: message) == "K7M2QX")
        #expect(InviteCode.extract(from: "k7m-2qx") == "K7M2QX")
        #expect(InviteCode.extract(from: "walk with us tonight please") == nil)
    }

    @Test func displayGroupsInThrees() {
        #expect(InviteCode.display("k7m2qx") == "K7M 2QX")
    }
}

/// The mock behaves like the backend for the join and organiser rules.
struct MockFamilyServiceTests {
    @Test func joinErrorsAndPreview() async throws {
        let service = MockFamilyService.sample(signedIn: true)
        await #expect(throws: FamilyServiceError.invalidCode) { try await service.joinFamily(code: "ABCDEF") }
        await #expect(throws: FamilyServiceError.familyFull) { try await service.joinFamily(code: MockFamilyService.fullFamilyCode) }

        let preview = try await service.previewInvite(code: "k7m-2qx")
        #expect(preview.name == "Thapa Family")
        #expect(preview.memberCount == 5)
        #expect(preview.alreadyMember)
        #expect(try await service.previewInvite(code: MockFamilyService.fullFamilyCode).isFull)

        // Joining a family you're in is harmless.
        #expect(try await service.joinFamily(code: "K7M2QX").familyId == "f_thapa")
    }

    @Test func organiserRules() async throws {
        let service = MockFamilyService.sample(signedIn: true)
        await #expect(throws: FamilyServiceError.cannotRemoveSelf) {
            try await service.removeMember(familyId: "f_thapa", userId: MockFamilyService.sampleUserId)
        }
        await #expect(throws: FamilyServiceError.notOrganiser) {
            try await service.removeMember(familyId: "f_cousins", userId: "u_anju")
        }
        await #expect(throws: FamilyServiceError.invalidGoal) {
            _ = try await service.updateFamily(familyId: "f_thapa", name: "Thapa Family", dailyGoal: 999)
        }
        // The organiser leaves: the next person in order takes over.
        try await service.leaveFamily(familyId: "f_thapa")
        await #expect(throws: FamilyServiceError.notMember) { try await service.familyToday(familyId: "f_thapa") }
    }

    @Test func newFamilyGreysOutEarlierDaysOfTheWeek() async throws {
        let now = TestTime.date("Asia/Kathmandu", 2026, 11, 12, 10) // Thursday
        let service = MockFamilyService.sample(signedIn: true, now: { now })
        let family = try await service.createFamily(name: "  New Family ", dailyGoal: 20_000)
        #expect(family.name == "New Family")
        #expect(family.memberCount == 1)
        let week = try await service.familyWeek(familyId: family.familyId)
        #expect(week.days.map(\.isBeforeFamily) == [true, true, true, false, false, false, false])
        #expect(week.days.map(\.isFuture) == [false, false, false, false, true, true, true])
    }
}
