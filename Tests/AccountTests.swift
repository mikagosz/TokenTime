import Foundation
import Testing
@testable import TokenTime

// MARK: - Model konta

@Suite("Account — status i postęp")
struct AccountStatusTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func account(resetIn seconds: TimeInterval?, windowHours: Double = 5) -> Account {
        Account(name: "test",
                resetDate: seconds.map { now.addingTimeInterval($0) },
                windowHours: windowHours)
    }

    @Test("Bez licznika konto jest bezczynne")
    func idleWithoutReset() {
        #expect(account(resetIn: nil).status(now: now) == .idle)
        #expect(account(resetIn: nil).remaining(now: now) == nil)
        #expect(account(resetIn: nil).progress(now: now) == 0)
    }

    @Test("Ponad godzina do resetu to stan spokojny")
    func okFarAway() {
        #expect(account(resetIn: 2 * 3600).status(now: now) == .ok)
        // Dokładnie godzina to jeszcze `ok` — granica jest ostra.
        #expect(account(resetIn: 3600).status(now: now) == .ok)
    }

    @Test("Poniżej godziny robi się bursztynowo")
    func soonUnderAnHour() {
        #expect(account(resetIn: 3599).status(now: now) == .soon)
        #expect(account(resetIn: 60).status(now: now) == .soon)
    }

    @Test("Osiągnięty reset to stan gotowy")
    func doneAtOrPastReset() {
        #expect(account(resetIn: 0).status(now: now) == .done)
        #expect(account(resetIn: -1).status(now: now) == .done)
        #expect(account(resetIn: -86_400).status(now: now) == .done)
    }

    @Test("Pozostały czas nigdy nie schodzi poniżej zera")
    func remainingNeverNegative() {
        #expect(account(resetIn: -500).remaining(now: now) == 0)
        #expect(account(resetIn: 120).remaining(now: now) == 120)
    }

    @Test("Postęp rozkłada się na całym oknie")
    func progressAcrossWindow() {
        #expect(account(resetIn: 5 * 3600, windowHours: 5).progress(now: now) == 0)
        #expect(account(resetIn: 2.5 * 3600, windowHours: 5).progress(now: now) == 0.5)
        #expect(account(resetIn: 0, windowHours: 5).progress(now: now) == 1)
    }

    @Test("Postęp trzyma się przedziału 0…1 także przy niedorzecznym oknie")
    func progressStaysClamped() {
        #expect(account(resetIn: -10_000, windowHours: 5).progress(now: now) == 1)
        // windowHours = 0 nie może dzielić przez zero ani wyjść poza zakres.
        let degenerate = account(resetIn: 3600, windowHours: 0).progress(now: now)
        #expect(degenerate >= 0 && degenerate <= 1)
    }
}

@Suite("Account — znacznik zmiany")
struct AccountTimestampTests {

    @Test("Realna zmiana pola podbija znacznik")
    func mutationBumpsTimestamp() {
        var account = Account(name: "przed", updatedAt: .distantPast)
        account.name = "po"
        #expect(account.updatedAt > .distantPast)
    }

    @Test("Przypisanie tej samej wartości znacznika nie rusza")
    func idempotentAssignmentKeepsTimestamp() {
        // Bez tego SwiftUI, zapisując przez `@Binding` niezmienioną wartość,
        // podbijałby znacznik i wywoływał zapis przy każdym przerysowaniu.
        let stamp = Date(timeIntervalSinceReferenceDate: 1000)
        var account = Account(name: "bez zmian", computers: [.iMac], updatedAt: stamp)
        account.name = "bez zmian"
        account.computers = [.iMac]
        account.windowHours = 5
        #expect(account.updatedAt == stamp)
    }

    @Test("Usunięcie zostawia nagrobek z datą")
    func markDeleted() {
        var account = Account(name: "do usunięcia", updatedAt: .distantPast)
        #expect(account.isDeleted == false)
        account.markDeleted()
        #expect(account.isDeleted)
        #expect(account.deletedAt == account.updatedAt)
    }

    @Test("Brakujący znacznik uzupełnia się datą pliku")
    func stampIfMissing() {
        let fileDate = Date(timeIntervalSinceReferenceDate: 2000)
        var legacy = Account(name: "stare", updatedAt: .distantPast)
        legacy.stampIfMissing(fileDate)
        #expect(legacy.updatedAt == fileDate)

        var fresh = Account(name: "nowe", updatedAt: fileDate.addingTimeInterval(60))
        fresh.stampIfMissing(fileDate)
        #expect(fresh.updatedAt == fileDate.addingTimeInterval(60))
    }
}

@Suite("Account — dekodowanie starszych plików")
struct AccountDecodingTests {

    @Test("Plik sprzed wprowadzenia okna i komputerów wczytuje się w całości")
    func decodesLegacyEntry() throws {
        // Dokładny kształt wpisu z pliku zapisanego przez wersję 1.0.
        let json = Data("""
        {"resetDate":807230396.101608,"windowHours":3.25,"computers":[],\
        "name":"mik13","id":"63579F70-64D2-4BCB-9758-8600ABB12C11"}
        """.utf8)

        let account = try JSONDecoder().decode(Account.self, from: json)
        #expect(account.name == "mik13")
        #expect(account.windowHours == 3.25)
        #expect(account.computers.isEmpty)
        #expect(account.isDeleted == false)
        // Brak znacznika = `.distantPast`, dopóki nie uzupełni go data pliku.
        #expect(account.updatedAt == .distantPast)
    }

    @Test("Brakujące pola dostają wartości domyślne zamiast wywalać wczytywanie")
    func decodesMinimalEntry() throws {
        let json = Data(#"{"name":"goły wpis"}"#.utf8)
        let account = try JSONDecoder().decode(Account.self, from: json)
        #expect(account.name == "goły wpis")
        #expect(account.resetDate == nil)
        #expect(account.windowHours == 5)
        #expect(account.computers.isEmpty)
    }

    @Test("Zapis i odczyt zachowuje znaczniki")
    func roundTripKeepsTimestamps() throws {
        var original = Account(name: "runda", computers: [.macBook, .macStudio])
        original.markDeleted()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Account.self, from: data)

        #expect(decoded == original)
        #expect(decoded.deletedAt == original.deletedAt)
        #expect(decoded.updatedAt == original.updatedAt)
    }
}
