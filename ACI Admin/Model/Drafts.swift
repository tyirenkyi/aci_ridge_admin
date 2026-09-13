//
//  Drafts.swift
//  ACI Admin
//
//  What a compose screen is editing, and how it turns into a request.
//
//  Drafts are the only thing that builds write bodies. Domain models deliberately
//  aren't Codable, so "just PATCH the model back" — which the server would reject
//  for carrying keys like `id` and `created_at` — isn't expressible.
//

import Foundation

// MARK: - Notices

nonisolated struct NoticeDraft: Equatable, Sendable {
    var title: String = ""
    var message: String = ""
    var sender: String = ""
    /// nil means "as soon as you send it".
    var scheduledAt: Date?

    init() {}

    init(_ notice: Notice) {
        title = notice.title
        message = notice.message
        sender = notice.sender
        scheduledAt = notice.scheduledAt
    }

    var isReady: Bool {
        !title.trimmed.isEmpty && !message.trimmed.isEmpty && !sender.trimmed.isEmpty
    }

    func createBody(scheduled: Bool) -> NoticeBody {
        if scheduled, let scheduledAt {
            return .scheduled(title: title.trimmed, message: message.trimmed,
                              sender: sender.trimmed, at: scheduledAt)
        }
        return .draft(title: title.trimmed, message: message.trimmed, sender: sender.trimmed)
    }

    func patch(from original: Notice, status: NoticeStatus?) -> PatchBody {
        var patch = PatchBody()
        patch.set("title", ifChanged: title.trimmed, from: original.title)
        patch.set("message", ifChanged: message.trimmed, from: original.message)
        patch.set("sender", ifChangedNullable: sender.trimmed, from: original.sender)
        if let status, status != original.status {
            patch.set("status", status.rawValue)
        }
        // Only meaningful while scheduled; the server clears it on any other status.
        if status != .draft {
            patch.set("scheduled_at", ifChanged: scheduledAt, from: original.scheduledAt)
        }
        return patch
    }
}

// MARK: - Recurring rules

nonisolated struct RuleDraft: Equatable, Sendable {
    var title: String = ""
    var message: String = ""
    var sender: String = ""
    var kind: RecurrenceKind = .daily
    var days: [Int] = []
    var dayOfMonth: Int = 1
    var sendTime: TimeOfDay = AdminTimes.default

    init() {}

    init(_ rule: RecurringRule) {
        title = rule.title
        message = rule.message
        sender = rule.sender
        kind = rule.kind
        days = rule.days
        dayOfMonth = rule.dayOfMonth
        sendTime = rule.sendTime
    }

    var isReady: Bool {
        guard !title.trimmed.isEmpty, !message.trimmed.isEmpty, !sender.trimmed.isEmpty else {
            return false
        }
        // A weekly rule with no day selected has no schedule to keep.
        return kind != .weekly || !days.isEmpty
    }

    /// The whole definition — this endpoint replaces rather than merges, and refuses
    /// a partial body.
    func body(active: Bool) -> RuleBody {
        RuleBody(
            kind: RuleBody.Kind(rawValue: kind.rawValue) ?? .daily,
            title: title.trimmed,
            message: message.trimmed,
            sender: sender.trimmed.isEmpty ? nil : sender.trimmed,
            sendTime: sendTime,
            active: active,
            days: days,
            dayOfMonth: dayOfMonth
        )
    }

    /// The compose screen's "first three sends" preview. Worked out on the device
    /// because the rule doesn't exist server-side yet.
    func previewOccurrences(count: Int = 3) -> [RuleOccurrence] {
        let provisional = RecurringRule(
            id: "draft", title: title, message: message, sender: sender,
            kind: kind, days: days, dayOfMonth: dayOfMonth,
            sendTime: sendTime, active: true
        )
        return provisional.occurrences(count: count).map {
            RuleOccurrence(day: $0.day, time: sendTime, skipped: false)
        }
    }
}

// MARK: - Events

nonisolated struct EventDraft: Equatable, Sendable {
    var name: String = ""
    var description: String = ""
    var location: String = ""
    var timeLabel: String = ""
    var startsAt: Date = EventDraft.defaultStart
    var endsAt: Date?
    /// Once the admin writes their own label we stop overwriting it.
    var timeLabelEdited: Bool = false

    init() {
        timeLabel = EventDates.label(startsAt, nil)
    }

    init(_ event: ChurchEvent) {
        name = event.name
        description = event.description
        location = event.location
        timeLabel = event.timeLabel
        startsAt = event.startsAt
        endsAt = event.endsAt
        // An existing label is the admin's, not ours to rewrite.
        timeLabelEdited = !event.timeLabel.isEmpty
    }

    /// The next 6pm that is at least an hour away.
    static var defaultStart: Date {
        let evening = CalendarDay.today.date(at: TimeOfDay(hour: 18, minute: 0)!)
        return evening.timeIntervalSinceNow > 3600
            ? evening
            : CalendarDay.today.adding(days: 1).date(at: TimeOfDay(hour: 18, minute: 0)!)
    }

    var isReady: Bool {
        !name.trimmed.isEmpty && !location.trimmed.isEmpty && isTimeRangeValid
    }

    var isTimeRangeValid: Bool {
        guard let endsAt else { return true }
        return endsAt >= startsAt
    }

    var timeRangeError: String? {
        isTimeRangeValid ? nil : "The end time comes before the start."
    }

    /// What the label says when nobody has overridden it.
    var autoTimeLabel: String { EventDates.label(startsAt, endsAt) }

    /// Call after any date change: keeps the label in step until it's been edited.
    mutating func refreshTimeLabel() {
        guard !timeLabelEdited else { return }
        timeLabel = autoTimeLabel
    }

    func body(status: EventStatus) -> EventBody {
        EventBody(
            name: name.trimmed,
            description: description.trimmed,
            startsAt: startsAt,
            endsAt: endsAt,
            timeLabel: timeLabel.trimmed,
            location: location.trimmed,
            status: status.rawValue
        )
    }

    func patch(from original: ChurchEvent, status: EventStatus?) -> PatchBody {
        var patch = PatchBody()
        patch.set("name", ifChanged: name.trimmed, from: original.name)
        patch.set("description", ifChangedNullable: description.trimmed, from: original.description)
        patch.set("location", ifChangedNullable: location.trimmed, from: original.location)
        patch.set("time_label", ifChangedNullable: timeLabel.trimmed, from: original.timeLabel)
        patch.set("starts_at", ifChanged: startsAt, from: original.startsAt)
        patch.set("ends_at", ifChanged: endsAt, from: original.endsAt)
        if let status, status != original.status {
            patch.set("status", status.rawValue)
        }
        return patch
    }
}

// MARK: -

nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
