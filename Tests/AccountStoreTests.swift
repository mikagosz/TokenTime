import Foundation
import Testing
@testable import TokenTime

// MARK: - The store's pure functions
//
// Only the static, pure operations are tested. `AccountStore` is deliberately not
// created here: the test bundle runs inside the app's process, so a live store
// would read and write the user's real accounts — in `UserDefaults`
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

    @Test("Accounts with no countdown, and those past their reset, do not count as active")
    func ignoresIdleAndFinished() {
        let accounts = [
            account("bez licznika"),
            account("po resecie", resetIn: -60),
            account("exactly now", resetIn: 0),
        ]
        let info = AccountStore.menuBarInfo(for: accounts, now: now)
        #expect(info.text == nil)
        #expect(info.status == .idle)
    }

    @Test("The account with the shortest time left is chosen")
    func picksSoonest() {
        let accounts = [
            account("daleko", resetIn: 5 * 3600),
            account("blisko", resetIn: 90 * 60),
            account("middling", resetIn: 3 * 3600),
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

@Suite("Compact countdown")
struct ShortCountdownTests {

    @Test("Over an hour — hours and minutes")
    func hoursAndMinutes() {
        #expect(AccountStore.shortCountdown(3661) == "1h 1m")
        #expect(AccountStore.shortCountdown(7200) == "2h 0m")
        #expect(AccountStore.shortCountdown(3600) == "1h 0m")
    }

    @Test("Under an hour — minutes only")
    func minutesOnly() {
        #expect(AccountStore.shortCountdown(3599) == "59m")
        #expect(AccountStore.shortCountdown(60) == "1m")
    }

    @Test("Under a minute — seconds")
    func secondsOnly() {
        #expect(AccountStore.shortCountdown(59) == "59s")
        #expect(AccountStore.shortCountdown(0) == "0s")
    }
}

// MARK: Scalanie per konto

@Suite("Merging changes between Macs")
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

    @Test("An account known only locally survives the merge")
    func keepsLocalOnly() {
        let mine = account("just added")
        let merged = AccountStore.merge(local: [mine], remote: [])
        #expect(merged.map(\.name) == ["just added"])
    }

    @Test("The newer change wins, whichever side it is on")
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

    @Test("On an equal stamp the file wins")
    func tieGoesToFile() {
        // An account untouched on this Mac has no reason to carry a newer stamp.
        // A tie therefore means "I did not change this", not "I am right".
        let id = UUID()
        let merged = AccountStore.merge(
            local: [account("local", updatedAt: now, id: id)],
            remote: [account("remote", updatedAt: now, id: id)]
        )
        #expect(merged.map(\.name) == ["remote"])
    }

    @Test("Two Macs changing different accounts do not erase each other")
    func independentEditsBothSurvive() {
        // This is exactly the scenario that lost a change when the whole array was
        // replaced (P2-03).
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

    @Test("A tombstone removes an account the other Mac has not deleted yet")
    func tombstoneRemovesAccount() {
        let id = UUID()
        var deleted = account("deleted", updatedAt: older, id: id)
        deleted.markDeleted(at: newer)

        let merged = AccountStore.merge(
            local: [account("deleted", updatedAt: older, id: id)],
            remote: [deleted]
        )
        #expect(merged.count == 1)
        #expect(merged[0].isDeleted)
    }

    @Test("An account edited after deletion comes back to life")
    func laterEditBeatsTombstone() {
        let id = UUID()
        var deleted = account("deleted", updatedAt: older, id: id)
        deleted.markDeleted(at: older)

        let merged = AccountStore.merge(
            local: [account("wskrzeszone", updatedAt: newer, id: id)],
            remote: [deleted]
        )
        #expect(merged.map(\.name) == ["wskrzeszone"])
        #expect(merged[0].isDeleted == false)
    }

    @Test("Order comes from the local list, new accounts go last")
    func preservesLocalOrder() {
        let a = account("pierwsze"), b = account("drugie"), c = account("z pliku")
        let merged = AccountStore.merge(local: [a, b], remote: [c, b, a])
        #expect(merged.map(\.name) == ["pierwsze", "drugie", "z pliku"])
    }
}

@Suite("Tombstone expiry")
struct PruneTests {

    @Test("Live accounts never disappear")
    func keepsLiveAccounts() {
        let entries = [account("live")]
        #expect(AccountStore.prune(entries, now: now.addingTimeInterval(10 * 365 * 86_400)).count == 1)
    }

    @Test("A fresh tombstone stays, an expired one goes")
    func dropsOnlyExpiredTombstones() {
        var fresh = account("just deleted")
        fresh.markDeleted(at: now.addingTimeInterval(-86_400))
        var old = account("long deleted")
        old.markDeleted(at: now.addingTimeInterval(-40 * 86_400))

        let pruned = AccountStore.prune([fresh, old], now: now)
        #expect(pruned.map(\.name) == ["just deleted"])
    }
}

@Suite("Detecting differences from the file")
struct DiffersTests {

    @Test("Order alone is not a difference")
    func orderAloneIsNotADifference() {
        // Otherwise two Macs with different card arrangements would bounce the same
        // file at each other every seven seconds.
        let a = account("A"), b = account("B")
        #expect(AccountStore.differs([a, b], from: [b, a]) == false)
    }

    @Test("Changed content, a new account and a vanished one are differences")
    func contentDifferences() {
        let id = UUID()
        let mine = account("after the change", updatedAt: now, id: id)
        let theirs = account("before the change", updatedAt: now.addingTimeInterval(-60), id: id)

        #expect(AccountStore.differs([mine], from: [theirs]))
        #expect(AccountStore.differs([mine, account("new")], from: [mine]))
        #expect(AccountStore.differs([mine], from: [mine, account("to delete")]))
        #expect(AccountStore.differs([mine], from: [mine]) == false)
    }
}
