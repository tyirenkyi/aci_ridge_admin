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

enum AdminDates {
    static let today: Date = Calendar.current.startOfDay(for: Date())

    static func add(_ days: Int, to date: Date = today) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
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

// MARK: - Admin

struct AdminUser {
    let name: String
    let email: String
    let church: String
    let initials: String

    static let current = AdminUser(
        name: "Franklin Owusu",
        email: "franklin@acirid.ge",
        church: "Ridge Community Cathedral",
        initials: "FO"
    )
}

// MARK: - Notices

enum NoticeStatus: String, Hashable {
    case scheduled, sent, draft
}

struct Notice: Identifiable, Hashable {
    let id: String
    var title: String
    var message: String
    var sender: String
    var status: NoticeStatus
    var when: String
    var audience: String
    var opens: String? = nil
}

// MARK: - Recurring

enum RecurrenceKind: String, Hashable, CaseIterable {
    case daily, weekly, monthly

    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

struct RecurringRule: Identifiable, Hashable {
    let id: String
    var title: String
    var message: String
    var sender: String
    var kind: RecurrenceKind
    var days: [Int] = []
    var dayOfMonth: Int = 1
    var time: String
    var active: Bool
    var skips: [Int] = []

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

    struct Occurrence: Identifiable {
        let offset: Int
        let date: Date
        var id: Int { offset }
    }

    /// Next occurrences of the rule, starting today.
    func occurrences(count: Int = 8) -> [Occurrence] {
        var out: [Occurrence] = []
        var i = 0
        let cal = Calendar.current
        while out.count < count && i < 120 {
            let d = AdminDates.add(i)
            let hit: Bool
            switch kind {
            case .daily: hit = true
            case .weekly: hit = days.contains(cal.component(.weekday, from: d) - 1)
            case .monthly: hit = cal.component(.day, from: d) == dayOfMonth
            }
            if hit { out.append(Occurrence(offset: i, date: d)) }
            i += 1
        }
        return out
    }
}

// MARK: - Events

enum EventStatus: String, Hashable {
    case published, draft
}

struct ChurchEvent: Identifiable, Hashable {
    let id: String
    var name: String
    var description: String
    var timeLabel: String
    var location: String
    var status: EventStatus
}

// MARK: - Today's queue

struct QueueItem: Identifiable, Hashable {
    enum State { case sent, pending }
    let id: String
    let time: String
    let title: String
    let sender: String
    let state: State
    let recurring: Bool
}

// MARK: - Translations

struct Language: Hashable, Identifiable {
    let code: String     // FR
    let value: String    // fr
    let native: String   // Français
    let label: String    // French
    var id: String { value }

    static let french = Language(code: "FR", value: "fr", native: "Français", label: "French")
    static let spanish = Language(code: "ES", value: "es", native: "Español", label: "Spanish")
    static let all: [Language] = [.french, .spanish]
}

enum ReviewStatus: String, Hashable {
    case pending, approved, rejected
}

struct TranslationField: Hashable {
    let label: String
    let source: String
    let draft: String

    /// Body copy and declarations render in the scripture serif.
    var usesSerif: Bool { label == "Body" || label.hasPrefix("Declaration") }
}

struct AudioInfo: Hashable {
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

struct TranslationItem: Identifiable, Hashable {
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

enum SampleData {
    static let notices: [Notice] = [
        Notice(id: "n1", title: "Baptism service this Sunday",
               message: "Candidates should arrive by 6:30 am with a change of white clothing. Families are welcome to stay for the whole service.",
               sender: "Ridge Community Cathedral", status: .scheduled,
               when: "Fri 6:00 am", audience: "All members"),
        Notice(id: "n2", title: "Choir rehearsal moved",
               message: "Thursday rehearsal now begins at 6:30 pm in the main hall instead of the annex.",
               sender: "Josephine Nyarko", status: .sent,
               when: "Sent Tue 4:12 pm", audience: "All members", opens: "412 opened"),
        Notice(id: "n3", title: "Building fund update",
               message: "The east wing roofing is complete. Thank you for your faithfulness — a full report follows on Sunday.",
               sender: "Church office", status: .draft,
               when: "Not scheduled", audience: "All members"),
    ]

    static let recurring: [RecurringRule] = [
        RecurringRule(id: "r1", title: "Today's Lamp is ready",
                      message: "Your devotion for today is live. Take five quiet minutes before the day begins.",
                      sender: "The Lamp", kind: .daily, time: "5:30 am", active: true, skips: [3]),
        RecurringRule(id: "r2", title: "First service starts in one hour",
                      message: "Sunday first service begins at 7:00 am. 31 Volta Street, Ridge.",
                      sender: "Church office", kind: .weekly, days: [0], time: "6:00 am", active: true),
        RecurringRule(id: "r3", title: "Tuesday evening service",
                      message: "Midweek service begins at 6:00 pm. Come as you are.",
                      sender: "Church office", kind: .weekly, days: [2], time: "4:00 pm", active: true),
        RecurringRule(id: "r4", title: "Communion Sunday",
                      message: "We break bread together this morning. Please prepare your heart.",
                      sender: "Ridge Community Cathedral", kind: .monthly, dayOfMonth: 1, time: "6:00 am", active: false),
    ]

    static let events: [ChurchEvent] = [
        ChurchEvent(id: "e1", name: "Night of Worship",
                    description: "An evening of praise with the cathedral choir and guest ministers. Doors open at 5:30 pm.",
                    timeLabel: "Friday, 6:00 pm — 9:00 pm",
                    location: "Main auditorium · 31 Volta Street", status: .published),
        ChurchEvent(id: "e2", name: "Youth Convention 2026",
                    description: "Three days for ages 13–25. Registration closes the Sunday before.",
                    timeLabel: "Sept 12–14 · daily from 8:00 am",
                    location: "Cathedral annex, Ridge", status: .published),
        ChurchEvent(id: "e3", name: "Leaders’ Retreat",
                    description: "Ministry heads and elders. Transport leaves the cathedral at 6:00 am.",
                    timeLabel: "Saturday, all day",
                    location: "Lake Bosomtwe", status: .draft),
    ]

    static let queue: [QueueItem] = [
        QueueItem(id: "q1", time: "5:30 am", title: "Today's Lamp is ready", sender: "The Lamp", state: .sent, recurring: true),
        QueueItem(id: "q2", time: "4:00 pm", title: "Tuesday evening service", sender: "Church office", state: .pending, recurring: true),
        QueueItem(id: "q3", time: "6:00 pm", title: "Baptism service this Sunday", sender: "Ridge Community Cathedral", state: .pending, recurring: false),
    ]

    static let times = ["4:00 am", "4:30 am", "5:00 am", "5:30 am", "6:00 am", "6:30 am", "7:00 am", "8:00 am",
                        "9:00 am", "12:00 pm", "2:00 pm", "4:00 pm", "5:00 pm", "6:00 pm", "7:00 pm", "8:00 pm"]

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

// MARK: - Store

/// In-memory prototype state. Holds the sample content so every screen reads
/// from one place; the only mutations are the small visual ones the
/// click-through needs (toggles, skips, toasts). No persistence, no network.
@Observable
final class AdminStore {
    var notices: [Notice] = SampleData.notices
    var recurring: [RecurringRule] = SampleData.recurring
    var events: [ChurchEvent] = SampleData.events
    var queue: [QueueItem] = SampleData.queue
    var translations: [String: [TranslationItem]] = SampleData.translations
    var reviewLanguage: Language = .french

    var toast: String? = nil
    private var toastTask: Task<Void, Never>? = nil

    func pendingCount(_ lang: Language) -> Int {
        (translations[lang.value] ?? []).filter { $0.status == .pending }.count
    }

    var pendingTotal: Int { Language.all.reduce(0) { $0 + pendingCount($1) } }

    func rule(_ id: RecurringRule.ID) -> RecurringRule? {
        recurring.first { $0.id == id }
    }

    func translation(_ id: TranslationItem.ID) -> TranslationItem? {
        translations.values.joined().first { $0.id == id }
    }

    func toggleRule(_ id: RecurringRule.ID) {
        guard let i = recurring.firstIndex(where: { $0.id == id }) else { return }
        recurring[i].active.toggle()
    }

    func toggleSkip(_ id: RecurringRule.ID, offset: Int) {
        guard let i = recurring.firstIndex(where: { $0.id == id }) else { return }
        if let j = recurring[i].skips.firstIndex(of: offset) {
            recurring[i].skips.remove(at: j)
            flash("Date restored")
        } else {
            recurring[i].skips.append(offset)
            recurring[i].skips.sort()
            flash("Date skipped — nothing will send")
        }
    }

    func flash(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { toast = nil }
        }
    }
}
