//
//  TimeOfDay.swift
//  ACI Admin
//
//  A wall-clock time with no date. The API carries these as "HH:mm" in 24h UTC
//  (`send_time` on a recurring rule); the console shows them as "6:00 am".
//

import Foundation

nonisolated struct TimeOfDay: Hashable, Comparable, Sendable {
    let hour: Int    // 0...23
    let minute: Int  // 0...59

    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses the wire form, "07:30".
    init?(hhmm: String) {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1])
        else { return nil }
        self.init(hour: h, minute: m)
    }

    /// Parses the display form the prototype's time pills use, "6:00 am".
    /// Kept so `AdminTimes.options` can be written in the design's own words.
    init?(display: String) {
        let parts = display.lowercased().split(separator: " ")
        guard parts.count == 2 else { return nil }
        let clock = parts[0].split(separator: ":")
        guard clock.count == 2, let h12 = Int(clock[0]), let m = Int(clock[1]),
              (1...12).contains(h12)
        else { return nil }
        let hour: Int
        switch parts[1] {
        case "am": hour = h12 == 12 ? 0 : h12
        case "pm": hour = h12 == 12 ? 12 : h12 + 12
        default: return nil
        }
        self.init(hour: hour, minute: m)
    }

    /// The wall-clock time of an instant, read on the church's calendar.
    init(_ date: Date, in cal: Calendar = .ghana) {
        let c = cal.dateComponents([.hour, .minute], from: date)
        self.hour = min(max(c.hour ?? 0, 0), 23)
        self.minute = min(max(c.minute ?? 0, 0), 59)
    }

    static let midnight = TimeOfDay(hour: 0, minute: 0)!

    /// The wire form: "07:30".
    var hhmm: String { String(format: "%02d:%02d", hour, minute) }

    /// The display form: "6:00 am".
    ///
    /// Formatted by hand rather than through `DateFormatter` on purpose — this has
    /// to match `AdminTimes.options` byte for byte for the time pills to compare
    /// equal, and ICU's en_GB am/pm casing has shifted between OS versions.
    var display: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "am" : "pm")
    }

    /// Minutes since midnight — the ordering key, and handy for "is this in the past".
    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func < (a: TimeOfDay, b: TimeOfDay) -> Bool {
        a.minutesSinceMidnight < b.minutesSinceMidnight
    }
}

/// The times a notice or rule can be scheduled for. Replaces `SampleData.times`.
nonisolated enum AdminTimes {
    static let options: [TimeOfDay] = [
        "4:00 am", "4:30 am", "5:00 am", "5:30 am", "6:00 am", "6:30 am", "7:00 am", "8:00 am",
        "9:00 am", "12:00 pm", "2:00 pm", "4:00 pm", "5:00 pm", "6:00 pm", "7:00 pm", "8:00 pm",
    ].compactMap(TimeOfDay.init(display:))

    static let `default` = TimeOfDay(hour: 6, minute: 0)!
}
