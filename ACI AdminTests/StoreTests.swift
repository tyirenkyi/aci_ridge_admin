//
//  StoreTests.swift
//  ACI AdminTests
//
//  The store's optimistic paths, where a wrong rollback would quietly show the admin
//  a state the server doesn't agree with.
//

import Foundation
import Testing
@testable import ACI_Admin

/// Fails every call with a chosen error, so rollback can be observed.
private actor FailingAPI: AdminAPI {
    let error: APIError
    /// Calls that should still succeed, so a test can get data loaded first.
    let base = StubAPI()

    init(error: APIError) { self.error = error }

    func me() async throws -> MeDTO { try await base.me() }
    func notices(status: String?, limit: Int) async throws -> [NoticeDTO] {
        try await base.notices(status: status, limit: limit)
    }
    func notice(_ id: String) async throws -> NoticeDTO { try await base.notice(id) }
    func createNotice(_ body: NoticeBody) async throws -> NoticeDTO { throw error }
    func updateNotice(_ id: String, _ patch: PatchBody) async throws -> NoticeDTO { throw error }
    func deleteNotice(_ id: String) async throws { throw error }
    func sendNotice(_ id: String) async throws -> SendResultDTO { throw error }

    func rules() async throws -> [RuleDTO] { try await base.rules() }
    func rule(_ id: String) async throws -> RuleDTO { try await base.rule(id) }
    func createRule(_ body: RuleBody) async throws -> RuleDTO { throw error }
    func updateRule(_ id: String, _ patch: RulePatch) async throws -> RuleDTO { throw error }
    func deleteRule(_ id: String) async throws { throw error }
    func occurrences(_ id: String, count: Int) async throws -> OccurrencesDTO {
        try await base.occurrences(id, count: count)
    }
    func addSkip(_ id: String, day: CalendarDay) async throws { throw error }
    func removeSkip(_ id: String, day: CalendarDay) async throws { throw error }

    func translationStatus(lang: String) async throws -> TranslationStatusDTO {
        try await base.translationStatus(lang: lang)
    }
    func translation(date: String, lang: String) async throws -> TranslationDetailDTO {
        try await base.translation(date: date, lang: lang)
    }
    func translationAudio(date: String, lang: String) async throws -> TranslationAudioDTO {
        try await base.translationAudio(date: date, lang: lang)
    }
    func reviewTranslation(date: String, lang: String, _ patch: PatchBody) async throws -> TranslationPatchResultDTO {
        throw error
    }

    func events() async throws -> [EventDTO] { try await base.events() }
    func createEvent(_ body: EventBody) async throws -> EventDTO { throw error }
    func updateEvent(_ id: String, _ patch: PatchBody) async throws -> EventDTO { throw error }
    func deleteEvent(_ id: String) async throws { throw error }
}

@Suite("AdminStore")
@MainActor
struct AdminStoreTests {

    @Test func loadsEveryAreaFromTheAPI() async {
        let store = AdminStore(api: StubAPI())
        await store.loadAll()
        #expect(store.notices.count == 3)
        #expect(store.recurring.count == 4)
        #expect(store.events.count == 3)
        #expect(store.noticesState.hasLoaded)
    }

    @Test func rollsBackARuleToggleTheServerRefuses() async {
        let store = AdminStore(api: FailingAPI(error: .conflict("Nope")))
        await store.loadRules()
        let rule = try! #require(store.recurring.first)
        let original = rule.active

        await store.setRuleActive(rule.id, !original)

        #expect(store.rule(rule.id)?.active == original)
        #expect(store.toast?.kind == .error)
        #expect(store.toast?.message == "Nope")
    }

    @Test func keepsASuccessfulRuleToggle() async {
        let store = AdminStore(api: StubAPI())
        await store.loadRules()
        let rule = try! #require(store.recurring.first)
        let original = rule.active

        await store.setRuleActive(rule.id, !original)

        #expect(store.rule(rule.id)?.active == !original)
    }

    /// Adding a skip that already exists conflicts, and removing one that doesn't is
    /// a 404. Both mean the admin already has what they asked for, so the optimistic
    /// change must stand rather than snapping back.
    @Test func treatsAnAlreadyAppliedSkipAsSuccess() async {
        let store = AdminStore(api: FailingAPI(error: .conflict("Already skipped")))
        await store.loadRules()
        let rule = try! #require(store.recurring.first)
        let day = CalendarDay.today.adding(days: 5)

        await store.setSkip(rule.id, day: day, skipped: true)

        #expect(store.rule(rule.id)?.isSkipped(day) == true)
        #expect(store.toast?.kind == .success)
    }

    @Test func treatsAnAlreadyRemovedSkipAsSuccess() async {
        let store = AdminStore(api: FailingAPI(error: .notFound("That date wasn't skipped")))
        await store.loadRules()
        // r1 ships with a skip three days out.
        let rule = try! #require(store.recurring.first { !$0.skips.isEmpty })
        let day = try! #require(rule.skips.first)

        await store.setSkip(rule.id, day: day, skipped: false)

        #expect(store.rule(rule.id)?.isSkipped(day) == false)
    }

    @Test func rollsBackASkipOnARealFailure() async {
        let store = AdminStore(api: FailingAPI(error: .validation("Only upcoming dates can be skipped")))
        await store.loadRules()
        let rule = try! #require(store.recurring.first)
        let day = CalendarDay.today.adding(days: 4)

        await store.setSkip(rule.id, day: day, skipped: true)

        #expect(store.rule(rule.id)?.isSkipped(day) == false)
        #expect(store.toast?.message == "Only upcoming dates can be skipped")
    }

    @Test func reportsAnAuthFailureToTheSession() async {
        var signedOut = false
        let store = AdminStore(api: FailingAPI(error: .unauthorized("gone")),
                               onAuthFailure: { signedOut = true })
        await store.loadRules()
        _ = try? await store.sendNotice("n1")
        #expect(signedOut)
    }

    @Test func sendingSurfacesTheServerSentence() async {
        let store = AdminStore(api: FailingAPI(error: .validation("Scheduling a notice requires scheduled_at")))
        await store.loadNotices()
        await #expect(throws: APIError.validation("Scheduling a notice requires scheduled_at")) {
            try await store.createNotice(NoticeDraft(), scheduled: true)
        }
    }

    /// The queue has no endpoint — it is derived from notices and rules.
    @Test func derivesTodaysQueue() async {
        let store = AdminStore(api: StubAPI())
        await store.loadAll()
        // r1 is a daily rule, so it always fires today unless skipped.
        #expect(store.queue.contains { $0.recurring })
        #expect(store.queue == store.queue.sorted { lhs, rhs in
            store.queue.firstIndex(of: lhs)! < store.queue.firstIndex(of: rhs)!
        })
    }

    @Test func sendingANoticeMarksItSentAndRecordsOpens() async throws {
        let store = AdminStore(api: StubAPI())
        await store.loadNotices()
        let draft = try #require(store.notices.first { $0.status == .draft })

        let sent = try await store.sendNotice(draft.id)

        #expect(sent.status == .sent)
        #expect(store.notice(draft.id)?.status == .sent)
        #expect(sent.when.hasPrefix("Sent "))
    }

    @Test func refusesToEditASentNotice() async {
        let store = AdminStore(api: StubAPI())
        await store.loadNotices()
        let sent = try! #require(store.notices.first { $0.status == .sent })
        #expect(sent.isEditable == false)
        #expect(sent.opensLabel == "412 opened")
    }
}


@Suite("Translation review")
@MainActor
struct TranslationReviewTests {

    private func loadedStore() async -> AdminStore {
        let store = AdminStore(api: StubAPI())
        await store.loadReviews()
        return store
    }

    @Test func queueDropsDaysThatWereNeverTranslated() async {
        let store = await loadedStore()
        let rows = store.reviewRows(.french)
        // The fixture has five dates, one of them "none".
        #expect(rows.count == 4)
        #expect(!rows.contains { $0.date == SampleData.devotionalDate(-4) })
    }

    @Test func queueRunsNewestFirst() async {
        let store = await loadedStore()
        let days = store.reviewRows(.french).compactMap(\.day)
        #expect(days == days.sorted(by: >))
    }

    @Test func pendingCountsOnlyUndecidedDays() async {
        let store = await loadedStore()
        #expect(store.pendingCount(.french) == 2)
        #expect(store.pendingCount(.spanish) == 1)
        #expect(store.pendingTotal == 3)
    }

    @Test func detailPairsEveryPartWithItsEnglish() async {
        let store = await loadedStore()
        let id = "fr|" + SampleData.devotionalDate(0)
        await store.loadReviewDetail(id)
        let detail = store.reviewDetail(id).value
        let labels = detail?.fields.map(\.label) ?? []
        #expect(labels.prefix(4) == ["Title", "Verse", "Scripture", "Declarations"])
        #expect(labels.filter { $0.hasPrefix("Prayer") }.count == 5)
        #expect(labels.filter { $0.hasPrefix("Paragraph") }.count == 3)
        // Both sides present on every field the fixture fills in.
        #expect(detail?.fields.allSatisfy { !$0.source.isEmpty && !$0.draft.isEmpty } == true)
    }

    @Test func aDayIsSeveralRecordings() async {
        let store = await loadedStore()
        let id = "fr|" + SampleData.devotionalDate(0)
        await store.loadReviewDetail(id)
        let tracks = store.reviewDetail(id).value?.tracks ?? []
        // Narration, declarations, five prayers, and the shared bed.
        #expect(tracks.map(\.key) == ["main", "declaration", "prayer_1", "prayer_2",
                                      "prayer_3", "prayer_4", "prayer_5", "background"])
        // Every voiced part has an English twin to A/B against.
        #expect(tracks.filter { $0.key != "background" }.allSatisfy { $0.hasTranslation && $0.hasSource })
        // The music bed is language-neutral: one file, no translation.
        #expect(tracks.last?.hasTranslation == false)
        #expect(tracks.last?.hasSource == true)
    }

    @Test func prayersOrderNumericallyNotAlphabetically() {
        let dto = TranslationAudioDTO(
            id: "d", date: "20/09/2026", lang: "fr", expiresIn: 3600,
            urls: [
                "prayer_1": "https://x/1.mp3",
                "prayer_2": "https://x/2.mp3",
                "prayer_10": "https://x/10.mp3",
            ]
        )
        #expect(dto.tracks.map(\.key) == ["prayer_1", "prayer_2", "prayer_10"])
    }

    @Test func aPartWithNoRecordingIsLeftOut() {
        let dto = TranslationAudioDTO(
            id: "d", date: "20/09/2026", lang: "fr", expiresIn: 3600,
            urls: ["main": "https://x/main.mp3"]
        )
        #expect(dto.tracks.map(\.key) == ["main"])
        #expect(dto.tracks.first?.hasSource == false)
    }

    @Test func approvingMovesTheRowAndTheDetail() async throws {
        let store = await loadedStore()
        let id = "fr|" + SampleData.devotionalDate(0)
        await store.loadReviewDetail(id)
        try await store.decide(id, .approved)
        #expect(store.summary(id)?.status == .approved)
        #expect(store.reviewDetail(id).value?.status == .approved)
        #expect(store.pendingCount(.french) == 1)
    }

    @Test func rejectingKeepsTheNoteOnTheRow() async throws {
        let store = await loadedStore()
        let id = "fr|" + SampleData.devotionalDate(0)
        try await store.decide(id, .rejected, note: "  Use le tombeau.  ")
        #expect(store.summary(id)?.status == .rejected)
        #expect(store.summary(id)?.note == "Use le tombeau.")
    }

    @Test func aFailedDecisionLeavesTheRowAlone() async {
        let store = AdminStore(api: FailingAPI(error: .server("nope")))
        await store.loadReviews()
        let id = "fr|" + SampleData.devotionalDate(0)
        await #expect(throws: APIError.self) {
            try await store.decide(id, .approved)
        }
        #expect(store.summary(id)?.status == .pending)
    }

    @Test func devotionalDatesParseBackToDays() {
        #expect(CalendarDay(devotional: "20/09/2026") == CalendarDay(year: 2026, month: 9, day: 20))
        #expect(CalendarDay(devotional: "2026-09-20") == nil)
        #expect(CalendarDay(devotional: "5/9/2026") == nil)
    }
}
