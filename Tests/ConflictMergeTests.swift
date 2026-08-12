import Foundation
import Testing
@testable import TokenTime

// MARK: - Merging the file with its iCloud conflict branches
//
// When two Macs replace `accounts.json` without having seen each other's version,
// iCloud keeps one as the current file and files the other as a conflict version.
// Nothing in the app used to look at those branches, so a change made on the other
// Mac was invisible: it never reached the merge, and it did not even change the
// current file's modification date, so polling never woke up. Measured on the real
// file on 2026-08-12: ten unresolved branches, all from the other Mac, spanning
// 8 July to 11 August.

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func account(_ name: String,
                     id: UUID,
                     resetIn seconds: TimeInterval? = nil,
                     updatedAt: Date = now,
                     deletedAt: Date? = nil) -> Account {
    Account(id: id,
            name: name,
            resetDate: seconds.map { now.addingTimeInterval($0) },
            updatedAt: updatedAt,
            deletedAt: deletedAt)
}

@Suite("Scalanie z gałęziami konfliktu iCloud")
struct ConflictMergeTests {

    @Test("An account that exists only in a conflict branch survives the merge")
    func branchOnlyAccountIsKept() {
        let inFile = UUID(), onlyInBranch = UUID()
        let current = [account("in the file", id: inFile)]
        let branch = [account("set on the other Mac", id: onlyInBranch)]

        let merged = AccountStore.mergeSources([current, branch])

        #expect(merged.count == 2)
        #expect(merged.contains { $0.id == onlyInBranch })
    }

    @Test("Across several branches the newest version of each account wins")
    func newestPerAccountWins() {
        let id = UUID()
        let current = [account("old name", id: id, updatedAt: now)]
        let older = [account("older still", id: id, updatedAt: now.addingTimeInterval(-3600))]
        let newest = [account("newest name", id: id, updatedAt: now.addingTimeInterval(3600))]

        let merged = AccountStore.mergeSources([current, older, newest])

        #expect(merged.count == 1)
        #expect(merged[0].name == "newest name")
    }

    /// The branches arrive oldest first, so the newest one has the last word on a
    /// tie. Without that ordering a stale branch could win by arriving later.
    @Test("On an equal stamp the source folded last wins")
    func lastSourceWinsOnATie() {
        let id = UUID()
        let first = [account("first", id: id, updatedAt: now)]
        let last = [account("last", id: id, updatedAt: now)]

        #expect(AccountStore.mergeSources([first, last])[0].name == "last")
    }

    /// A deletion is a tombstone carrying its own stamp, so it has to beat an older
    /// live copy sitting in another branch — otherwise deleting an account on one
    /// Mac would be undone by the other Mac's stale version.
    @Test("A newer tombstone removes an account that a branch still holds")
    func newerTombstoneWins() {
        let id = UUID()
        let branch = [account("still here", id: id, updatedAt: now)]
        let deletion = [account("deleted", id: id,
                                updatedAt: now.addingTimeInterval(60),
                                deletedAt: now.addingTimeInterval(60))]

        let merged = AccountStore.mergeSources([branch, deletion])

        #expect(merged.count == 1)
        #expect(merged[0].isDeleted)
    }

    @Test("An older deletion does not remove an account edited later elsewhere")
    func olderTombstoneLoses() {
        let id = UUID()
        let deletion = [account("deleted earlier", id: id,
                                updatedAt: now,
                                deletedAt: now)]
        let edit = [account("edited later", id: id, updatedAt: now.addingTimeInterval(60))]

        let merged = AccountStore.mergeSources([deletion, edit])

        #expect(merged.count == 1)
        #expect(merged[0].isDeleted == false)
        #expect(merged[0].name == "edited later")
    }

    @Test("No sources at all merge to nothing")
    func noSources() {
        #expect(AccountStore.mergeSources([]).isEmpty)
    }

    /// The measured case, kept as a test so nobody "fixes" it back: the file on this
    /// Mac had no session reset for one account while the branch from the other Mac
    /// had one — but the file's entry was stamped later, because the countdown had
    /// since run out. Merging must keep the newer entry, i.e. the reset stays gone.
    /// Resolving conflicts recovers what is *newer* elsewhere, not what is older here.
    @Test("A newer cleared countdown beats an older one from a branch")
    func aClearedCountdownStaysClearedWhenItIsNewer() {
        let id = UUID()
        let branchWithReset = [account("mik13", id: id, resetIn: 3600, updatedAt: now)]
        let fileWithoutReset = [account("mik13", id: id, updatedAt: now.addingTimeInterval(600))]

        let merged = AccountStore.mergeSources([fileWithoutReset, branchWithReset])

        #expect(merged.count == 1)
        #expect(merged[0].resetDate == nil)
    }
}
