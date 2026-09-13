//
//  RuleDTO.swift
//  ACI Admin
//
//  Wire shapes for /api/rules. `send_time` is "HH:mm" in 24h UTC and `days` uses
//  0 = Sunday, matching the server's getUTCDay().
//

import Foundation

nonisolated struct RuleDTO: Decodable, Sendable {
    let id: String
    let kind: String
    let days: [Int]?
    let dayOfMonth: Int?
    let sendTime: String
    let title: String
    let message: String
    let sender: String?
    let active: Bool
    let createdBy: String?
    let createdAt: Date?
    let updatedAt: Date?
    /// "YYYY-MM-DD". Empty on a create response, which selects `*` without the
    /// skips embed — see AdminStore.saveRule, which refetches after a create.
    let skips: [String]
    let nextOccurrence: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, days, title, message, sender, active, skips
        case dayOfMonth = "day_of_month"
        case sendTime = "send_time"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case nextOccurrence = "next_occurrence"
    }
}

/// The create/replace body. The server validates this as a discriminated union on
/// `kind` with strict key checking, so a `days` key on a daily rule is a 400 — which
/// is why this encodes by hand instead of leaning on optional fields.
nonisolated struct RuleBody: Encodable, Sendable, Equatable {
    enum Kind: String, Sendable, Equatable { case daily, weekly, monthly }

    var kind: Kind
    var title: String
    var message: String
    var sender: String?
    var sendTime: TimeOfDay
    var active: Bool?
    /// Weekly only. 0 = Sunday, 1...7 entries.
    var days: [Int] = []
    /// Monthly only. 1...28.
    var dayOfMonth: Int = 1

    enum CodingKeys: String, CodingKey {
        case kind, title, message, sender, days, active
        case sendTime = "send_time"
        case dayOfMonth = "day_of_month"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(message, forKey: .message)
        try c.encode(sendTime.hhmm, forKey: .sendTime)
        if let sender, !sender.isEmpty { try c.encode(sender, forKey: .sender) }
        if let active { try c.encode(active, forKey: .active) }

        // Only the key this kind owns. Anything else is rejected.
        switch kind {
        case .daily:
            break
        case .weekly:
            try c.encode(Array(Set(days)).sorted(), forKey: .days)
        case .monthly:
            try c.encode(dayOfMonth, forKey: .dayOfMonth)
        }
    }
}

/// `PATCH /api/rules/:id` takes either `{ active }` on its own or a whole
/// definition, and rejects anything in between.
nonisolated enum RulePatch: Encodable, Sendable {
    case activation(Bool)
    case definition(RuleBody)

    private enum CodingKeys: String, CodingKey { case active }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .activation(let active):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(active, forKey: .active)
        case .definition(let body):
            try body.encode(to: encoder)
        }
    }
}

nonisolated struct OccurrencesDTO: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let date: String     // "YYYY-MM-DD"
        let time: String     // "HH:mm"
        let skipped: Bool
    }

    let id: String
    let occurrences: [Entry]
}

nonisolated struct SkipDTO: Decodable, Sendable {
    let ruleId: String
    let date: String

    enum CodingKeys: String, CodingKey {
        case date
        case ruleId = "rule_id"
    }
}

nonisolated struct SkipBody: Encodable, Sendable {
    let date: String
}

nonisolated extension RuleDTO {
    var domain: RecurringRule {
        RecurringRule(
            id: id,
            title: title,
            message: message,
            sender: sender ?? "",
            kind: RecurrenceKind(rawValue: kind) ?? .daily,
            days: days ?? [],
            dayOfMonth: dayOfMonth ?? 1,
            sendTime: TimeOfDay(hhmm: sendTime) ?? AdminTimes.default,
            active: active,
            skips: Set(skips.compactMap(CalendarDay.init(iso:))),
            nextOccurrence: nextOccurrence.flatMap(CalendarDay.init(iso:))
        )
    }
}

nonisolated extension OccurrencesDTO {
    var domain: [RuleOccurrence] {
        occurrences.compactMap { entry in
            guard let day = CalendarDay(iso: entry.date),
                  let time = TimeOfDay(hhmm: entry.time)
            else { return nil }
            return RuleOccurrence(day: day, time: time, skipped: entry.skipped)
        }
    }
}
