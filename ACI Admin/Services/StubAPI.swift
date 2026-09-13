//
//  StubAPI.swift
//  ACI Admin
//
//  An in-memory stand-in for the server, holding the same fixtures the prototype
//  shipped with. It backs the click-through UI test (which can't drive a real Sign
//  in with Apple sheet, and shouldn't depend on live data) and SwiftUI previews.
//
//  It is deliberately forgiving: it validates nothing, because its job is to let the
//  screens run, not to re-implement the API.
//

import Foundation

actor StubAPI: AdminAPI {
    private var notices: [NoticeDTO]
    private var rules: [RuleDTO]
    private var events: [EventDTO]
    private var skips: [String: Set<String>] = [:]

    init() {
        notices = SampleData.notices.map(NoticeDTO.init(stubbing:))
        rules = SampleData.recurring.map(RuleDTO.init(stubbing:))
        events = SampleData.events.map(EventDTO.init(stubbing:))
        for rule in SampleData.recurring {
            skips[rule.id] = Set(rule.skips.map(\.iso))
        }
    }

    // MARK: Identity

    func me() async throws(APIError) -> MeDTO {
        MeDTO(email: "franklin@acirid.ge", role: "owner")
    }

    // MARK: Notices

    func notices(status: String?, limit: Int) async throws(APIError) -> [NoticeDTO] {
        guard let status else { return notices }
        return notices.filter { $0.status == status }
    }

    func notice(_ id: String) async throws(APIError) -> NoticeDTO {
        guard let row = notices.first(where: { $0.id == id }) else {
            throw APIError.notFound("Notice not found")
        }
        return row
    }

    func createNotice(_ body: NoticeBody) async throws(APIError) -> NoticeDTO {
        let row = NoticeDTO(
            id: UUID().uuidString, title: body.title, message: body.message,
            sender: body.sender, status: body.status,
            scheduledAt: body.scheduledAt, sentAt: nil,
            createdAt: Date(), updatedAt: Date(), createdBy: nil, opens: 0
        )
        notices.insert(row, at: 0)
        return row
    }

    func updateNotice(_ id: String, _ patch: PatchBody) async throws(APIError) -> NoticeDTO {
        guard let index = notices.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound("Notice not found")
        }
        guard notices[index].status != "sent" else {
            throw APIError.conflict("This notice already went out and can no longer change")
        }
        let current = notices[index]
        notices[index] = NoticeDTO(
            id: current.id,
            title: patch.string("title") ?? current.title,
            message: patch.string("message") ?? current.message,
            sender: patch.string("sender") ?? current.sender,
            status: patch.string("status") ?? current.status,
            scheduledAt: patch.fields["scheduled_at"] != nil ? patch.date("scheduled_at") : current.scheduledAt,
            sentAt: current.sentAt, createdAt: current.createdAt, updatedAt: Date(),
            createdBy: current.createdBy, opens: current.opens
        )
        return notices[index]
    }

    func deleteNotice(_ id: String) async throws(APIError) {
        guard let index = notices.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound("Notice not found")
        }
        guard notices[index].status != "sent" else {
            throw APIError.conflict("Sent notices are history and can't be deleted")
        }
        notices.remove(at: index)
    }

    func sendNotice(_ id: String) async throws(APIError) -> SendResultDTO {
        guard let index = notices.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound("Notice not found")
        }
        guard notices[index].status != "sent" else {
            throw APIError.conflict("This notice was already sent")
        }
        let current = notices[index]
        notices[index] = NoticeDTO(
            id: current.id, title: current.title, message: current.message,
            sender: current.sender, status: "sent", scheduledAt: nil, sentAt: Date(),
            createdAt: current.createdAt, updatedAt: Date(), createdBy: current.createdBy, opens: 0
        )
        return SendResultDTO(
            notice: notices[index],
            push: PushDTO(apnSent: 128, apnFailed: 0, fcmSent: 64, fcmFailed: 1)
        )
    }

    // MARK: Rules

    func rules() async throws(APIError) -> [RuleDTO] {
        rules.map { withSkips($0) }
    }

    func rule(_ id: String) async throws(APIError) -> RuleDTO {
        guard let row = rules.first(where: { $0.id == id }) else {
            throw APIError.notFound("Rule not found")
        }
        return withSkips(row)
    }

    func createRule(_ body: RuleBody) async throws(APIError) -> RuleDTO {
        let row = RuleDTO(stubbing: body, id: UUID().uuidString)
        rules.insert(row, at: 0)
        return row
    }

    func updateRule(_ id: String, _ patch: RulePatch) async throws(APIError) -> RuleDTO {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound("Rule not found")
        }
        let current = rules[index]
        switch patch {
        case .activation(let active):
            rules[index] = current.settingActive(active)
        case .definition(let body):
            rules[index] = RuleDTO(stubbing: body, id: current.id)
        }
        return withSkips(rules[index])
    }

    func deleteRule(_ id: String) async throws(APIError) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound("Rule not found")
        }
        rules.remove(at: index)
        skips[id] = nil
    }

    func occurrences(_ id: String, count: Int) async throws(APIError) -> OccurrencesDTO {
        let row = try await rule(id)
        let skipped = skips[id] ?? []
        let entries = row.domain.occurrences(count: count).map {
            OccurrencesDTO.Entry(date: $0.day.iso, time: row.sendTime,
                                 skipped: skipped.contains($0.day.iso))
        }
        return OccurrencesDTO(id: id, occurrences: entries)
    }

    func addSkip(_ id: String, day: CalendarDay) async throws(APIError) {
        guard rules.contains(where: { $0.id == id }) else {
            throw APIError.notFound("Rule not found")
        }
        skips[id, default: []].insert(day.iso)
    }

    func removeSkip(_ id: String, day: CalendarDay) async throws(APIError) {
        guard skips[id]?.contains(day.iso) == true else {
            throw APIError.notFound("That date wasn't skipped")
        }
        skips[id]?.remove(day.iso)
    }

    private func withSkips(_ row: RuleDTO) -> RuleDTO {
        row.settingSkips(Array(skips[row.id] ?? []).sorted())
    }

    // MARK: Events

    func events() async throws(APIError) -> [EventDTO] { events }

    func createEvent(_ body: EventBody) async throws(APIError) -> EventDTO {
        let row = EventDTO(
            id: UUID().uuidString, name: body.name, description: body.description,
            startsAt: body.startsAt, endsAt: body.endsAt, timeLabel: body.timeLabel,
            location: body.location, tone: "burgundy", status: body.status,
            createdAt: Date(), updatedAt: Date()
        )
        events.append(row)
        return row
    }

    func updateEvent(_ id: String, _ patch: PatchBody) async throws(APIError) -> EventDTO {
        guard let index = events.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound("Event not found")
        }
        let current = events[index]
        events[index] = EventDTO(
            id: current.id,
            name: patch.string("name") ?? current.name,
            description: patch.string("description") ?? current.description,
            startsAt: patch.date("starts_at") ?? current.startsAt,
            endsAt: patch.fields["ends_at"] != nil ? patch.date("ends_at") : current.endsAt,
            timeLabel: patch.string("time_label") ?? current.timeLabel,
            location: patch.string("location") ?? current.location,
            tone: current.tone,
            status: patch.string("status") ?? current.status,
            createdAt: current.createdAt, updatedAt: Date()
        )
        return events[index]
    }

    func deleteEvent(_ id: String) async throws(APIError) {
        guard let index = events.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound("Event not found")
        }
        events.remove(at: index)
    }
}

// MARK: - Reading a patch back, for the stub only

private nonisolated extension PatchBody {
    func string(_ key: String) -> String? {
        if case .string(let value) = fields[key] { return value }
        return nil
    }

    func date(_ key: String) -> Date? {
        if case .string(let value) = fields[key] { return APIDate.parse(value) }
        return nil
    }
}

// MARK: - Fixtures as wire rows

private nonisolated extension NoticeDTO {
    init(stubbing notice: Notice) {
        self.init(
            id: notice.id, title: notice.title, message: notice.message,
            sender: notice.sender, status: notice.status.rawValue,
            scheduledAt: notice.scheduledAt, sentAt: notice.sentAt,
            createdAt: notice.createdAt, updatedAt: notice.createdAt,
            createdBy: nil, opens: notice.opens
        )
    }
}

private nonisolated extension RuleDTO {
    init(stubbing rule: RecurringRule) {
        self.init(
            id: rule.id, kind: rule.kind.rawValue,
            days: rule.kind == .weekly ? rule.days : nil,
            dayOfMonth: rule.kind == .monthly ? rule.dayOfMonth : nil,
            sendTime: rule.sendTime.hhmm, title: rule.title, message: rule.message,
            sender: rule.sender, active: rule.active, createdBy: nil,
            createdAt: Date(), updatedAt: Date(),
            skips: rule.skips.map(\.iso).sorted(),
            nextOccurrence: rule.occurrences(count: 1).first?.day.iso
        )
    }

    init(stubbing body: RuleBody, id: String) {
        self.init(
            id: id, kind: body.kind.rawValue,
            days: body.kind == .weekly ? body.days : nil,
            dayOfMonth: body.kind == .monthly ? body.dayOfMonth : nil,
            sendTime: body.sendTime.hhmm, title: body.title, message: body.message,
            sender: body.sender, active: body.active ?? true, createdBy: nil,
            createdAt: Date(), updatedAt: Date(), skips: [], nextOccurrence: nil
        )
    }

    func settingActive(_ active: Bool) -> RuleDTO {
        RuleDTO(id: id, kind: kind, days: days, dayOfMonth: dayOfMonth, sendTime: sendTime,
                title: title, message: message, sender: sender, active: active,
                createdBy: createdBy, createdAt: createdAt, updatedAt: Date(),
                skips: skips, nextOccurrence: nextOccurrence)
    }

    func settingSkips(_ skips: [String]) -> RuleDTO {
        RuleDTO(id: id, kind: kind, days: days, dayOfMonth: dayOfMonth, sendTime: sendTime,
                title: title, message: message, sender: sender, active: active,
                createdBy: createdBy, createdAt: createdAt, updatedAt: updatedAt,
                skips: skips, nextOccurrence: nextOccurrence)
    }
}

private nonisolated extension EventDTO {
    init(stubbing event: ChurchEvent) {
        self.init(
            id: event.id, name: event.name, description: event.description,
            startsAt: event.startsAt, endsAt: event.endsAt, timeLabel: event.timeLabel,
            location: event.location, tone: event.tone.rawValue, status: event.status.rawValue,
            createdAt: Date(), updatedAt: Date()
        )
    }
}
