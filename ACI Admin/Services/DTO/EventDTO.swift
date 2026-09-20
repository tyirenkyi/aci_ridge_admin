//
//  EventDTO.swift
//  ACI Admin
//
//  Wire shapes for /api/events. Publishing is a status PATCH — there is no
//  dedicated publish route.
//

import Foundation

nonisolated struct EventDTO: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let startsAt: Date
    let endsAt: Date?
    let timeLabel: String?
    let location: String?
    let tone: String
    let status: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description, location, tone, status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeLabel = "time_label"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct EventBody: Encodable, Sendable {
    var name: String
    var description: String?
    var startsAt: Date
    var endsAt: Date?
    var timeLabel: String?
    var location: String?
    var status: String          // "draft" | "published"

    enum CodingKeys: String, CodingKey {
        case name, description, location, status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeLabel = "time_label"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(startsAt, forKey: .startsAt)
        try c.encode(status, forKey: .status)
        // Optional, not nullable, on create — omit when empty.
        if let description, !description.isEmpty { try c.encode(description, forKey: .description) }
        if let endsAt { try c.encode(endsAt, forKey: .endsAt) }
        if let timeLabel, !timeLabel.isEmpty { try c.encode(timeLabel, forKey: .timeLabel) }
        if let location, !location.isEmpty { try c.encode(location, forKey: .location) }
        // `tone` is deliberately absent: the console doesn't expose it, and the
        // server defaults it to burgundy.
    }
}

nonisolated extension EventDTO {
    var domain: ChurchEvent {
        ChurchEvent(
            id: id,
            name: name,
            description: description ?? "",
            startsAt: startsAt,
            endsAt: endsAt,
            timeLabel: timeLabel ?? "",
            location: location ?? "",
            tone: EventTone(rawValue: tone) ?? .burgundy,
            status: EventStatus(rawValue: status) ?? .draft
        )
    }
}
