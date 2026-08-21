import Foundation
import Testing
@testable import TokenTime

// MARK: - The probes polling depends on
//
// These tests run against a real file in a temporary directory, never against the
// user's accounts file: `AccountsFile` is only a thin layer over the file system,
// and the thing that broke could not be seen in a pure function.
//
// What broke: a `URL` value caches every resource value it has ever fetched, and
// the cache belongs to the value. `AccountsFile` holds one long-lived `url`, so
// from its second question onwards it kept being handed its first answer, and
// `AccountStore.poll` never saw a modification date change. The file was read once
// per launch and written forever after — which is exactly what "TokenTime does not
// sync between the Macs" looked like from the outside.

private func makeTemporaryDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("TokenTimeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// The modification date straight from the file system — the control the tests
/// measure the probe against. It goes through `FileManager` on purpose: it must not
/// share the mechanism that is under test.
private func modificationDateOnDisk(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

@Suite("Plik kont — sondy dla odpytywania")
struct AccountsFileTests {

    @Test("The modification date follows the file, it is not frozen at the first reading")
    func modificationDateIsNotCached() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("accounts.json")
        let file = AccountsFile(url: url)   // held for the whole test, as the store holds it

        try Data("[]".utf8).write(to: url)
        let first = file.modificationDate()
        #expect(first != nil)

        // Somebody else replaces the file — the other Mac, through iCloud.
        Thread.sleep(forTimeInterval: 1.1)
        try Data(#"[{"name":"z drugiego Maka"}]"#.utf8).write(to: url, options: .atomic)

        // Positive control: the file really did change. Without it a probe that
        // always returns the same date would look the same as a file nobody touched.
        #expect(modificationDateOnDisk(url) != first)

        let second = file.modificationDate()
        #expect(second == modificationDateOnDisk(url))
        #expect(second != first,
                "The probe answered with the previous date — poll() will never notice the other Mac")
    }

    @Test("The date returned by a write is the date of the file we wrote")
    func writeReportsTheDateItWrote() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("accounts.json")
        let file = AccountsFile(url: url)

        try Data("[]".utf8).write(to: url)
        _ = file.modificationDate()   // primes the cache the old code fell into

        Thread.sleep(forTimeInterval: 1.1)
        let written = try file.write(Data(#"[{"name":"stąd"}]"#.utf8))

        #expect(written == modificationDateOnDisk(url),
                "`lastKnownModDate` would be stamped with a stale date, and every later comparison would match by accident")
    }

    @Test("A file replaced behind our back is read as its new content")
    func readSeesReplacedContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("accounts.json")
        let file = AccountsFile(url: url)

        try Data("[]".utf8).write(to: url)
        _ = try file.read()

        Thread.sleep(forTimeInterval: 1.1)
        let replacement = Data(#"[{"name":"z drugiego Maka"}]"#.utf8)
        try replacement.write(to: url, options: .atomic)

        let snapshot = try file.read()
        #expect(snapshot.data == replacement)
        #expect(snapshot.modificationDate == modificationDateOnDisk(url))
    }

    @Test("A downloaded file outside iCloud counts as present")
    func availabilityOfALocalFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("accounts.json")
        let file = AccountsFile(url: url)

        try Data("[]".utf8).write(to: url)
        #expect(file.availability() == .present)
    }
}
