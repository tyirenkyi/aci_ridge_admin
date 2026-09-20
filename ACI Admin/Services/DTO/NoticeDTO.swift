//
//  NoticeDTO.swift
//  ACI Admin
//
//  Wire shapes for /api/notices. Rows are raw Postgres, so everything is
//  snake_case; CodingKeys are spelled out rather than inferred so the contract is
//  readable here and the camelCase `push` island can't surprise us.
//

import Foundation

nonisolated struct NoticeDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let message: String
    let sender: String?
    let status: String
    let scheduledAt: Date?
    let sentAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    /// Always present: the server computes it even on writes, where it is 0.
    let opens: Int

    enum CodingKeys: String, CodingKey {
        case id, title, message, sender, status, opens
        case scheduledAt = "scheduled_at"
        case sentAt = "sent_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case createdBy = "created_by"
    }
}

/// `POST /api/notices`. Scheduling requires a future `scheduled_at`, and the server
/// nulls the field for any status but `scheduled`.
nonisolated struct NoticeBody: Encodable, Sendable {
    var title: String
    var message: String
    var sender: String?
    var status: String          // "draft" | "scheduled" — never "sent"
    var scheduledAt: Date?

    enum CodingKeys: String, CodingKey {
        case title, message, sender, status
        case scheduledAt = "scheduled_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(message, forKey: .message)
        try c.encode(status, forKey: .status)
        // Omit rather than null: create bodies are strict and these are optional,
        // not nullable.
        if let sender, !sender.isEmpty { try c.encode(sender, forKey: .sender) }
        if let scheduledAt { try c.encode(scheduledAt, forKey: .scheduledAt) }
    }

    static func draft(title: String, message: String, sender: String?) -> NoticeBody {
        NoticeBody(title: title, message: message, sender: sender, status: "draft", scheduledAt: nil)
    }

    static func scheduled(title: String, message: String, sender: String?, at date: Date) -> NoticeBody {
        NoticeBody(title: title, message: message, sender: sender, status: "scheduled", scheduledAt: date)
    }
}

/// `POST /api/notices/:id/send` answers with the notice's own fields plus a `push`
/// summary, so decode the notice from the same container.
nonisolated struct SendResultDTO: Decodable, Sendable {
    let notice: NoticeDTO
    let push: PushDTO?

    private enum CodingKeys: String, CodingKey { case push }

    init(notice: NoticeDTO, push: PushDTO?) {
        self.notice = notice
        self.push = push
    }

    init(from decoder: any Decoder) throws {
        notice = try NoticeDTO(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        push = try c.decodeIfPresent(PushDTO.self, forKey: .push)
    }
}

nonisolated extension NoticeDTO {
    var domain: Notice {
        Notice(
            id: id,
            title: title ?? "",
            message: message,
            sender: sender ?? "",
            status: NoticeStatus(rawValue: status) ?? .draft,
            scheduledAt: scheduledAt,
            sentAt: sentAt,
            opens: opens,
            createdAt: createdAt
        )
    }
}
