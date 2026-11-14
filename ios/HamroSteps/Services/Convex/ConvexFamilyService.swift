import Foundation

/// `FamilyService` against the Convex backend (`convex/families.ts`,
/// `steps.ts`, `home.ts`, `users.ts`). Methods throw `FamilyServiceError`.
struct ConvexFamilyService: FamilyService {
    let connection: ConvexConnection

    func createFamily(name: String, dailyGoal: Int) async throws -> FamilySummary {
        try await mutation("families:createFamily", ["name": .string(name), "dailyGoal": .int(dailyGoal)])
    }

    func previewInvite(code: String) async throws -> InvitePreview {
        try await query("families:previewInvite", ["code": .string(code)])
    }

    func joinFamily(code: String) async throws -> FamilySummary {
        try await mutation("families:joinFamily", ["code": .string(code)])
    }

    func regenerateInviteCode(familyId: String) async throws -> String {
        struct Result: Decodable, Sendable { let inviteCode: String }
        let result: Result = try await mutation("families:regenerateInviteCode", ["familyId": .string(familyId)])
        return result.inviteCode
    }

    func removeMember(familyId: String, userId: String) async throws {
        let _: ConvexNull = try await mutation("families:removeMember", ["familyId": .string(familyId), "userId": .string(userId)])
    }

    func updateFamily(familyId: String, name: String, dailyGoal: Int) async throws -> FamilySummary {
        try await mutation("families:updateFamily", [
            "familyId": .string(familyId),
            "name": .string(name),
            "dailyGoal": .int(dailyGoal),
        ])
    }

    func leaveFamily(familyId: String) async throws {
        let _: ConvexNull = try await mutation("families:leaveFamily", ["familyId": .string(familyId)])
    }

    func myFamilies() async throws -> [FamilySummary] {
        try await query("families:myFamilies", [:])
    }

    @discardableResult
    func syncSteps(days: [StepDay]) async throws -> SyncStepsResult {
        let payload = days.map { ConvexArg.object(["day": .string($0.day), "steps": .int($0.steps)]) }
        return try await mutation("steps:syncSteps", ["days": .array(payload)])
    }

    /// `"revoked"`, `"skipped"` and `"queued"` all mean the account is gone;
    /// only a thrown error means it isn't.
    func deleteMyAccount() async throws {
        struct Result: Decodable, Sendable { let appleRevoke: String }
        let _: Result = try await connection.run { try await $0.action("users:deleteMyAccount", args: [:]) }
    }

    func familyToday(familyId: String) async throws -> FamilyToday {
        try await query("home:familyToday", ["familyId": .string(familyId)])
    }

    func familyWeek(familyId: String) async throws -> FamilyWeek {
        try await query("home:familyWeek", ["familyId": .string(familyId)])
    }

    func familyTodayUpdates(familyId: String) -> AsyncStream<FamilyToday> {
        connection.updates("home:familyToday", args: ["familyId": .string(familyId)], as: FamilyToday.self)
    }

    private func query<T: Decodable & Sendable>(_ name: String, _ args: [String: ConvexArg]) async throws -> T {
        try await connection.run { try await $0.query(name, args: args) }
    }

    private func mutation<T: Decodable & Sendable>(_ name: String, _ args: [String: ConvexArg]) async throws -> T {
        try await connection.run { try await $0.mutation(name, args: args) }
    }
}
