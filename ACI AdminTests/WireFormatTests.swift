//
//  WireFormatTests.swift
//  ACI AdminTests
//
//  The wire contract is prose in another repo, so the places where a silent
//  mismatch would cost us a 400 (or a wrong time on a push) are pinned here.
//

import Foundation
import Testing
@testable import ACI_Admin

// MARK: - Timestamps

@Suite("APIDate")
struct APIDateTests {
    /// PostgREST's actual output shape: six fractional digits and a numeric offset.
    /// This is the single riskiest parse in the app.
    @Test func parsesPostgrestMicrosecondsWithOffset() throws {
        let date = try #require(APIDate.parse("2026-08-30T15:04:05.123456+00:00"))
        #expect(abs(date.timeIntervalSince1970 - 1788102245.123456) < 0.001)
    }

    /// Captured verbatim from the deployed server, so a Postgres or PostgREST
    /// change that alters the shape fails here rather than in the field.
    @Test func parsesARealResponseTimestamp() throws {
        let date = try #require(APIDate.parse("2026-08-23T21:54:41.388098+00:00"))
        #expect(abs(date.timeIntervalSince1970 - 1787522081.388098) < 0.001)
    }

    @Test func parsesMillisecondsAndZuluAndPlainForms() throws {
        let forms = [
            "2026-08-30T15:04:05.123+00:00",
            "2026-08-30T15:04:05.123456Z",
            "2026-08-30T15:04:05Z",
            "2026-08-30T15:04:05+00:00",
        ]
        for form in forms {
            let date = try #require(APIDate.parse(form), "failed to parse \(form)")
            #expect(abs(date.timeIntervalSince1970 - 1788102245) < 1)
        }
    }

    @Test func parsesANonUTCOffset() throws {
        let date = try #require(APIDate.parse("2026-08-30T16:04:05.123456+01:00"))
        #expect(abs(date.timeIntervalSince1970 - 1788102245.123456) < 0.001)
    }

    @Test func rejectsGarbage() {
        #expect(APIDate.parse("not a date") == nil)
        #expect(APIDate.parse("") == nil)
    }

    /// We always write `Z`; the server's validator accepts it alongside offsets.
    @Test func encodesAsZulu() {
        let date = Date(timeIntervalSince1970: 1788102245)
        #expect(APIDate.string(date) == "2026-08-30T15:04:05Z")
    }

    @Test func roundTrips() throws {
        let date = Date(timeIntervalSince1970: 1788102245)
        let parsed = try #require(APIDate.parse(APIDate.string(date)))
        #expect(abs(parsed.timeIntervalSince1970 - date.timeIntervalSince1970) < 1)
    }

    @Test func decoderUsesTheChain() throws {
        struct Row: Decodable { let created_at: Date }
        let json = #"{"created_at":"2026-08-30T15:04:05.123456+00:00"}"#
        let row = try JSONDecoder.api.decode(Row.self, from: Data(json.utf8))
        #expect(abs(row.created_at.timeIntervalSince1970 - 1788102245.123456) < 0.001)
    }
}

// MARK: - Patch bodies

@Suite("PatchBody")
struct PatchBodyTests {
    private func encoded(_ patch: PatchBody) throws -> [String: Any] {
        let data = try JSONEncoder.api.encode(patch)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A no-op diff must never reach the wire — the server answers `{}` with
    /// 400 "Nothing to change".
    @Test func isEmptyForANoOpDiff() {
        var patch = PatchBody()
        patch.set("title", ifChanged: "Same", from: "Same")
        patch.set("active", ifChanged: true, from: true)
        #expect(patch.isEmpty)
    }

    /// Strict validation means an unchanged key is not merely wasteful, it is a
    /// 400 risk on fields the endpoint doesn't accept.
    @Test func carriesOnlyChangedKeys() throws {
        var patch = PatchBody()
        patch.set("title", ifChanged: "New", from: "Old")
        patch.set("message", ifChanged: "Same", from: "Same")
        let json = try encoded(patch)
        #expect(json.keys.sorted() == ["title"])
        #expect(json["title"] as? String == "New")
    }

    @Test func sendsExplicitNullToClearANullableField() throws {
        var patch = PatchBody()
        patch.set("sender", nullable: nil)
        let json = try encoded(patch)
        #expect(json["sender"] is NSNull)
    }

    @Test func treatsEmptyStringAsNullForNullableFields() throws {
        var patch = PatchBody()
        patch.set("location", ifChangedNullable: "", from: "Main hall")
        let json = try encoded(patch)
        #expect(json["location"] is NSNull)
    }

    @Test func encodesDatesThroughTheSharedFormat() throws {
        var patch = PatchBody()
        patch.set("scheduled_at", date: Date(timeIntervalSince1970: 1788102245))
        let json = try encoded(patch)
        #expect(json["scheduled_at"] as? String == "2026-08-30T15:04:05Z")
    }
}

// MARK: - Time of day

@Suite("TimeOfDay")
struct TimeOfDayTests {
    /// `display` has to match the design's own strings exactly, or the time pills
    /// stop comparing equal.
    @Test(arguments: [
        ("06:00", "6:00 am"),
        ("04:30", "4:30 am"),
        ("00:00", "12:00 am"),
        ("12:00", "12:00 pm"),
        ("13:05", "1:05 pm"),
        ("20:00", "8:00 pm"),
        ("23:59", "11:59 pm"),
    ])
    func formatsForDisplay(wire: String, display: String) throws {
        let time = try #require(TimeOfDay(hhmm: wire))
        #expect(time.display == display)
        #expect(time.hhmm == wire)
    }

    @Test func parsesTheDisplayFormBackAgain() throws {
        for time in AdminTimes.options {
            let reparsed = try #require(TimeOfDay(display: time.display))
            #expect(reparsed == time)
        }
    }

    /// Every string the prototype offered must survive the move to a value type.
    @Test func coversEverySampleTime() {
        #expect(AdminTimes.options.count == 16)
        #expect(AdminTimes.options.first?.display == "4:00 am")
        #expect(AdminTimes.options.last?.display == "8:00 pm")
    }

    @Test func ordersChronologically() throws {
        let early = try #require(TimeOfDay(hhmm: "06:00"))
        let late = try #require(TimeOfDay(hhmm: "18:00"))
        #expect(early < late)
        #expect(AdminTimes.options == AdminTimes.options.sorted())
    }

    @Test func rejectsMalformedInput() {
        #expect(TimeOfDay(hhmm: "6:00") == nil)      // must be zero-padded
        #expect(TimeOfDay(hhmm: "24:00") == nil)
        #expect(TimeOfDay(hhmm: "12:60") == nil)
        #expect(TimeOfDay(display: "13:00 am") == nil)
    }
}

// MARK: - Calendar day

@Suite("CalendarDay")
struct CalendarDayTests {
    @Test func roundTripsTheWireForm() throws {
        let day = try #require(CalendarDay(iso: "2026-09-20"))
        #expect(day.year == 2026 && day.month == 9 && day.day == 20)
        #expect(day.iso == "2026-09-20")
    }

    @Test func rejectsMalformedInput() {
        #expect(CalendarDay(iso: "2026-9-20") == nil)
        #expect(CalendarDay(iso: "20-09-2026") == nil)
        #expect(CalendarDay(iso: "2026-13-01") == nil)
    }

    /// The whole reason `Calendar.ghana` exists: an admin abroad must still see the
    /// church's date, not their own.
    @Test func isIndependentOfTheDeviceTimeZone() throws {
        // 2026-09-21 01:30 in Accra (UTC) is still the 20th in New York.
        let instant = try #require(APIDate.parse("2026-09-21T01:30:00Z"))

        var accra = Calendar(identifier: .gregorian)
        accra.timeZone = try #require(TimeZone(identifier: "Africa/Accra"))
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        #expect(CalendarDay(instant, in: .ghana).iso == "2026-09-21")
        #expect(CalendarDay(instant, in: accra) == CalendarDay(instant, in: .ghana))
        // The device calendar genuinely disagrees here, so a Calendar.current
        // regression would fail this test rather than slip through.
        #expect(CalendarDay(instant, in: newYork).iso == "2026-09-20")
    }

    @Test func buildsAnInstantAtAGivenTime() throws {
        let day = try #require(CalendarDay(iso: "2026-09-20"))
        let time = try #require(TimeOfDay(hhmm: "07:30"))
        #expect(APIDate.string(day.date(at: time)) == "2026-09-20T07:30:00Z")
    }

    @Test func mapsWeekdaysWithSundayAtZero() throws {
        // 2026-09-20 is a Sunday.
        #expect(try #require(CalendarDay(iso: "2026-09-20")).weekdayIndex == 0)
        #expect(try #require(CalendarDay(iso: "2026-09-21")).weekdayIndex == 1)
        #expect(try #require(CalendarDay(iso: "2026-09-26")).weekdayIndex == 6)
    }

    @Test func addsDaysAcrossAMonthBoundary() throws {
        let day = try #require(CalendarDay(iso: "2026-09-29"))
        #expect(day.adding(days: 3).iso == "2026-10-02")
        #expect(day.adding(days: -29).iso == "2026-08-31")
    }

    @Test func ordersChronologically() throws {
        let a = try #require(CalendarDay(iso: "2026-09-20"))
        let b = try #require(CalendarDay(iso: "2026-10-01"))
        #expect(a < b)
    }
}
