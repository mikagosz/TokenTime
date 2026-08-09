import Foundation
import Testing
@testable import TokenTime

/// The expected result as a `TimeInterval`. Without an explicit type the literals
/// come out as integers, and comparing `TimeInterval?` with `Int` goes through
/// `AnyHashable` and is false whatever the values are.
private func hm(_ hours: Int, _ minutes: Int = 0) -> TimeInterval {
    TimeInterval(hours) * 3600 + TimeInterval(minutes) * 60
}

// MARK: - Parser czasu trwania
//
// The parser accepts only "H:MM" and a bare hour count. The edge cases are the
// unobvious part (`3:` rejected, `3:5` read as 3 h 05 m, zero rejected), so they
// are what these tests are mostly about.

@Suite("DurationParser")
struct DurationParserTests {

    @Test("Format zegarowy H:MM")
    func clockFormat() {
        #expect(DurationParser.parse("3:30") == hm(3, 30))
        #expect(DurationParser.parse("2:45") == hm(2, 45))
        #expect(DurationParser.parse("0:30") == hm(0, 30))
        #expect(DurationParser.parse("12:00") == hm(12))
    }

    @Test("Sama liczba to godziny")
    func bareHours() {
        #expect(DurationParser.parse("3") == hm(3))
        #expect(DurationParser.parse("1") == hm(1))
    }

    @Test("A single minute digit reads as tens")
    func singleDigitMinutes() {
        // „3:5” to 3h05m, nie 3h50m — nieoczywiste, ale takie jest zachowanie.
        #expect(DurationParser.parse("3:5") == hm(3, 5))
    }

    @Test("Surrounding whitespace is ignored")
    func trimsWhitespace() {
        #expect(DurationParser.parse("  3:30  ") == hm(3, 30))
    }

    @Test("Zero jest odrzucane — licznik na zero nie ma sensu")
    func rejectsZero() {
        #expect(DurationParser.parse("0") == nil)
        #expect(DurationParser.parse("0:00") == nil)
        #expect(DurationParser.parse("0:0") == nil)
    }

    @Test("Incomplete and overloaded input is rejected", arguments: [
        "", "   ", "3:", ":30", "3:60", "3:99", "3:005", "1:2:3", "-1:30", "3,30", "abc",
    ])
    func rejectsMalformed(input: String) {
        #expect(DurationParser.parse(input) == nil)
    }

    @Test("Formats the README once promised are still not accepted", arguments: [
        "4h", "1h30m", "90m", "45s",
    ])
    func rejectsSuffixFormats(input: String) {
        // The documentation promised these, the parser never knew them (P2-04).
        // This test keeps the README and the implementation from drifting again.
        #expect(DurationParser.parse(input) == nil)
    }
}
