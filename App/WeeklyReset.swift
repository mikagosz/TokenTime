import Foundation

// MARK: - Weekly limit reset

/// The moment in the week when an account's weekly limit resets, written the way
/// Anthropic states it: a day abbreviation plus a 12-hour clock — `Sat 12 AM`.
///
/// Only the recurring rule is stored, never a concrete date. The next occurrence is
/// computed from it, so the entry stays true after every reset and there is nothing
/// to bump week after week.
struct WeeklyReset: Codable, Equatable, Sendable {
    /// 1 = Sunday … 7 = Saturday — the numbering `Calendar` itself uses, so the value
    /// can go straight into `DateComponents(weekday:)` without translation.
    var weekday: Int
    /// 0–23. `12 AM` is midnight (0), `12 PM` is noon (12).
    var hour: Int
    var minute: Int

    /// Day abbreviations in `Calendar` order, starting at Sunday = 1.
    ///
    /// Deliberately hardcoded in English rather than taken from `Calendar.shortWeekdaySymbols`:
    /// this is the format Anthropic prints, so it must read the same on a Polish Mac.
    /// Localised symbols would turn `Sat` into `sob` and stop matching what the user copies.
    static let dayAbbreviations = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// The entry written back out, e.g. `Sat 12 AM`, `Mon 5:30 PM`.
    var label: String {
        let day = Self.dayAbbreviations[(weekday - 1 + 7) % 7]
        let suffix = hour < 12 ? "AM" : "PM"
        var clock = hour % 12
        if clock == 0 { clock = 12 }
        let time = minute == 0 ? "\(clock)" : String(format: "%d:%02d", clock, minute)
        return "\(day) \(time) \(suffix)"
    }

    /// The first reset strictly after `date`.
    ///
    /// `Calendar.nextDate(after:matching:)` does the search, which is what keeps the
    /// daylight-saving cases honest: on the weekend the clocks move, the wall-clock
    /// time the user typed is still the time they get.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
            matchingPolicy: .nextTime
        )
    }

    /// Seconds until the next reset. `nil` only when the calendar finds no match at all.
    func remaining(from date: Date = Date(), calendar: Calendar = .current) -> TimeInterval? {
        nextDate(after: date, calendar: calendar).map { $0.timeIntervalSince(date) }
    }

    /// Progress through the week (0 = the reset just happened, 1 = it is due now).
    ///
    /// The window is the whole week, since that is the period this bar stands for —
    /// unlike the session bar, whose window the user types in.
    func progress(from date: Date = Date(), calendar: Calendar = .current) -> Double {
        guard let remaining = remaining(from: date, calendar: calendar) else { return 0 }
        let week: TimeInterval = 7 * 86_400
        return min(1, max(0, 1 - remaining / week))
    }
}

// MARK: - Parsing what Anthropic prints

extension WeeklyReset {
    /// Reads `Sat 12 AM` and the shapes around it: `sat 12am`, `Sat 12:00 AM`,
    /// `Mon 5 PM`. Returns `nil` for anything it cannot read whole — a half-understood
    /// entry would show a countdown to the wrong moment, which is worse than no countdown.
    ///
    /// Input is user-typed, so this is validation, not convenience: the ladder's
    /// exemption for "data coming in from outside" applies.
    static func parse(_ input: String) -> WeeklyReset? {
        // Case and separators are the user's business; the shape is not.
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: " ")
            .lowercased()
        guard !cleaned.isEmpty else { return nil }

        // "12am" is one token, "12 am" is two — glue the meridiem back on so both
        // spellings take the same path.
        var tokens = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        if let last = tokens.last, last.count > 2, last.hasSuffix("am") || last.hasSuffix("pm") {
            let meridiem = String(last.suffix(2))
            tokens[tokens.count - 1] = String(last.dropLast(2))
            tokens.append(meridiem)
        }
        guard tokens.count == 3 else { return nil }

        guard let weekday = weekdayNumber(tokens[0]) else { return nil }

        let meridiem = tokens[2]
        guard meridiem == "am" || meridiem == "pm" else { return nil }

        // Hour, or hour:minute.
        let clockParts = tokens[1].split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(clockParts.count),
              let clockHour = Int(clockParts[0]), (1...12).contains(clockHour)
        else { return nil }

        var minute = 0
        if clockParts.count == 2 {
            let minutesText = clockParts[1]
            guard minutesText.count == 2, let parsed = Int(minutesText), (0..<60).contains(parsed)
            else { return nil }
            minute = parsed
        }

        // 12 AM is 0, 12 PM is 12 — the one place this format traps people.
        var hour = clockHour % 12
        if meridiem == "pm" { hour += 12 }

        return WeeklyReset(weekday: weekday, hour: hour, minute: minute)
    }

    /// Accepts the three-letter abbreviation and the full English day name.
    private static func weekdayNumber(_ token: String) -> Int? {
        let full = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let index = full.firstIndex(where: { $0 == token }) { return index + 1 }
        guard token.count == 3,
              let index = dayAbbreviations.firstIndex(where: { $0.lowercased() == token })
        else { return nil }
        return index + 1
    }
}

// MARK: - Countdown text

extension WeeklyReset {
    /// A weekly countdown reads in days and hours — `3 dni 23h`. Seconds would be noise
    /// at this range, and this text sits inside a 12 pt bar, so it has to stay short.
    /// Bilingual, because the app is (`Localization`).
    static func countdownText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 {
            // Polish takes "dzień" only at one; every other count in this range is "dni".
            return loc.t("\(days) \(days == 1 ? "dzień" : "dni") \(hours)h", "\(days)d \(hours)h")
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
