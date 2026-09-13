//
//  AdminAPI.swift
//  ACI Admin
//
//  The seam between the console and the server. APIClient is the real thing;
//  StubAPI backs the click-through UI test and the unit tests.
//

import Foundation

/// Requirements throw plain `Error` rather than `throws(APIError)`: a typed throw
/// does not survive being called through an existential, and every caller here goes
/// through `any AdminAPI`. AdminStore.perform normalises back to APIError in one
/// place, and the conforming types still throw APIError concretely.
nonisolated protocol AdminAPI: Sendable {
    func me() async throws -> MeDTO

    func notices(status: String?, limit: Int) async throws -> [NoticeDTO]
    func notice(_ id: String) async throws -> NoticeDTO
    func createNotice(_ body: NoticeBody) async throws -> NoticeDTO
    func updateNotice(_ id: String, _ patch: PatchBody) async throws -> NoticeDTO
    func deleteNotice(_ id: String) async throws
    func sendNotice(_ id: String) async throws -> SendResultDTO

    func rules() async throws -> [RuleDTO]
    func rule(_ id: String) async throws -> RuleDTO
    func createRule(_ body: RuleBody) async throws -> RuleDTO
    func updateRule(_ id: String, _ patch: RulePatch) async throws -> RuleDTO
    func deleteRule(_ id: String) async throws
    func occurrences(_ id: String, count: Int) async throws -> OccurrencesDTO
    func addSkip(_ id: String, day: CalendarDay) async throws
    func removeSkip(_ id: String, day: CalendarDay) async throws

    func events() async throws -> [EventDTO]
    func createEvent(_ body: EventBody) async throws -> EventDTO
    func updateEvent(_ id: String, _ patch: PatchBody) async throws -> EventDTO
    func deleteEvent(_ id: String) async throws
}

extension AdminAPI {
    func notices(status: String? = nil, limit: Int = 200) async throws -> [NoticeDTO] {
        try await notices(status: status, limit: limit)
    }

    func occurrences(_ id: String, count: Int = 10) async throws -> OccurrencesDTO {
        try await occurrences(id, count: count)
    }
}

extension APIClient: AdminAPI {}
