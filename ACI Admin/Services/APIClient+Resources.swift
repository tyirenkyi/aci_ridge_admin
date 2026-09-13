//
//  APIClient+Resources.swift
//  ACI Admin
//
//  Typed wrappers over the endpoints. Each extension opts out of the module's
//  MainActor default separately — default isolation is applied per declaration.
//

import Foundation

// MARK: - Identity

nonisolated extension APIClient {
    func me() async throws(APIError) -> MeDTO {
        try await send(Endpoint(.get, "/api/me"))
    }
}

// MARK: - Notices

nonisolated extension APIClient {
    func notices(status: String?, limit: Int) async throws(APIError) -> [NoticeDTO] {
        var query = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 500)))]
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        return try await send(Endpoint(.get, "/api/notices", query: query))
    }

    func notice(_ id: String) async throws(APIError) -> NoticeDTO {
        try await send(Endpoint(.get, "/api/notices/\(id)"))
    }

    func createNotice(_ body: NoticeBody) async throws(APIError) -> NoticeDTO {
        try await send(Endpoint(.post, "/api/notices", body: body))
    }

    func updateNotice(_ id: String, _ patch: PatchBody) async throws(APIError) -> NoticeDTO {
        try await send(Endpoint(.patch, "/api/notices/\(id)", body: patch))
    }

    func deleteNotice(_ id: String) async throws(APIError) {
        try await send(Endpoint(.delete, "/api/notices/\(id)"))
    }

    func sendNotice(_ id: String) async throws(APIError) -> SendResultDTO {
        try await send(Endpoint(.post, "/api/notices/\(id)/send"))
    }
}

// MARK: - Recurring rules

nonisolated extension APIClient {
    func rules() async throws(APIError) -> [RuleDTO] {
        try await send(Endpoint(.get, "/api/rules"))
    }

    func rule(_ id: String) async throws(APIError) -> RuleDTO {
        try await send(Endpoint(.get, "/api/rules/\(id)"))
    }

    func createRule(_ body: RuleBody) async throws(APIError) -> RuleDTO {
        try await send(Endpoint(.post, "/api/rules", body: body))
    }

    func updateRule(_ id: String, _ patch: RulePatch) async throws(APIError) -> RuleDTO {
        try await send(Endpoint(.patch, "/api/rules/\(id)", body: patch))
    }

    func deleteRule(_ id: String) async throws(APIError) {
        try await send(Endpoint(.delete, "/api/rules/\(id)"))
    }

    func occurrences(_ id: String, count: Int) async throws(APIError) -> OccurrencesDTO {
        let query = [URLQueryItem(name: "count", value: String(min(max(count, 1), 31)))]
        return try await send(Endpoint(.get, "/api/rules/\(id)/occurrences", query: query))
    }

    func addSkip(_ id: String, day: CalendarDay) async throws(APIError) {
        let _: SkipDTO = try await send(
            Endpoint(.post, "/api/rules/\(id)/skips", body: SkipBody(date: day.iso))
        )
    }

    func removeSkip(_ id: String, day: CalendarDay) async throws(APIError) {
        try await send(Endpoint(.delete, "/api/rules/\(id)/skips/\(day.iso)"))
    }
}

// MARK: - Events

nonisolated extension APIClient {
    /// Always the admin listing: drafts and expired events included.
    func events() async throws(APIError) -> [EventDTO] {
        try await send(Endpoint(.get, "/api/events", query: [URLQueryItem(name: "all", value: "true")]))
    }

    func createEvent(_ body: EventBody) async throws(APIError) -> EventDTO {
        try await send(Endpoint(.post, "/api/events", body: body))
    }

    func updateEvent(_ id: String, _ patch: PatchBody) async throws(APIError) -> EventDTO {
        try await send(Endpoint(.patch, "/api/events/\(id)", body: patch))
    }

    func deleteEvent(_ id: String) async throws(APIError) {
        try await send(Endpoint(.delete, "/api/events/\(id)"))
    }
}
