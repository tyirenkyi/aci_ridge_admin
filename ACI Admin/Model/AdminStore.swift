//
//  AdminStore.swift
//  ACI Admin
//
//  Everything the console knows, and every write it makes.
//
//  Two kinds of method live here on purpose:
//
//  * Throwing ones (create/update/send/save) — a compose screen has to react, so it
//    stays open on failure and dismisses only on success.
//  * Non-throwing ones (setRuleActive, setSkip) — ambient row actions. They apply
//    optimistically, roll back if the server disagrees, and say so in a toast, so a
//    list row needs no error plumbing of its own.
//

import Foundation
import Observation

struct Toast: Equatable, Identifiable, Sendable {
    enum Kind: Sendable { case success, error }
    let id = UUID()
    var message: String
    var kind: Kind = .success
}

/// Row-level work in flight. Rows can't hold their own state across a re-render.
enum BusyKey: Hashable, Sendable {
    case rule(String)
    case skip(String, CalendarDay)
    case event(String)
}

@Observable
final class AdminStore {
    private let api: any AdminAPI
    /// Called when a 401 outlives the client's one refresh attempt.
    private let onAuthFailure: () -> Void

    /// `seeded` starts with the fixtures already in place instead of loading them.
    /// The click-through UI test needs that: a spinner that is still animating keeps
    /// XCUITest waiting for the app to go idle before every single interaction.
    init(api: any AdminAPI, onAuthFailure: @escaping () -> Void = {}, seeded: Bool = false) {
        self.api = api
        self.onAuthFailure = onAuthFailure
        guard seeded else { return }
        noticesState = .loaded(SampleData.notices)
        rulesState = .loaded(SampleData.recurring)
        eventsState = .loaded(SampleData.events)
        for rule in SampleData.recurring {
            occurrencesState[rule.id] = .loaded(
                rule.occurrences(count: 10).map {
                    RuleOccurrence(day: $0.day, time: rule.sendTime, skipped: rule.isSkipped($0.day))
                }
            )
        }
        // Reviews are seeded through the same wire → domain mapping the live path
        // uses, details included: a spinner that is still turning stops the app
        // reporting itself idle, and XCUITest waits on that before every tap.
        let details = SampleData.translationDetails
        let audio = SampleData.translationAudio
        for lang in Language.all {
            let rows = SampleData.translationStatus(lang.value).summaries
            reviewQueues[lang.value] = .loaded(rows)
            for row in rows {
                guard let dto = details[row.id] else { continue }
                reviewDetails[row.id] = .loaded(TranslationDetail(dto, audio: audio[row.id]))
            }
        }
        lastLoaded = Date()
    }

    // MARK: State

    private(set) var noticesState: Loadable<[Notice]> = .idle
    private(set) var rulesState: Loadable<[RecurringRule]> = .idle
    private(set) var eventsState: Loadable<[ChurchEvent]> = .idle
    private(set) var occurrencesState: [RecurringRule.ID: Loadable<[RuleOccurrence]>] = [:]

    /// Plain reads for the many places that only want the rows.
    var notices: [Notice] { noticesState.value ?? [] }
    var recurring: [RecurringRule] { rulesState.value ?? [] }
    var events: [ChurchEvent] { eventsState.value ?? [] }

    /// The review queue, keyed by language value. Each tab loads and fails on its
    /// own, so a dead Spanish request never blanks the French one.
    ///
    /// Only devotionals appear here: the server translates the daily devotional and
    /// nothing else, so notices and recurring rules have no review state to fetch.
    private(set) var reviewQueues: [String: Loadable<[TranslationSummary]>] = [:]
    /// One day's text and recordings, keyed by `TranslationSummary.ID`. Fetched
    /// only when a day is opened — the queue is metadata, and the corpus is every
    /// devotional the church has ever published.
    private(set) var reviewDetails: [TranslationSummary.ID: Loadable<TranslationDetail>] = [:]
    var reviewLanguage: Language = .french

    private(set) var busy: Set<BusyKey> = []
    private(set) var toast: Toast?
    private var toastTask: Task<Void, Never>?
    private var lastLoaded: Date?

    func isBusy(_ key: BusyKey) -> Bool { busy.contains(key) }

    // MARK: Derived

    /// Today's outbound queue. There is no queue endpoint — it's the notices due
    /// today plus the rules that fire today, which we already hold.
    var queue: [QueueItem] {
        let today = CalendarDay.today
        let now = TimeOfDay(Date())
        var rows: [(TimeOfDay, QueueItem)] = []

        for notice in notices {
            if let sentAt = notice.sentAt, CalendarDay(sentAt) == today {
                let time = TimeOfDay(sentAt)
                rows.append((time, QueueItem(id: notice.id, time: time.display, title: notice.title,
                                             sender: notice.sender, state: .sent, recurring: false)))
            } else if notice.status == .scheduled, let at = notice.scheduledAt, CalendarDay(at) == today {
                let time = TimeOfDay(at)
                rows.append((time, QueueItem(id: notice.id, time: time.display, title: notice.title,
                                             sender: notice.sender, state: .pending, recurring: false)))
            }
        }

        for rule in recurring where rule.active && !rule.isSkipped(today) {
            let firesToday = rule.nextOccurrence == today
                || (rule.nextOccurrence == nil && rule.occurrences(count: 1).first?.day == today)
            guard firesToday else { continue }
            rows.append((rule.sendTime,
                         QueueItem(id: rule.id, time: rule.sendTime.display, title: rule.title,
                                   sender: rule.sender,
                                   state: rule.sendTime <= now ? .sent : .pending,
                                   recurring: true)))
        }

        return rows.sorted { $0.0 < $1.0 }.map(\.1)
    }

    func reviewQueue(_ lang: Language) -> Loadable<[TranslationSummary]> {
        reviewQueues[lang.value] ?? .idle
    }

    func reviewRows(_ lang: Language) -> [TranslationSummary] {
        reviewQueue(lang).value ?? []
    }

    func reviewDetail(_ id: TranslationSummary.ID) -> Loadable<TranslationDetail> {
        reviewDetails[id] ?? .idle
    }

    func pendingCount(_ lang: Language) -> Int {
        reviewRows(lang).filter { $0.status == .pending }.count
    }

    var pendingTotal: Int { Language.all.reduce(0) { $0 + pendingCount($1) } }

    func rule(_ id: RecurringRule.ID) -> RecurringRule? { recurring.first { $0.id == id } }
    func notice(_ id: Notice.ID) -> Notice? { notices.first { $0.id == id } }
    func event(_ id: ChurchEvent.ID) -> ChurchEvent? { events.first { $0.id == id } }

    func summary(_ id: TranslationSummary.ID) -> TranslationSummary? {
        reviewQueues.values.compactMap(\.value).joined().first { $0.id == id }
    }

    // MARK: Loading

    func loadAll(force: Bool = false) async {
        async let notices: Void = loadNotices(force: force)
        async let rules: Void = loadRules(force: force)
        async let events: Void = loadEvents(force: force)
        // Both languages, because the tab badge counts them together.
        async let reviews: Void = loadReviews(force: force)
        _ = await (notices, rules, events, reviews)
        lastLoaded = Date()
    }

    /// Called when the console comes back to the foreground.
    func refreshIfStale(after seconds: TimeInterval = 60) async {
        guard let lastLoaded else { return await loadAll() }
        if Date().timeIntervalSince(lastLoaded) > seconds {
            await loadAll(force: true)
        }
    }

    func loadNotices(force: Bool = false) async {
        guard force || !noticesState.hasLoaded else { return }
        noticesState.beginRefresh()
        do {
            let rows = try await perform { try await api.notices(status: nil, limit: 200) }
            noticesState = .loaded(rows.map(\.domain))
        } catch {
            noticesState.fail(error)
        }
    }

    func loadRules(force: Bool = false) async {
        guard force || !rulesState.hasLoaded else { return }
        rulesState.beginRefresh()
        do {
            let rows = try await perform { try await api.rules() }
            rulesState = .loaded(rows.map(\.domain))
        } catch {
            rulesState.fail(error)
        }
    }

    func loadEvents(force: Bool = false) async {
        guard force || !eventsState.hasLoaded else { return }
        eventsState.beginRefresh()
        do {
            let rows = try await perform { try await api.events() }
            eventsState = .loaded(rows.map(\.domain))
        } catch {
            eventsState.fail(error)
        }
    }

    /// The authoritative schedule for a saved rule, skip flags included.
    func loadOccurrences(_ id: RecurringRule.ID, count: Int = 10, force: Bool = false) async {
        var state = occurrencesState[id] ?? .idle
        guard force || !state.hasLoaded else { return }
        state.beginRefresh()
        occurrencesState[id] = state
        do {
            let dto = try await perform { try await api.occurrences(id, count: count) }
            occurrencesState[id] = .loaded(dto.domain)
        } catch {
            state.fail(error)
            occurrencesState[id] = state
        }
    }

    // MARK: Review

    func loadReviews(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for lang in Language.all {
                group.addTask { await self.loadReview(lang, force: force) }
            }
        }
    }

    func loadReview(_ lang: Language, force: Bool = false) async {
        var state = reviewQueue(lang)
        guard force || !state.hasLoaded else { return }
        state.beginRefresh()
        reviewQueues[lang.value] = state
        do {
            let dto = try await perform { try await api.translationStatus(lang: lang.value) }
            reviewQueues[lang.value] = .loaded(dto.summaries)
        } catch {
            state.fail(error)
            reviewQueues[lang.value] = state
        }
    }

    /// The text and the recordings for one day. They are two requests: the signed
    /// URLs can fail on their own (storage, an expired key) without taking the text
    /// with them, and a reviewer can still read a draft they can't listen to.
    func loadReviewDetail(_ id: TranslationSummary.ID, force: Bool = false) async {
        guard let summary = summary(id) else { return }
        var state = reviewDetail(id)
        guard force || !state.hasLoaded else { return }
        state.beginRefresh()
        reviewDetails[id] = state
        do {
            let detail = try await perform { [api] in
                async let text = api.translation(date: summary.pathDate, lang: summary.lang)
                async let audio = try? await api.translationAudio(date: summary.pathDate, lang: summary.lang)
                return TranslationDetail(try await text, audio: await audio)
            }
            reviewDetails[id] = .loaded(detail)
        } catch {
            state.fail(error)
            reviewDetails[id] = state
        }
    }

    /// Approve or send back. A rejection carries the note the server insists on:
    /// it refuses a rejection without one, so the translator always knows why.
    func decide(_ id: TranslationSummary.ID, _ status: ReviewStatus, note: String = "") async throws(APIError) {
        guard let summary = summary(id) else {
            throw APIError.notFound("That day isn't in the review queue any more.")
        }
        var patch = PatchBody()
        patch.set("status", status.wire)
        if status == .rejected { patch.set("review_note", note.trimmed) }

        let result = try await perform {
            try await api.reviewTranslation(date: summary.pathDate, lang: summary.lang, patch)
        }
        apply(result.translation, to: id, lang: summary.lang)
    }

    private func apply(_ entry: TranslationEntryDTO, to id: TranslationSummary.ID, lang: String) {
        if var rows = reviewQueues[lang]?.value,
           let i = rows.firstIndex(where: { $0.id == id }) {
            if let status = entry.status.flatMap(ReviewStatus.init(wire:)) { rows[i].status = status }
            rows[i].note = entry.reviewNote
            if let stale = entry.audioStale { rows[i].audioStale = stale }
            reviewQueues[lang] = .loaded(rows)
        }
        if let detail = reviewDetails[id]?.value {
            reviewDetails[id] = .loaded(detail.applying(entry))
        }
    }

    // MARK: Notices

    func createNotice(_ draft: NoticeDraft, scheduled: Bool) async throws(APIError) -> Notice {
        let dto = try await perform { try await api.createNotice(draft.createBody(scheduled: scheduled)) }
        let notice = dto.domain
        upsert(notice)
        return notice
    }

    func updateNotice(_ id: Notice.ID, to draft: NoticeDraft, status: NoticeStatus?) async throws(APIError) -> Notice {
        guard let original = notice(id) else {
            throw APIError.notFound("That notice isn't here any more.")
        }
        let patch = draft.patch(from: original, status: status)
        guard !patch.isEmpty else { return original }
        let dto = try await perform { try await api.updateNotice(id, patch) }
        let notice = dto.domain
        upsert(notice)
        return notice
    }

    /// Sends an existing notice. A 409 means it already went out, which is the
    /// outcome the admin wanted — reconcile rather than shout.
    func sendNotice(_ id: Notice.ID) async throws(APIError) -> Notice {
        do {
            let result = try await perform { try await api.sendNotice(id) }
            let notice = result.notice.domain
            upsert(notice)
            return notice
        } catch {
            if case .conflict = error {
                await loadNotices(force: true)
                if let existing = notice(id) { return existing }
            }
            throw error
        }
    }

    func deleteNotice(_ id: Notice.ID) async throws(APIError) {
        try await perform { try await api.deleteNotice(id) }
        if var rows = noticesState.value {
            rows.removeAll { $0.id == id }
            noticesState = .loaded(rows)
        }
    }

    private func upsert(_ notice: Notice) {
        var rows = noticesState.value ?? []
        if let i = rows.firstIndex(where: { $0.id == notice.id }) {
            rows[i] = notice
        } else {
            rows.insert(notice, at: 0)
        }
        noticesState = .loaded(rows)
    }

    // MARK: Rules

    func saveRule(_ draft: RuleDraft, id: RecurringRule.ID?, active: Bool) async throws(APIError) -> RecurringRule {
        let body = draft.body(active: active)
        if let id {
            let dto = try await perform { try await api.updateRule(id, .definition(body)) }
            let rule = dto.domain
            upsert(rule)
            return rule
        }
        let dto = try await perform { try await api.createRule(body) }
        let rule = dto.domain
        upsert(rule)
        // A create response selects `*` without the skips embed, so the skip list it
        // carries is empty rather than true. Reconcile before anyone reads it.
        await loadRules(force: true)
        return self.rule(rule.id) ?? rule
    }

    func deleteRule(_ id: RecurringRule.ID) async throws(APIError) {
        try await perform { try await api.deleteRule(id) }
        if var rows = rulesState.value {
            rows.removeAll { $0.id == id }
            rulesState = .loaded(rows)
        }
        occurrencesState[id] = nil
    }

    /// Optimistic. The row flips at once and goes back if the server refuses.
    func setRuleActive(_ id: RecurringRule.ID, _ active: Bool) async {
        guard var rows = rulesState.value,
              let index = rows.firstIndex(where: { $0.id == id }),
              rows[index].active != active
        else { return }

        let previous = rows[index].active
        rows[index].active = active
        rulesState = .loaded(rows)

        busy.insert(.rule(id))
        defer { busy.remove(.rule(id)) }

        do {
            let dto = try await perform { try await api.updateRule(id, .activation(active)) }
            upsert(dto.domain)
        } catch {
            // Re-find by id: a refresh may have replaced the array while we waited.
            if var current = rulesState.value,
               let i = current.firstIndex(where: { $0.id == id }) {
                current[i].active = previous
                rulesState = .loaded(current)
            }
            flashError(error)
        }
    }

    /// Optimistic skip/restore, updating both the rule's skip set and the occurrence
    /// row the schedule screen is showing.
    func setSkip(_ id: RecurringRule.ID, day: CalendarDay, skipped: Bool) async {
        guard let ruleIndex = rulesState.value?.firstIndex(where: { $0.id == id }) else { return }
        let previousSkips = rulesState.value?[ruleIndex].skips ?? []
        applySkip(id, day: day, skipped: skipped)
        flash(skipped ? "Date skipped — nothing will send" : "Date restored")

        busy.insert(.skip(id, day))
        defer { busy.remove(.skip(id, day)) }

        do {
            if skipped {
                try await perform { try await api.addSkip(id, day: day) }
            } else {
                try await perform { try await api.removeSkip(id, day: day) }
            }
        } catch {
            // The state we wanted already holds: adding a skip that exists conflicts,
            // removing one that doesn't is a 404. Either way there is nothing to undo.
            let alreadyDone = (skipped && error.isConflict) || (!skipped && error.isNotFound)
            guard !alreadyDone else { return }

            if var rows = rulesState.value, let i = rows.firstIndex(where: { $0.id == id }) {
                rows[i].skips = previousSkips
                rulesState = .loaded(rows)
            }
            applyOccurrenceSkip(id, day: day, skipped: !skipped)
            flashError(error)
        }
    }

    private func applySkip(_ id: RecurringRule.ID, day: CalendarDay, skipped: Bool) {
        if var rows = rulesState.value, let i = rows.firstIndex(where: { $0.id == id }) {
            if skipped { rows[i].skips.insert(day) } else { rows[i].skips.remove(day) }
            rulesState = .loaded(rows)
        }
        applyOccurrenceSkip(id, day: day, skipped: skipped)
    }

    private func applyOccurrenceSkip(_ id: RecurringRule.ID, day: CalendarDay, skipped: Bool) {
        guard var rows = occurrencesState[id]?.value,
              let i = rows.firstIndex(where: { $0.day == day })
        else { return }
        rows[i].skipped = skipped
        occurrencesState[id] = .loaded(rows)
    }

    private func upsert(_ rule: RecurringRule) {
        var rows = rulesState.value ?? []
        if let i = rows.firstIndex(where: { $0.id == rule.id }) {
            // A create/replace response can carry an empty skip list; keep what we know.
            var incoming = rule
            if incoming.skips.isEmpty { incoming.skips = rows[i].skips }
            rows[i] = incoming
        } else {
            rows.insert(rule, at: 0)
        }
        rulesState = .loaded(rows)
    }

    // MARK: Events

    func saveEvent(_ draft: EventDraft, id: ChurchEvent.ID?, status: EventStatus) async throws(APIError) -> ChurchEvent {
        if let id, let original = event(id) {
            let patch = draft.patch(from: original, status: status)
            guard !patch.isEmpty else { return original }
            let dto = try await perform { try await api.updateEvent(id, patch) }
            let event = dto.domain
            upsert(event)
            return event
        }
        let dto = try await perform { try await api.createEvent(draft.body(status: status)) }
        let event = dto.domain
        upsert(event)
        return event
    }

    /// Publishing and unpublishing are both just a status change.
    func setEventStatus(_ id: ChurchEvent.ID, _ status: EventStatus) async throws(APIError) -> ChurchEvent {
        var patch = PatchBody()
        patch.set("status", status.rawValue)
        let dto = try await perform { try await api.updateEvent(id, patch) }
        let event = dto.domain
        upsert(event)
        return event
    }

    func deleteEvent(_ id: ChurchEvent.ID) async throws(APIError) {
        try await perform { try await api.deleteEvent(id) }
        if var rows = eventsState.value {
            rows.removeAll { $0.id == id }
            eventsState = .loaded(rows)
        }
    }

    private func upsert(_ event: ChurchEvent) {
        var rows = eventsState.value ?? []
        if let i = rows.firstIndex(where: { $0.id == event.id }) {
            rows[i] = event
        } else {
            rows.append(event)
            rows.sort { $0.startsAt < $1.startsAt }
        }
        eventsState = .loaded(rows)
    }

    // MARK: Toasts

    func flash(_ message: String, kind: Toast.Kind = .success) {
        toastTask?.cancel()
        toast = Toast(message: message, kind: kind)
        // Under UI testing the toast stays until something replaces it. XCUITest
        // waits for the app to be idle after a tap, which outlasts the real timeout,
        // so an auto-dismissing toast can never be asserted on.
        guard !APIConfig.isUITesting else { return }
        let seconds = kind == .error ? 3.5 : 2.2
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func flashError(_ error: APIError) {
        flash(error.message, kind: .error)
    }

    // MARK: Auth plumbing

    /// Every request goes through here so the session — not the stateless client —
    /// gets to decide what a dead token means.
    private func perform<T>(_ work: () async throws -> T) async throws(APIError) -> T {
        do {
            return try await work()
        } catch let error as APIError {
            if error.isAuthFailure { onAuthFailure() }
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }
}

private extension APIError {
    var isConflict: Bool { if case .conflict = self { return true }; return false }
    var isNotFound: Bool { if case .notFound = self { return true }; return false }
}
