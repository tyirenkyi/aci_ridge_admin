//
//  AdminModels.swift
//  ACI Admin
//
//  Everything the admin console displays, ported from admin-data.jsx.
//  Prototype data only — nothing here talks to a backend.
//

import Foundation
import Observation

// MARK: - Dates

nonisolated enum AdminDates {
    /// Computed, not stored: a console left open overnight must not keep yesterday's
    /// idea of "today". Always the church's day — see Calendar.ghana.
    static var today: Date { Calendar.ghana.startOfDay(for: Date()) }

    static func add(_ days: Int, to date: Date = AdminDates.today) -> Date {
        Calendar.ghana.date(byAdding: .day, value: days, to: date) ?? date
    }

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = Calendar.ghana.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = Calendar.ghana.timeZone
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    /// "Sun 30 Aug"
    static func short(_ date: Date) -> String { shortFormatter.string(from: date) }

    /// "Sunday, August 30"
    static func long(_ date: Date) -> String { longFormatter.string(from: date) }

    /// Label for a day offset from today, as the design phrases it.
    static func relative(_ offset: Int, long: Bool = false) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return long ? Self.long(add(offset)) : short(add(offset))
        }
    }

    /// How a notice states its send time: "Today 6:00 am", "Tomorrow 6:00 am",
    /// "Fri 6:00 am" inside the week, "Sun 30 Aug · 6:00 am" beyond it.
    static func whenLabel(_ date: Date?) -> String {
        guard let date else { return "Not scheduled" }
        let day = CalendarDay(date)
        let time = TimeOfDay(date).display
        switch day.offsetFromToday() {
        case 0: return "Today \(time)"
        case 1: return "Tomorrow \(time)"
        case 2...6: return "\(dayShort[day.weekdayIndex]) \(time)"
        default: return "\(short(date)) · \(time)"
        }
    }

    static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let dayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func ordinal(_ n: Int) -> String {
        let v = n % 100
        let suffix: String
        if (11...13).contains(v) { suffix = "th" }
        else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Notices

nonisolated enum NoticeStatus: String, Hashable {
    case scheduled, sent, draft
}

nonisolated struct Notice: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var message: String
    /// Empty when the server has none; the composer falls back to the church name.
    var sender: String
    var status: NoticeStatus
    var scheduledAt: Date?
    var sentAt: Date?
    /// How many members opened it. The server computes this; there is no per-member
    /// receipt endpoint.
    var opens: Int = 0
    var createdAt: Date?

    /// Was a stored display string in the prototype; derived now so it can never
    /// drift from the dates behind it.
    var when: String {
        switch status {
        case .draft: return "Not scheduled"
        case .scheduled: return AdminDates.whenLabel(scheduledAt)
        case .sent: return "Sent \(AdminDates.whenLabel(sentAt))"
        }
    }

    var opensLabel: String? {
        status == .sent ? "\(opens) opened" : nil
    }

    /// A sent notice is history: the server rejects edits and deletes with a 409.
    var isEditable: Bool { status != .sent }
}

// MARK: - Recurring

nonisolated enum RecurrenceKind: String, Hashable, CaseIterable {
    case daily, weekly, monthly

    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

nonisolated struct RecurringRule: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var message: String
    var sender: String
    var kind: RecurrenceKind
    /// 0 = Sunday, matching the server's getUTCDay().
    var days: [Int] = []
    /// 1...28. Capped so every month actually has the date.
    var dayOfMonth: Int = 1
    var sendTime: TimeOfDay
    var active: Bool
    /// Absolute dates, as the server stores them. The prototype used offsets from
    /// launch day, which went stale the moment the app stayed open past midnight.
    var skips: Set<CalendarDay> = []
    var nextOccurrence: CalendarDay?

    /// Kept so `ruleLabel` and the screens read the same as they always did.
    var time: String { sendTime.display }

    /// Skips that still lie ahead — the only ones worth counting in the UI.
    var upcomingSkips: Set<CalendarDay> { skips.filter { $0 >= .today } }

    func isSkipped(_ day: CalendarDay) -> Bool { skips.contains(day) }

    /// The human sentence the rule adds up to.
    var ruleLabel: String {
        switch kind {
        case .daily:
            return "Daily · \(time)"
        case .weekly:
            if days.isEmpty { return "Weekly · pick a day · \(time)" }
            let sorted = days.sorted()
            let label: String
            if sorted.count == 1 { label = AdminDates.dayNames[sorted[0]] }
            else if sorted.count == 7 { label = "every day" }
            else { label = sorted.map { AdminDates.dayShort[$0] }.joined(separator: ", ") }
            return "Weekly · \(label) · \(time)"
        case .monthly:
            return "Monthly · \(AdminDates.ordinal(dayOfMonth)) of the month · \(time)"
        }
    }

    struct Occurrence: Identifiable, Hashable {
        let offset: Int
        let day: CalendarDay
        var id: Int { offset }
        var date: Date { day.date() }
    }

    /// Occurrences worked out on the device.
    ///
    /// This mirrors the server's own calculation and exists for the compose screen's
    /// preview, where the rule doesn't exist yet so there is nothing to ask about.
    /// Anywhere a saved rule is shown, prefer GET /api/rules/:id/occurrences — it is
    /// authoritative and already knows which dates are skipped. Keep the two in step.
    func occurrences(count: Int = 8) -> [Occurrence] {
        var out: [Occurrence] = []
        var i = 0
        let start = CalendarDay.today
        while out.count < count && i < 120 {
            let day = start.adding(days: i)
            let hit: Bool
            switch kind {
            case .daily: hit = true
            case .weekly: hit = days.contains(day.weekdayIndex)
            case .monthly: hit = day.day == dayOfMonth
            }
            if hit { out.append(Occurrence(offset: i, day: day)) }
            i += 1
        }
        return out
    }
}

/// One scheduled send, as the server reports it.
nonisolated struct RuleOccurrence: Identifiable, Hashable, Sendable {
    let day: CalendarDay
    let time: TimeOfDay
    var skipped: Bool

    var id: String { day.iso }
    var isToday: Bool { day.isToday }
    var date: Date { day.date(at: time) }
}

// MARK: - Events

nonisolated enum EventStatus: String, Hashable {
    case published, draft
}

nonisolated enum EventTone: String, Hashable, Sendable, CaseIterable {
    case burgundy, gold, sapphire, emerald
}

nonisolated struct ChurchEvent: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var description: String
    /// Required by the server, and what ordering and expiry actually run on.
    var startsAt: Date
    var endsAt: Date?
    /// The sentence members read. Auto-filled from the dates, but an admin can say
    /// it better than a date pair can — "Sept 12–14 · daily from 8:00 am".
    var timeLabel: String
    var location: String
    var tone: EventTone = .burgundy
    var status: EventStatus

    var displayTime: String {
        timeLabel.isEmpty ? EventDates.label(startsAt, endsAt) : timeLabel
    }
}

/// How an event's dates read when nobody has written a label by hand.
nonisolated enum EventDates {
    static func label(_ starts: Date, _ ends: Date?) -> String {
        let startDay = CalendarDay(starts)
        let startTime = TimeOfDay(starts).display
        let dayText = AdminDates.long(starts)

        guard let ends else { return "\(dayText) · \(startTime)" }

        let endDay = CalendarDay(ends)
        let endTime = TimeOfDay(ends).display
        if endDay == startDay {
            return "\(dayText), \(startTime) — \(endTime)"
        }
        return "\(AdminDates.short(starts)) \(startTime) — \(AdminDates.short(ends)) \(endTime)"
    }
}

// MARK: - Today's queue

nonisolated struct QueueItem: Identifiable, Hashable {
    enum State { case sent, pending }
    let id: String
    let time: String
    let title: String
    let sender: String
    let state: State
    let recurring: Bool
}

// MARK: - Translations

nonisolated struct Language: Hashable, Identifiable {
    let code: String     // FR
    let value: String    // fr
    let native: String   // Français
    let label: String    // French
    var id: String { value }

    static let french = Language(code: "FR", value: "fr", native: "Français", label: "French")
    static let spanish = Language(code: "ES", value: "es", native: "Español", label: "Spanish")
    static let all: [Language] = [.french, .spanish]
}

nonisolated enum ReviewStatus: String, Hashable {
    case pending, approved, rejected
}

nonisolated struct TranslationField: Hashable {
    let label: String
    let source: String
    let draft: String

    /// Body copy and declarations render in the scripture serif.
    var usesSerif: Bool { label == "Body" || label.hasPrefix("Declaration") }
}

nonisolated struct AudioInfo: Hashable {
    let duration: String
    let voice: String
    let recorded: String
    let size: String

    var totalSeconds: Int {
        let parts = duration.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }
}

nonisolated struct TranslationItem: Identifiable, Hashable {
    let id: String
    /// 0 = today, -1 = tomorrow (mirrors the design's sign convention).
    let offset: Int
    let type: String
    let title: String
    let fields: [TranslationField]
    var status: ReviewStatus
    var note: String? = nil
    var audio: AudioInfo? = nil

    var dayLabel: String { offset == 0 ? "Today" : AdminDates.short(AdminDates.add(-offset)) }
    var dayLabelLong: String { offset == 0 ? "Today" : AdminDates.long(AdminDates.add(-offset)) }
}

// MARK: - Sample content

nonisolated enum SampleData {
    /// A few fixed points so the fixtures read the same every run.
    private static func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        CalendarDay.today.adding(days: days).date(at: TimeOfDay(hour: hour, minute: minute) ?? .midnight)
    }

    static let notices: [Notice] = [
        Notice(id: "n1", title: "Baptism service this Sunday",
               message: "Candidates should arrive by 6:30 am with a change of white clothing. Families are welcome to stay for the whole service.",
               sender: "Ridge Community Cathedral", status: .scheduled,
               scheduledAt: at(3, 6), sentAt: nil),
        Notice(id: "n2", title: "Choir rehearsal moved",
               message: "Thursday rehearsal now begins at 6:30 pm in the main hall instead of the annex.",
               sender: "Josephine Nyarko", status: .sent,
               scheduledAt: nil, sentAt: at(-1, 16, 12), opens: 412),
        Notice(id: "n3", title: "Building fund update",
               message: "The east wing roofing is complete. Thank you for your faithfulness — a full report follows on Sunday.",
               sender: "Church office", status: .draft,
               scheduledAt: nil, sentAt: nil),
    ]

    static let recurring: [RecurringRule] = [
        RecurringRule(id: "r1", title: "Today's Lamp is ready",
                      message: "Your devotion for today is live. Take five quiet minutes before the day begins.",
                      sender: "The Lamp", kind: .daily,
                      sendTime: TimeOfDay(hour: 5, minute: 30)!, active: true,
                      skips: [CalendarDay.today.adding(days: 3)]),
        RecurringRule(id: "r2", title: "First service starts in one hour",
                      message: "Sunday first service begins at 7:00 am. 31 Volta Street, Ridge.",
                      sender: "Church office", kind: .weekly, days: [0],
                      sendTime: TimeOfDay(hour: 6, minute: 0)!, active: true),
        RecurringRule(id: "r3", title: "Tuesday evening service",
                      message: "Midweek service begins at 6:00 pm. Come as you are.",
                      sender: "Church office", kind: .weekly, days: [2],
                      sendTime: TimeOfDay(hour: 16, minute: 0)!, active: true),
        RecurringRule(id: "r4", title: "Communion Sunday",
                      message: "We break bread together this morning. Please prepare your heart.",
                      sender: "Ridge Community Cathedral", kind: .monthly, dayOfMonth: 1,
                      sendTime: TimeOfDay(hour: 6, minute: 0)!, active: false),
    ]

    static let events: [ChurchEvent] = [
        ChurchEvent(id: "e1", name: "Night of Worship",
                    description: "An evening of praise with the cathedral choir and guest ministers. Doors open at 5:30 pm.",
                    startsAt: at(2, 18), endsAt: at(2, 21),
                    timeLabel: "Friday, 6:00 pm — 9:00 pm",
                    location: "Main auditorium · 31 Volta Street", status: .published),
        ChurchEvent(id: "e2", name: "Youth Convention 2026",
                    description: "Three days for ages 13–25. Registration closes the Sunday before.",
                    startsAt: at(9, 8), endsAt: at(11, 17),
                    timeLabel: "Sept 12–14 · daily from 8:00 am",
                    location: "Cathedral annex, Ridge", status: .published),
        ChurchEvent(id: "e3", name: "Leaders’ Retreat",
                    description: "Ministry heads and elders. Transport leaves the cathedral at 6:00 am.",
                    startsAt: at(16, 6), endsAt: nil,
                    timeLabel: "Saturday, all day",
                    location: "Lake Bosomtwe", status: .draft),
    ]

    static let translations: [String: [TranslationItem]] = [
        "fr": [
            TranslationItem(id: "fr-d0", offset: 0, type: "Daily devotion", title: "The Stone Still Speaks",
                fields: [
                    TranslationField(label: "Title", source: "The Stone Still Speaks", draft: "La pierre parle encore"),
                    TranslationField(label: "Scripture", source: "John 11:23–26", draft: "Jean 11:23–26"),
                    TranslationField(label: "Body",
                        source: "Martha met Jesus with a sentence that carried both faith and grief. She believed in a resurrection far away, at the last day. He moved it closer.",
                        draft: "Marthe rencontra Jésus avec une phrase qui portait à la fois la foi et le chagrin. Elle croyait en une résurrection lointaine, au dernier jour. Il l'a rapprochée."),
                ],
                status: .pending,
                audio: AudioInfo(duration: "4:12", voice: "Studio · Amélie", recorded: "Yesterday, 8:40 pm", size: "3.8 MB")),
            TranslationItem(id: "fr-p0", offset: 0, type: "Prayers & declarations", title: "5 prayers · 5 declarations",
                fields: [
                    TranslationField(label: "Prayer 1", source: "For a faith that is present tense", draft: "Pour une foi au présent"),
                    TranslationField(label: "Prayer 2", source: "For the grief we still carry", draft: "Pour le chagrin que nous portons encore"),
                    TranslationField(label: "Declaration 1", source: "I am held by the One who is the resurrection.", draft: "Je suis tenu par Celui qui est la résurrection."),
                ],
                status: .pending,
                audio: AudioInfo(duration: "2:38", voice: "Studio · Amélie", recorded: "Yesterday, 9:05 pm", size: "2.4 MB")),
            TranslationItem(id: "fr-n1", offset: 0, type: "Notification", title: "Baptism service this Sunday",
                fields: [
                    TranslationField(label: "Title", source: "Baptism service this Sunday", draft: "Service de baptême ce dimanche"),
                    TranslationField(label: "Message", source: "Candidates should arrive by 6:30 am with a change of white clothing.", draft: "Les candidats doivent arriver à 6h30 avec des vêtements blancs de rechange."),
                    TranslationField(label: "Sender", source: "Ridge Community Cathedral", draft: "Du bureau pastoral"),
                ],
                status: .pending),
            TranslationItem(id: "fr-r1", offset: 0, type: "Recurring notification", title: "Today's Lamp is ready",
                fields: [
                    TranslationField(label: "Title", source: "Today's Lamp is ready", draft: "La Lampe du jour est prête"),
                    TranslationField(label: "Message", source: "Your devotion for today is live.", draft: "Votre méditation du jour est disponible."),
                ],
                status: .approved,
                audio: AudioInfo(duration: "0:22", voice: "Studio · Amélie", recorded: "Mon, 7:15 am", size: "0.4 MB")),
            TranslationItem(id: "fr-d1", offset: -1, type: "Daily devotion", title: "Tomorrow · A Lamp for the Path",
                fields: [
                    TranslationField(label: "Title", source: "A Lamp for the Path", draft: "Une lampe pour le chemin"),
                    TranslationField(label: "Scripture", source: "Psalm 119:105", draft: "Psaume 119:105"),
                ],
                status: .pending),
        ],
        "es": [
            TranslationItem(id: "es-d0", offset: 0, type: "Daily devotion", title: "The Stone Still Speaks",
                fields: [
                    TranslationField(label: "Title", source: "The Stone Still Speaks", draft: "La piedra aún habla"),
                    TranslationField(label: "Scripture", source: "John 11:23–26", draft: "Juan 11:23–26"),
                    TranslationField(label: "Body",
                        source: "Martha met Jesus with a sentence that carried both faith and grief. She believed in a resurrection far away, at the last day. He moved it closer.",
                        draft: "Marta se encontró con Jesús con una frase que llevaba fe y dolor a la vez. Ella creía en una resurrección lejana, en el último día. Él la acercó."),
                ],
                status: .pending,
                audio: AudioInfo(duration: "4:31", voice: "Studio · Mateo", recorded: "Yesterday, 7:20 pm", size: "4.1 MB")),
            TranslationItem(id: "es-n1", offset: 0, type: "Notification", title: "Choir rehearsal moved",
                fields: [
                    TranslationField(label: "Title", source: "Choir rehearsal moved", draft: "Ensayo del coro reprogramado"),
                    TranslationField(label: "Message", source: "Thursday rehearsal now begins at 6:30 pm in the main hall.", draft: "El ensayo del jueves comienza ahora a las 6:30 pm en el salón principal."),
                ],
                status: .rejected,
                note: "Use \"sala principal\" — \"salón\" reads like a hall for hire."),
            TranslationItem(id: "es-p0", offset: 0, type: "Prayers & declarations", title: "5 prayers · 5 declarations",
                fields: [
                    TranslationField(label: "Prayer 1", source: "For a faith that is present tense", draft: "Por una fe en tiempo presente"),
                    TranslationField(label: "Declaration 1", source: "I am held by the One who is the resurrection.", draft: "Soy sostenido por Aquel que es la resurrección."),
                ],
                status: .pending,
                audio: AudioInfo(duration: "2:54", voice: "Studio · Mateo", recorded: "Yesterday, 7:48 pm", size: "2.7 MB")),
        ],
    ]
}
