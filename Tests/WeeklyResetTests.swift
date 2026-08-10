import Foundation
import Testing
@testable import TokenTime

// MARK: - Parsing Anthropic's wording
//
// The format comes from someone else's screen, so the tests are mostly about what
// the user will actually paste: mixed case, "12am" glued together, and the 12 AM /
// 12 PM trap that catches people (and code) more often than any other hour.

@Suite("WeeklyReset — parser")
struct WeeklyResetParserTests {

    @Test("The canonical form")
    func canonical() {
        let parsed = WeeklyReset.parse("Sat 12 AM")
        #expect(parsed == WeeklyReset(weekday: 7, hour: 0, minute: 0))
    }

    @Test("12 AM is midnight, 12 PM is noon")
    func noonAndMidnight() {
        #expect(WeeklyReset.parse("Sat 12 AM")?.hour == 0)
        #expect(WeeklyReset.parse("Sat 12 PM")?.hour == 12)
    }

    @Test("Afternoon hours get 12 added")
    func afternoon() {
        #expect(WeeklyReset.parse("Mon 5 PM") == WeeklyReset(weekday: 2, hour: 17, minute: 0))
        #expect(WeeklyReset.parse("Fri 11 PM") == WeeklyReset(weekday: 6, hour: 23, minute: 0))
    }

    @Test("Case, glued meridiem and a comma are all accepted", arguments: [
        "sat 12am", "SAT 12 AM", "Sat 12:00 AM", "Saturday 12 AM", "Sat, 12 AM"
    ])
    func spellings(_ input: String) {
        #expect(WeeklyReset.parse(input) == WeeklyReset(weekday: 7, hour: 0, minute: 0))
    }

    @Test("Minutes are read when given")
    func minutes() {
        #expect(WeeklyReset.parse("Wed 5:30 PM") == WeeklyReset(weekday: 4, hour: 17, minute: 30))
    }

    /// A half-understood entry would count down to the wrong moment, so anything
    /// short of a whole match is rejected.
    @Test("Malformed entries are rejected", arguments: [
        "", "   ", "Sat", "Sat 12", "12 AM", "Xyz 12 AM", "Sat 13 AM", "Sat 0 AM",
        "Sat 12 XM", "Sat 12:5 AM", "Sat 12:60 AM", "Sat 12 AM extra", "Sat :30 AM"
    ])
    func rejected(_ input: String) {
        #expect(WeeklyReset.parse(input) == nil)
    }

    /// What the user typed has to come back unchanged — the field is pre-filled with
    /// this when they reopen it.
    @Test("The label round-trips through the parser", arguments: [
        "Sat 12 AM", "Mon 5 PM", "Wed 5:30 PM", "Sun 12 PM"
    ])
    func roundTrip(_ input: String) {
        #expect(WeeklyReset.parse(input)?.label == input)
    }
}

// MARK: - The next occurrence

@Suite("WeeklyReset — next occurrence")
struct WeeklyResetScheduleTests {

    /// A fixed calendar and zone: the result must not depend on where the test runs.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    @Test("Finds the coming Saturday midnight")
    func comingSaturday() {
        // Wednesday 2026-08-12, 10:00 → Saturday 2026-08-15, 00:00
        let weekly = WeeklyReset(weekday: 7, hour: 0, minute: 0)
        let next = weekly.nextDate(after: date(2026, 8, 12, 10), calendar: calendar)
        #expect(next == date(2026, 8, 15, 0))
    }

    /// The moment itself must roll forward, not stand still — otherwise the card
    /// would show "in 0m" for a whole minute every week.
    @Test("Standing exactly on the reset gives the next week")
    func exactlyOnReset() {
        let weekly = WeeklyReset(weekday: 7, hour: 0, minute: 0)
        let next = weekly.nextDate(after: date(2026, 8, 15, 0), calendar: calendar)
        #expect(next == date(2026, 8, 22, 0))
    }

    @Test("A minute past the reset gives the next week")
    func justAfterReset() {
        let weekly = WeeklyReset(weekday: 7, hour: 0, minute: 0)
        let next = weekly.nextDate(after: date(2026, 8, 15, 0, 1), calendar: calendar)
        #expect(next == date(2026, 8, 22, 0))
    }

    /// The clocks go back on the last Sunday of October. The user typed a wall-clock
    /// time, so a wall-clock time is what they must get — the interval is 25 h that week,
    /// and that is correct, not a bug to "fix" by adding 24 h.
    @Test("A wall-clock time survives the change to winter time")
    func daylightSaving() {
        // Poland: clocks go back on 2026-10-25. Reset set for Sunday 3 AM.
        let weekly = WeeklyReset(weekday: 1, hour: 3, minute: 0)
        let next = weekly.nextDate(after: date(2026, 10, 24, 12), calendar: calendar)
        let components = calendar.dateComponents([.weekday, .hour], from: next!)
        #expect(components.weekday == 1)
        #expect(components.hour == 3)
    }

    @Test("Remaining time is the distance to that moment")
    func remaining() {
        let weekly = WeeklyReset(weekday: 7, hour: 0, minute: 0)
        let now = date(2026, 8, 14, 0)          // Friday midnight → 24 h to go
        #expect(weekly.remaining(from: now, calendar: calendar) == 86_400)
    }

    @Test("Progress runs across the whole week")
    func progress() {
        let weekly = WeeklyReset(weekday: 7, hour: 0, minute: 0)
        // A full week away = just reset; a day away = six sevenths through.
        #expect(weekly.progress(from: date(2026, 8, 8, 0), calendar: calendar) == 0)
        let dayBefore = weekly.progress(from: date(2026, 8, 14, 0), calendar: calendar)
        #expect(abs(dayBefore - 6.0 / 7.0) < 0.001)
    }
}

// MARK: - Storage

@Suite("WeeklyReset — storage")
struct WeeklyResetStorageTests {

    /// Files written by an older TokenTime, or by a Mac that has not updated yet,
    /// must still load — losing accounts over a new optional field is exactly the
    /// failure this app already had once (P2-03).
    @Test("An account without a weekly reset still decodes")
    func decodesOlderFile() throws {
        let json = """
        {"id":"E0E0E0E0-0000-0000-0000-000000000001","name":"stare konto","windowHours":5}
        """
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        #expect(account.weeklyReset == nil)
        #expect(account.name == "stare konto")
    }

    @Test("A weekly reset survives a round trip through JSON")
    func roundTrip() throws {
        let account = Account(name: "konto", weeklyReset: WeeklyReset(weekday: 7, hour: 0, minute: 0))
        let data = try JSONEncoder().encode(account)
        let back = try JSONDecoder().decode(Account.self, from: data)
        #expect(back.weeklyReset == account.weeklyReset)
    }

    /// Merging between Macs goes by `updatedAt`, so setting the weekly reset has to
    /// bump that stamp — otherwise the other Mac would overwrite it back to nil.
    @Test("Setting the weekly reset bumps the change stamp")
    func bumpsUpdatedAt() {
        var account = Account(name: "konto", updatedAt: .distantPast)
        account.weeklyReset = WeeklyReset(weekday: 7, hour: 0, minute: 0)
        #expect(account.updatedAt > .distantPast)
    }
}
