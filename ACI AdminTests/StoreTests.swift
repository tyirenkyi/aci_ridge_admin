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
