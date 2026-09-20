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

nonisolated struct Language: Hashable, Identifiable, Sendable {
    let code: String     // FR
    let value: String    // fr
    let native: String   // Français
    let label: String    // French
    var id: String { value }

    static let french = Language(code: "FR", value: "fr", native: "Français", label: "French")
    static let spanish = Language(code: "ES", value: "es", native: "Español", label: "Spanish")
    static let all: [Language] = [.french, .spanish]

    static func named(_ value: String) -> Language? { all.first { $0.value == value } }
}

nonisolated enum ReviewStatus: String, Hashable, Sendable {
    case pending, approved, rejected

    /// The server's word for "translated but nobody has looked at it yet" is
    /// `draft`; the console calls that pending. `none` means the day was never
    /// translated, which is not a review state at all — hence the failable init.
    init?(wire: String) {
        switch wire {
        case "draft":    self = .pending
        case "approved": self = .approved
        case "rejected": self = .rejected
        default:         return nil
        }
    }

    /// What a decision sends back. Pending is never written by the console.
    var wire: String { rawValue }
}

nonisolated struct TranslationField: Hashable, Sendable {
    let label: String
    let source: String
    let draft: String
    /// Scripture, declarations and body paragraphs read as scripture, so they set
    /// in the display serif. Carried explicitly rather than guessed from the label,
    /// which used to break the moment a label was reworded.
    let usesSerif: Bool
}

/// One recording in a day's narration.
///
/// A devotional is never a single file: there is the main narration, the
/// declarations, one file per prayer, and a language-neutral music bed — each with
/// an English counterpart to A/B against. `translated` is nil for the music bed
/// (it is shared, not translated) and for any part the job has not voiced yet.
nonisolated struct AudioTrack: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    let translated: URL?
    let source: URL?

    var id: String { key }
    var hasTranslation: Bool { translated != nil }
    var hasSource: Bool { source != nil }
    var isPlayable: Bool { hasTranslation || hasSource }

    /// Which recording to open with: the translated one is what's under review.
    var preferred: URL? { translated ?? source }
}

/// A queue row. The status endpoint reports one language's state for every
/// devotional date; the text and audio behind it load only when the day is opened.
nonisolated struct TranslationSummary: Identifiable, Hashable, Sendable {
    /// `DD/MM/YYYY`, exactly as the devotional table spells it.
    let date: String
    let lang: String
    var status: ReviewStatus
    var note: String?
    /// The text was edited after the audio was voiced, so the narration is behind.
    var audioStale: Bool
    /// Machine-flagged worries, e.g. "scripture" when the passage was auto-matched.
    var needsReview: [String]

    var id: String { "\(lang)|\(date)" }

    /// The routes take `DD-MM-YYYY` and the column stores `DD/MM/YYYY`.
    var pathDate: String { date.replacingOccurrences(of: "/", with: "-") }

    var day: CalendarDay? { CalendarDay(devotional: date) }

    var dayLabel: String {
        guard let day else { return date }
        if day.isToday { return "Today" }
        return AdminDates.short(day.date())
    }

    var dayLabelLong: String {
        guard let day else { return date }
        if day.isToday { return "Today" }
        return AdminDates.long(day.date())
    }
}

/// Everything the review screen shows for one day: the fields side by side, and
/// the recordings to listen to before deciding.
nonisolated struct TranslationDetail: Hashable, Sendable {
    var status: ReviewStatus
    var note: String?
    var audioStale: Bool
    let fields: [TranslationField]
    let tracks: [AudioTrack]
    let voice: String?
    let translatedAt: Date?
    let reviewedBy: String?

    var recordedLabel: String? {
        guard let translatedAt else { return nil }
        return AdminDates.whenLabel(translatedAt)
    }
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

    // MARK: Translations
    //
    // These fixtures are wire shapes, not domain objects, so the stub server and
    // the seeded store both reach the screens through the same mapping the live
    // path uses. Domain-shaped fixtures would let that mapping rot unnoticed.
    //
    // Only devotionals are here because only devotionals are translated: the
    // review queue has no notice or recurring rows to show.

    /// The devotional table's spelling of a day, "20/09/2026".
    static func devotionalDate(_ offset: Int) -> String {
        let d = CalendarDay.today.adding(days: offset)
        return String(format: "%02d/%02d/%04d", d.day, d.month, d.year)
    }

    private static func statusRow(_ date: String, _ status: String,
                                  note: String? = nil, stale: Bool = false,
                                  needsReview: [String] = []) -> TranslationStatusDTO.Row {
        TranslationStatusDTO.Row(id: "devo-\(date)", date: date, status: status,
                                 audioStale: stale, needsReview: needsReview, reviewNote: note)
    }

    static func translationStatus(_ lang: String) -> TranslationStatusDTO {
        switch lang {
        case "fr":
            return TranslationStatusDTO(lang: "fr", dates: [
                statusRow(devotionalDate(0), "draft", needsReview: ["scripture"]),
                statusRow(devotionalDate(-1), "draft", stale: true),
                statusRow(devotionalDate(-2), "rejected",
                          note: "Use \u{201C}le tombeau\u{201D} in the title — \u{201C}la pierre\u{201D} loses the sense of a grave marker."),
                statusRow(devotionalDate(-3), "approved"),
                // A day nobody has translated. The mapping drops it.
                statusRow(devotionalDate(-4), "none"),
            ])
        default:
            return TranslationStatusDTO(lang: "es", dates: [
                statusRow(devotionalDate(0), "draft"),
                statusRow(devotionalDate(-2), "approved"),
                statusRow(devotionalDate(-4), "none"),
            ])
        }
    }

    private static let englishSource = TranslationSourceDTO(
        title: "The Stone Still Speaks",
        verse: "John 11:23\u{2013}26",
        scripture: "Jesus said to her, \u{201C}Your brother will rise again.\u{201D} Martha answered, \u{201C}I know he will rise again in the resurrection at the last day.\u{201D}",
        declarations: "I am held by the One who is the resurrection. My grief is not the last word over my house.",
        prayers: [
            "For a faith that is present tense",
            "For the grief we still carry",
            "For the households waiting on an answer",
            "For courage to roll the stone away",
            "For the ones who came to mourn and stayed to believe",
        ],
        paragraphs: [
            "Martha met Jesus with a sentence that carried both faith and grief. She believed in a resurrection far away, at the last day. He moved it closer.",
            "There is a kind of belief that is safe because it is distant. It costs nothing to agree that God will act eventually.",
            "The stone was still in place when he spoke. That is where faith usually has to stand.",
        ]
    )

    private static func entry(_ status: String, note: String? = nil, stale: Bool = false,
                              voice: String, title: String, verse: String, scripture: String,
                              declarations: String, prayers: [String], paragraphs: [String],
                              needsReview: [String] = []) -> TranslationEntryDTO {
        TranslationEntryDTO(
            status: status, audioStale: stale, title: title, verse: verse, scripture: scripture,
            declarations: declarations, prayers: prayers, paragraphs: paragraphs,
            needsReview: needsReview,
            translatedAt: APIDate.string(Date().addingTimeInterval(-13 * 3600)),
            voice: voice, ttsModel: "gemini-tts", reviewNote: note,
            reviewedBy: status == "draft" ? nil : "franklin@acirid.ge",
            reviewedAt: status == "draft" ? nil : APIDate.string(Date().addingTimeInterval(-2 * 3600))
        )
    }

    private static let frenchEntry = entry(
        "draft", voice: "Studio \u{00B7} Am\u{00E9}lie",
        title: "La pierre parle encore",
        verse: "Jean 11:23\u{2013}26",
        scripture: "J\u{00E9}sus lui dit : \u{00AB} Ton fr\u{00E8}re ressuscitera. \u{00BB} Marthe r\u{00E9}pondit : \u{00AB} Je sais qu\u{2019}il ressuscitera \u{00E0} la r\u{00E9}surrection, au dernier jour. \u{00BB}",
        declarations: "Je suis tenu par Celui qui est la r\u{00E9}surrection. Mon chagrin n\u{2019}est pas le dernier mot sur ma maison.",
        prayers: [
            "Pour une foi au pr\u{00E9}sent",
            "Pour le chagrin que nous portons encore",
            "Pour les foyers qui attendent une r\u{00E9}ponse",
            "Pour le courage de rouler la pierre",
            "Pour ceux qui sont venus pleurer et sont rest\u{00E9}s pour croire",
        ],
        paragraphs: [
            "Marthe rencontra J\u{00E9}sus avec une phrase qui portait \u{00E0} la fois la foi et le chagrin. Elle croyait en une r\u{00E9}surrection lointaine, au dernier jour. Il l\u{2019}a rapproch\u{00E9}e.",
            "Il existe une forme de croyance qui reste confortable parce qu\u{2019}elle est lointaine. Il n\u{2019}en co\u{00FB}te rien d\u{2019}admettre que Dieu agira un jour.",
            "La pierre \u{00E9}tait encore en place lorsqu\u{2019}il a parl\u{00E9}. C\u{2019}est l\u{00E0} que la foi doit g\u{00E9}n\u{00E9}ralement se tenir.",
        ],
        needsReview: ["scripture"]
    )

    private static let spanishEntry = entry(
        "draft", voice: "Studio \u{00B7} Mateo",
        title: "La piedra a\u{00FA}n habla",
        verse: "Juan 11:23\u{2013}26",
        scripture: "Jes\u{00FA}s le dijo: \u{00AB}Tu hermano resucitar\u{00E1}\u{00BB}. Marta respondi\u{00F3}: \u{00AB}S\u{00E9} que resucitar\u{00E1} en la resurrecci\u{00F3}n, en el \u{00FA}ltimo d\u{00ED}a\u{00BB}.",
        declarations: "Soy sostenido por Aquel que es la resurrecci\u{00F3}n. Mi dolor no es la \u{00FA}ltima palabra sobre mi casa.",
        prayers: [
            "Por una fe en tiempo presente",
            "Por el dolor que a\u{00FA}n llevamos",
            "Por los hogares que esperan una respuesta",
            "Por el valor de remover la piedra",
            "Por quienes vinieron a llorar y se quedaron a creer",
        ],
        paragraphs: [
            "Marta se encontr\u{00F3} con Jes\u{00FA}s con una frase que llevaba fe y dolor a la vez. Ella cre\u{00ED}a en una resurrecci\u{00F3}n lejana, en el \u{00FA}ltimo d\u{00ED}a. \u{00C9}l la acerc\u{00F3}.",
            "Hay una clase de fe que resulta c\u{00F3}moda porque est\u{00E1} lejos. No cuesta nada aceptar que Dios actuar\u{00E1} alg\u{00FA}n d\u{00ED}a.",
            "La piedra segu\u{00ED}a en su lugar cuando \u{00E9}l habl\u{00F3}. Ah\u{00ED} es donde la fe suele tener que sostenerse.",
        ]
    )

    /// Keyed the same way `TranslationSummary.id` is: "lang|DD/MM/YYYY".
    static var translationDetails: [String: TranslationDetailDTO] {
        var out: [String: TranslationDetailDTO] = [:]
        func put(_ lang: String, _ offset: Int, _ entry: TranslationEntryDTO) {
            let date = devotionalDate(offset)
            out["\(lang)|\(date)"] = TranslationDetailDTO(
                id: "devo-\(date)", date: date, lang: lang,
                translation: entry, source: englishSource
            )
        }
        put("fr", 0, frenchEntry)
        put("fr", -1, entry("draft", stale: true, voice: "Studio \u{00B7} Am\u{00E9}lie",
                            title: "Une lampe pour le chemin", verse: "Psaume 119:105",
                            scripture: "Ta parole est une lampe \u{00E0} mes pieds, et une lumi\u{00E8}re sur mon sentier.",
                            declarations: "Je marche dans la lumi\u{00E8}re que j\u{2019}ai re\u{00E7}ue.",
                            prayers: ["Pour la lumi\u{00E8}re du jour", "Pour un pas de plus"],
                            paragraphs: ["La lampe n\u{2019}\u{00E9}claire pas la route enti\u{00E8}re. Elle \u{00E9}claire le pas suivant."]))
        put("fr", -2, entry("rejected",
                            note: "Use \u{201C}le tombeau\u{201D} in the title \u{2014} \u{201C}la pierre\u{201D} loses the sense of a grave marker.",
                            voice: "Studio \u{00B7} Am\u{00E9}lie",
                            title: "La pierre parle encore", verse: "Jean 11:23\u{2013}26",
                            scripture: "J\u{00E9}sus lui dit : \u{00AB} Ton fr\u{00E8}re ressuscitera. \u{00BB}",
                            declarations: "Je suis tenu par Celui qui est la r\u{00E9}surrection.",
                            prayers: ["Pour une foi au pr\u{00E9}sent"],
                            paragraphs: ["Marthe rencontra J\u{00E9}sus avec une phrase qui portait la foi et le chagrin."]))
        put("fr", -3, entry("approved", voice: "Studio \u{00B7} Am\u{00E9}lie",
                            title: "La Lampe du jour", verse: "Psaume 63:1",
                            scripture: "\u{00D4} Dieu, tu es mon Dieu, je te cherche d\u{00E8}s l\u{2019}aube.",
                            declarations: "Je cherche Dieu le premier.",
                            prayers: ["Pour un matin donn\u{00E9} \u{00E0} Dieu"],
                            paragraphs: ["Le matin d\u{00E9}cide souvent du reste."]))
        put("es", 0, spanishEntry)
        put("es", -2, entry("approved", voice: "Studio \u{00B7} Mateo",
                            title: "La l\u{00E1}mpara de hoy", verse: "Salmo 63:1",
                            scripture: "Oh Dios, t\u{00FA} eres mi Dios; te busco de madrugada.",
                            declarations: "Busco a Dios primero.",
                            prayers: ["Por una ma\u{00F1}ana entregada a Dios"],
                            paragraphs: ["La ma\u{00F1}ana suele decidir el resto."]))
        return out
    }

    /// A day's recordings. Deliberately several files, with an English twin for
    /// each and a shared music bed — one prayer per file is how the worker writes
    /// them, so a day with five prayers is seven recordings plus the bed.
    static var translationAudio: [String: TranslationAudioDTO] {
        func bag(_ lang: String, prayers: Int, declarations: Bool = true, bed: Bool = true) -> [String: String] {
            let root = "https://stub.local/audio/\(lang)"
            var urls = ["main": "\(root)/main.mp3", "source_main": "https://stub.local/audio/en/main.mp3"]
            if declarations {
                urls["declaration"] = "\(root)/declaration.mp3"
                urls["source_declaration"] = "https://stub.local/audio/en/declaration.mp3"
            }
            for i in 1...max(prayers, 0) where prayers > 0 {
                urls["prayer_\(i)"] = "\(root)/prayer_\(i).mp3"
                urls["source_prayer_\(i)"] = "https://stub.local/audio/en/prayer_\(i).mp3"
            }
            if bed { urls["background"] = "https://stub.local/audio/bed.mp3" }
            return urls
        }
        func make(_ lang: String, _ offset: Int, _ urls: [String: String]) -> (String, TranslationAudioDTO) {
            let date = devotionalDate(offset)
            return ("\(lang)|\(date)",
                    TranslationAudioDTO(id: "devo-\(date)", date: date, lang: lang,
                                        expiresIn: 3600, urls: urls))
        }
        return Dictionary(uniqueKeysWithValues: [
            make("fr", 0, bag("fr", prayers: 5)),
            make("fr", -1, bag("fr", prayers: 2, declarations: false)),
            make("fr", -2, bag("fr", prayers: 1)),
            make("fr", -3, bag("fr", prayers: 1)),
            make("es", 0, bag("es", prayers: 5)),
            make("es", -2, bag("es", prayers: 1, bed: false)),
        ])
    }
}
