import Foundation
import Testing
@testable import TokenTime

// MARK: - Model konta

@Suite("Account — status and progress")
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
        // Exactly one hour is still `ok` — the boundary is sharp.
        #expect(account(resetIn: 3600).status(now: now) == .ok)
    }

    @Test("Under an hour turns amber")
    func soonUnderAnHour() {
        #expect(account(resetIn: 3599).status(now: now) == .soon)
        #expect(account(resetIn: 60).status(now: now) == .soon)
    }

    @Test("A reached reset is the done state")
    func doneAtOrPastReset() {
        #expect(account(resetIn: 0).status(now: now) == .done)
        #expect(account(resetIn: -1).status(now: now) == .done)
        #expect(account(resetIn: -86_400).status(now: now) == .done)
    }

    @Test("Remaining time never goes below zero")
    func remainingNeverNegative() {
        #expect(account(resetIn: -500).remaining(now: now) == 0)
        #expect(account(resetIn: 120).remaining(now: now) == 120)
    }

    @Test("Progress spreads across the whole window")
    func progressAcrossWindow() {
        #expect(account(resetIn: 5 * 3600, windowHours: 5).progress(now: now) == 0)
        #expect(account(resetIn: 2.5 * 3600, windowHours: 5).progress(now: now) == 0.5)
        #expect(account(resetIn: 0, windowHours: 5).progress(now: now) == 1)
    }

    @Test("Progress stays within 0…1 even for an absurd window")
    func progressStaysClamped() {
        #expect(account(resetIn: -10_000, windowHours: 5).progress(now: now) == 1)
        // windowHours = 0 must not divide by zero or escape the range.
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

    @Test("Assigning the same value leaves the stamp alone")
    func idempotentAssignmentKeepsTimestamp() {
        // Without this, SwiftUI writing an unchanged value through `@Binding`
        // would bump the stamp and trigger a save on every redraw.
        let stamp = Date(timeIntervalSinceReferenceDate: 1000)
        var account = Account(name: "bez zmian", computers: [.iMac], updatedAt: stamp)
        account.name = "bez zmian"
        account.computers = [.iMac]
        account.windowHours = 5
        #expect(account.updatedAt == stamp)
    }

    @Test("Deleting leaves a dated tombstone")
    func markDeleted() {
        var account = Account(name: "to be deleted", updatedAt: .distantPast)
        #expect(account.isDeleted == false)
        account.markDeleted()
        #expect(account.isDeleted)
        #expect(account.deletedAt == account.updatedAt)
    }

    @Test("A missing stamp is filled in from the file date")
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

@Suite("Account — decoding older files")
struct AccountDecodingTests {

    @Test("A file predating windows and Macs loads in full")
    func decodesLegacyEntry() throws {
        // The exact shape of an entry from a file written by version 1.0.
        let json = Data("""
        {"resetDate":807230396.101608,"windowHours":3.25,"computers":[],\
        "name":"mik13","id":"63579F70-64D2-4BCB-9758-8600ABB12C11"}
        """.utf8)

        let account = try JSONDecoder().decode(Account.self, from: json)
        #expect(account.name == "mik13")
        #expect(account.windowHours == 3.25)
        #expect(account.computers.isEmpty)
        #expect(account.isDeleted == false)
        // No stamp means `.distantPast` until the file date fills it in.
        #expect(account.updatedAt == .distantPast)
    }

    @Test("Missing fields fall back to defaults instead of breaking the load")
    func decodesMinimalEntry() throws {
        let json = Data(#"{"name":"bare entry"}"#.utf8)
        let account = try JSONDecoder().decode(Account.self, from: json)
        #expect(account.name == "bare entry")
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
