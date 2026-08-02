import Foundation
import Testing
@testable import TokenTime

/// Oczekiwany wynik jako `TimeInterval`. Bez jawnego typu literały wychodzą
/// całkowite, a porównanie `TimeInterval?` z `Int` przechodzi przez `AnyHashable`
/// i jest fałszywe niezależnie od wartości.
private func hm(_ hours: Int, _ minutes: Int = 0) -> TimeInterval {
    TimeInterval(hours) * 3600 + TimeInterval(minutes) * 60
}

// MARK: - Parser czasu trwania
//
// Parser przyjmuje wyłącznie „H:MM” oraz samą liczbę godzin. Warunki brzegowe są
// nieoczywiste (`3:` odrzucone, `3:5` przyjęte jako 3h05m, zero odrzucone),
// więc to one są tu głównym przedmiotem testów.

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

    @Test("Jedna cyfra minut czyta się jako dziesiątki")
    func singleDigitMinutes() {
        // „3:5” to 3h05m, nie 3h50m — nieoczywiste, ale takie jest zachowanie.
        #expect(DurationParser.parse("3:5") == hm(3, 5))
    }

    @Test("Białe znaki wokół nie przeszkadzają")
    func trimsWhitespace() {
        #expect(DurationParser.parse("  3:30  ") == hm(3, 30))
    }

    @Test("Zero jest odrzucane — licznik na zero nie ma sensu")
    func rejectsZero() {
        #expect(DurationParser.parse("0") == nil)
        #expect(DurationParser.parse("0:00") == nil)
        #expect(DurationParser.parse("0:0") == nil)
    }

    @Test("Niekompletny i przeładowany zapis jest odrzucany", arguments: [
        "", "   ", "3:", ":30", "3:60", "3:99", "3:005", "1:2:3", "-1:30", "3,30", "abc",
    ])
    func rejectsMalformed(input: String) {
        #expect(DurationParser.parse(input) == nil)
    }

    @Test("Formaty, których README kiedyś obiecywał, nadal nie są przyjmowane", arguments: [
        "4h", "1h30m", "90m", "45s",
    ])
    func rejectsSuffixFormats(input: String) {
        // Dokumentacja obiecywała te zapisy, parser ich nigdy nie znał (P2-04).
        // Test pilnuje, żeby README i implementacja nie rozjechały się ponownie.
        #expect(DurationParser.parse(input) == nil)
    }
}
