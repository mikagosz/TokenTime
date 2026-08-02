import Foundation
import Testing
@testable import TokenTime

// MARK: - Czyste funkcje składnicy
//
// Testujemy wyłącznie statyczne, czyste operacje. `AccountStore` celowo nie jest
// tu tworzony: pakiet testowy działa w procesie aplikacji, więc żywa składnica
// czytałaby i zapisywała prawdziwe konta użytkownika — w `UserDefaults`
// i w iCloud Drive.

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func account(_ name: String,
                     resetIn seconds: TimeInterval? = nil,
                     updatedAt: Date = now,
                     id: UUID = UUID()) -> Account {
    Account(id: id,
            name: name,
            resetDate: seconds.map { now.addingTimeInterval($0) },
            updatedAt: updatedAt)
}

// MARK: Podsumowanie do paska menu

@Suite("Pasek menu")
struct MenuBarInfoTests {

    @Test("Bez kont pasek nie pokazuje nic")
    func emptyList() {
        let info = AccountStore.menuBarInfo(for: [], now: now)
        #expect(info.text == nil)
        #expect(info.status == .idle)
    }

    @Test("Konta bez licznika i po resecie nie liczą się jako aktywne")
    func ignoresIdleAndFinished() {
        let accounts = [
            account("bez licznika"),
            account("po resecie", resetIn: -60),
            account("dokładnie teraz", resetIn: 0),
        ]
        let info = AccountStore.menuBarInfo(for: accounts, now: now)
        #expect(info.text == nil)
        #expect(info.status == .idle)
    }

    @Test("Wybierane jest konto z najkrótszym czasem")
    func picksSoonest() {
        let accounts = [
            account("daleko", resetIn: 5 * 3600),
            account("blisko", resetIn: 90 * 60),
            account("średnio", resetIn: 3 * 3600),
        ]
        let info = AccountStore.menuBarInfo(for: accounts, now: now)
        #expect(info.text == "1h 30m")
        #expect(info.status == .ok)
    }

    @Test("Status pochodzi z konta wybranego, nie z pierwszego z brzegu")
    func statusFollowsSelectedAccount() {
        let accounts = [
            account("spokojne", resetIn: 4 * 3600),
            account("pilne", resetIn: 10 * 60),
        ]
        let info = AccountStore.menuBarInfo(for: accounts, now: now)
        #expect(info.text == "10m")
        #expect(info.status == .soon)
    }
}

@Suite("Skrócone odliczanie")
struct ShortCountdownTests {

    @Test("Powyżej godziny — godziny i minuty")
    func hoursAndMinutes() {
        #expect(AccountStore.shortCountdown(3661) == "1h 1m")
        #expect(AccountStore.shortCountdown(7200) == "2h 0m")
        #expect(AccountStore.shortCountdown(3600) == "1h 0m")
    }

    @Test("Poniżej godziny — same minuty")
    func minutesOnly() {
        #expect(AccountStore.shortCountdown(3599) == "59m")
        #expect(AccountStore.shortCountdown(60) == "1m")
    }

    @Test("Poniżej minuty — sekundy")
    func secondsOnly() {
        #expect(AccountStore.shortCountdown(59) == "59s")
        #expect(AccountStore.shortCountdown(0) == "0s")
    }
}

// MARK: Scalanie per konto

@Suite("Scalanie zmian między Makami")
struct MergeTests {
    private let older = now.addingTimeInterval(-3600)
    private let newer = now.addingTimeInterval(3600)

    @Test("Konto znane tylko z pliku dochodzi do listy")
    func adoptsRemoteOnly() {
        let mine = account("moje")
        let theirs = account("cudze")
        let merged = AccountStore.merge(local: [mine], remote: [theirs])
        #expect(merged.map(\.name) == ["moje", "cudze"])
    }

    @Test("Konto znane tylko lokalnie przeżywa scalenie")
    func keepsLocalOnly() {
        let mine = account("świeżo dodane")
        let merged = AccountStore.merge(local: [mine], remote: [])
        #expect(merged.map(\.name) == ["świeżo dodane"])
    }

    @Test("Nowsza zmiana wygrywa, niezależnie od strony")
    func newerWins() {
        let id = UUID()

        let localNewer = AccountStore.merge(
            local: [account("lokalne", updatedAt: newer, id: id)],
            remote: [account("zdalne", updatedAt: older, id: id)]
        )
        #expect(localNewer.map(\.name) == ["lokalne"])

        let remoteNewer = AccountStore.merge(
            local: [account("lokalne", updatedAt: older, id: id)],
            remote: [account("zdalne", updatedAt: newer, id: id)]
        )
        #expect(remoteNewer.map(\.name) == ["zdalne"])
    }

    @Test("Przy równym znaczniku wygrywa plik")
    func tieGoesToFile() {
        // Konto, którego na tym Macu nie tknięto, nie ma powodu mieć nowszego
        // znacznika. Remis oznacza więc „nie zmieniałem tego", nie „mam rację".
        let id = UUID()
        let merged = AccountStore.merge(
            local: [account("lokalne", updatedAt: now, id: id)],
            remote: [account("zdalne", updatedAt: now, id: id)]
        )
        #expect(merged.map(\.name) == ["zdalne"])
    }

    @Test("Dwa Maki zmieniające różne konta nie kasują sobie zmian")
    func independentEditsBothSurvive() {
        // Dokładnie ten scenariusz gubił zmianę przy podmianie całej tablicy (P2-03).
        let a = UUID(), b = UUID()
        let local = [
            account("A po mojej zmianie", updatedAt: newer, id: a),
            account("B stare", updatedAt: older, id: b),
        ]
        let remote = [
            account("A stare", updatedAt: older, id: a),
            account("B po ich zmianie", updatedAt: newer, id: b),
        ]
        let merged = AccountStore.merge(local: local, remote: remote)
        #expect(merged.map(\.name) == ["A po mojej zmianie", "B po ich zmianie"])
    }

    @Test("Nagrobek zabiera konto, którego drugi Mac jeszcze nie usunął")
    func tombstoneRemovesAccount() {
        let id = UUID()
        var deleted = account("usunięte", updatedAt: older, id: id)
        deleted.markDeleted(at: newer)

        let merged = AccountStore.merge(
            local: [account("usunięte", updatedAt: older, id: id)],
            remote: [deleted]
        )
        #expect(merged.count == 1)
        #expect(merged[0].isDeleted)
    }

    @Test("Konto zmienione po usunięciu wraca do żywych")
    func laterEditBeatsTombstone() {
        let id = UUID()
        var deleted = account("usunięte", updatedAt: older, id: id)
        deleted.markDeleted(at: older)

        let merged = AccountStore.merge(
            local: [account("wskrzeszone", updatedAt: newer, id: id)],
            remote: [deleted]
        )
        #expect(merged.map(\.name) == ["wskrzeszone"])
        #expect(merged[0].isDeleted == false)
    }

    @Test("Kolejność bierze się z listy lokalnej, nowe konta idą na koniec")
    func preservesLocalOrder() {
        let a = account("pierwsze"), b = account("drugie"), c = account("z pliku")
        let merged = AccountStore.merge(local: [a, b], remote: [c, b, a])
        #expect(merged.map(\.name) == ["pierwsze", "drugie", "z pliku"])
    }
}

@Suite("Przedawnianie nagrobków")
struct PruneTests {

    @Test("Żywe konta nigdy nie znikają")
    func keepsLiveAccounts() {
        let entries = [account("żywe")]
        #expect(AccountStore.prune(entries, now: now.addingTimeInterval(10 * 365 * 86_400)).count == 1)
    }

    @Test("Świeży nagrobek zostaje, przedawniony znika")
    func dropsOnlyExpiredTombstones() {
        var fresh = account("świeżo usunięte")
        fresh.markDeleted(at: now.addingTimeInterval(-86_400))
        var old = account("dawno usunięte")
        old.markDeleted(at: now.addingTimeInterval(-40 * 86_400))

        let pruned = AccountStore.prune([fresh, old], now: now)
        #expect(pruned.map(\.name) == ["świeżo usunięte"])
    }
}

@Suite("Wykrywanie różnic wobec pliku")
struct DiffersTests {

    @Test("Sama kolejność to nie różnica")
    func orderAloneIsNotADifference() {
        // Inaczej dwa Maki o różnym ułożeniu kart odsyłałyby sobie ten sam plik
        // w kółko co siedem sekund.
        let a = account("A"), b = account("B")
        #expect(AccountStore.differs([a, b], from: [b, a]) == false)
    }

    @Test("Zmieniona treść, nowe i zniknięte konto to różnice")
    func contentDifferences() {
        let id = UUID()
        let mine = account("po zmianie", updatedAt: now, id: id)
        let theirs = account("przed zmianą", updatedAt: now.addingTimeInterval(-60), id: id)

        #expect(AccountStore.differs([mine], from: [theirs]))
        #expect(AccountStore.differs([mine, account("nowe")], from: [mine]))
        #expect(AccountStore.differs([mine], from: [mine, account("do usunięcia")]))
        #expect(AccountStore.differs([mine], from: [mine]) == false)
    }
}
