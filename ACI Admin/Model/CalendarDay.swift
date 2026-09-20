//
//  CalendarDay.swift
//  ACI Admin
//
//  A date with no time component — the "YYYY-MM-DD" the API uses for rule skips,
//  occurrences and `next_occurrence`.
//

import Foundation

nonisolated extension Calendar {
    /// The church's calendar.
    ///
    /// Africa/Accra is UTC year-round, which is exactly what the server's `send_time`
    /// and skip dates mean. Never use `Calendar.current` for anything scheduled — an
    /// admin travelling must still see the church's dates, not their own.
    static let ghana: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Africa/Accra") ?? TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_GB")
        return cal
    }()
}

nonisolated struct CalendarDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses the wire form, "2026-09-20".
    init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Parses the devotional table's own spelling, "20/09/2026". The audio and
    /// translation routes are the only place this form reaches the app.
    init?(devotional: String) {
        let parts = devotional.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 2, parts[1].count == 2, parts[2].count == 4,
              let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    init(_ date: Date, in cal: Calendar = .ghana) {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    static var today: CalendarDay { CalendarDay(Date()) }

    /// The wire form: "2026-09-20".
    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }

    var isToday: Bool { self == .today }

    func date(at time: TimeOfDay = .midnight, in cal: Calendar = .ghana) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = time.hour
        c.minute = time.minute
        return cal.date(from: c) ?? Date()
    }

    func adding(days: Int, in cal: Calendar = .ghana) -> CalendarDay {
        let shifted = cal.date(byAdding: .day, value: days, to: date()) ?? date()
        return CalendarDay(shifted, in: cal)
    }

    /// Whole days from today — negative in the past. Replaces the prototype's
    /// launch-relative offsets.
    func offsetFromToday(in cal: Calendar = .ghana) -> Int {
        cal.dateComponents([.day], from: CalendarDay.today.date(), to: date()).day ?? 0
    }

    /// 0 = Sunday, matching both the rule model and the server's `getUTCDay()`.
    var weekdayIndex: Int {
        (Calendar.ghana.component(.weekday, from: date()) - 1 + 7) % 7
    }

    static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}
