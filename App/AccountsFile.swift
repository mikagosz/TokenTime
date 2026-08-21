import Foundation

// MARK: - Access to the accounts file in iCloud Drive

/// All work on `accounts.json`: sensing its state, reading, writing, requesting a download.
///
/// Every read and write goes through `NSFileCoordinator`, because the iCloud daemon
/// swaps the file under our hands. An uncoordinated `Data(contentsOf:)` can land
/// mid-swap and return truncated content that then fails to decode (P2-02).
///
/// The type is stateless and `Sendable`, and every method is synchronous and
/// blocking — coordination can wait for seconds, so the caller moves them off the
/// main thread. The one exception is app termination, where there is nothing left
/// to wait for.
///
/// `nonisolated`, because the project isolates everything to `@MainActor` by default
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`) and this is the one type meant to run beside it.
nonisolated struct AccountsFile: Sendable {
    /// What can be said about the file right now. Telling `missing` from
    /// `notDownloaded` is the crucial part — confusing them overwrote the cloud with
    /// emptiness (P1-01).
    enum Availability: Sendable, Equatable {
        case present          // the file is on disk and can be read
        case notDownloaded    // plik istnieje w chmurze, ale nie na tym Macu
        case missing          // pliku nie ma nigdzie — pierwsze uruchomienie
        case cloudUnavailable // iCloud Drive is not enabled on this Mac
    }

    struct Snapshot: Sendable {
        let data: Data
        let modificationDate: Date?
    }

    let url: URL

    /// Default location: an iCloud Drive folder reachable without entitlements —
    /// the system syncs it like the rest of Documents in iCloud.
    static var defaultURL: URL {
        cloudDocumentsURL
            .appendingPathComponent("TokenTime", isDirectory: true)
            .appendingPathComponent("accounts.json", isDirectory: false)
    }

    private static var cloudDocumentsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    private var directory: URL { url.deletingLastPathComponent() }

    /// The placeholder older iCloud Drive uses to mark content that is not downloaded.
    private var placeholderURL: URL {
        directory.appendingPathComponent(".\(url.lastPathComponent).icloud", isDirectory: false)
    }

    // MARK: Rozpoznanie stanu

    func availability() -> Availability {
        let fm = FileManager.default

        // Newer iCloud Drive leaves the file visible but without content. Then the
        // state is read from an attribute rather than from the path existing.
        if let status = try? Self.uncached(url).resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus {
            return status == .notDownloaded ? .notDownloaded : .present
        }

        if fm.fileExists(atPath: url.path) { return .present }
        if fm.fileExists(atPath: placeholderURL.path) { return .notDownloaded }
        guard fm.fileExists(atPath: Self.cloudDocumentsURL.path) else { return .cloudUnavailable }
        return .missing
    }

    /// A cheap probe for polling — just `stat`, no coordination and no reading.
    func modificationDate() -> Date? {
        Self.modificationDate(of: url)
    }

    /// Whether iCloud is holding versions of this file that nobody has merged.
    ///
    /// This is the second cheap probe polling needs, and the reason it exists is a
    /// month of lost changes: when two Macs replace the file without having seen
    /// each other's version, iCloud keeps one as current and files the other as a
    /// **conflict version**. A conflict version does not change the current file's
    /// modification date, so a poller watching only that date never wakes up — and
    /// the app read the current file forever while the other Mac's edits sat in
    /// branches nobody opened. Measured 2026-08-12 on the real file: **10
    /// unresolved branches, all from the Mac mini, from 8 July to 11 August.**
    func hasUnresolvedConflicts() -> Bool {
        (try? Self.uncached(url).resourceValues(forKeys: [.ubiquitousItemHasUnresolvedConflictsKey]))?
            .ubiquitousItemHasUnresolvedConflicts ?? false
    }

    /// Contents of every unresolved conflict version, oldest first.
    ///
    /// Ordered oldest first so a fold over them ends on the newest, matching how
    /// `AccountStore.merge` breaks ties. A branch that cannot be read is skipped
    /// rather than failing the whole exchange: one unreadable branch must not stop
    /// the other nine from being merged.
    func readConflicts() -> [Snapshot] {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) else { return [] }
        return versions
            .sorted { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
            .compactMap { version in
                guard let data = try? Data(contentsOf: version.url) else { return nil }
                return Snapshot(data: data, modificationDate: version.modificationDate)
            }
    }

    /// Tells the system every conflict has been dealt with, which removes the
    /// branches.
    ///
    /// Called **only after** the merged result is safely in the file: resolving
    /// first and writing second would drop the other Mac's changes if the write
    /// then failed. Returns how many branches were closed, so the caller can log a
    /// number rather than "done".
    @discardableResult
    func resolveConflicts() -> Int {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) else { return 0 }
        var closed = 0
        for version in versions {
            version.isResolved = true
            closed += 1
        }
        return closed
    }

    /// Asks the system to bring the content down to this Mac.
    func startDownload() throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: Odczyt i zapis

    func read() throws -> Snapshot {
        var outcome: Result<Snapshot, any Error>?
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            outcome = Result {
                Snapshot(data: try Data(contentsOf: readURL),
                         modificationDate: Self.modificationDate(of: readURL))
            }
        }

        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileReadUnknown) }
        return try outcome.get()
    }

    /// Writes and returns the modification date of the file **we** wrote.
    ///
    /// The date is read while still inside the coordination: outside it, a write
    /// from another Mac could slip between `write` and reading the attributes, and we
    /// would remember someone else's date as our own — their change would then never
    /// be loaded (P3-03).
    @discardableResult
    func write(_ data: Data) throws -> Date? {
        try createDirectoryIfNeeded()

        var written: Date?
        var writeError: (any Error)?
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
                written = Self.modificationDate(of: writeURL)
            } catch {
                writeError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        return written
    }

    // MARK: Katalog

    private func createDirectoryIfNeeded() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directory.path) else { return }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        hideDirectory()
    }

    /// Marks the folder hidden so it does not clutter Finder. The name and iCloud
    /// syncing stay as they are — unlike a dot-prefixed name, which iCloud Drive
    /// would not sync at all.
    ///
    /// Called when the folder is created and once at app start (it may have arrived
    /// from another Mac without the flag), not on every save (P3-04).
    func hideDirectoryIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let isHidden = (try? directory.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
        guard isHidden == false else { return }
        hideDirectory()
    }

    private func hideDirectory() {
        var directory = self.directory
        var values = URLResourceValues()
        values.isHidden = true
        try? directory.setResourceValues(values)
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? uncached(url).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// A `URL` that has never answered a resource-value question before.
    ///
    /// This is the fix for "TokenTime does not sync between Macs", and the reason
    /// is a trap rather than a bug in the sync logic: **a `URL` value caches every
    /// resource value it has ever fetched**, and the cache belongs to the value, not
    /// to the file. This struct holds one long-lived `url`, so from its second
    /// question onwards it was told the *first* answer — forever.
    ///
    /// Two things followed, both of them the whole failure:
    /// * `modificationDate()` froze at the date read shortly after launch, so
    ///   `AccountStore.poll` computed `dateChanged == false` on every single tick;
    /// * `NSFileCoordinator` hands the very same `URL` back to the accessor
    ///   (measured: `readURL == url` is `true`), so `read()` and `write()` stamped
    ///   `lastKnownModDate` with that same frozen date — the two sides of the
    ///   comparison were equal because both were stale, which is why the mismatch
    ///   never showed up as a wrong date in the interface.
    ///
    /// Net effect: the file was read **once per launch** and written forever after,
    /// so each Mac kept overwriting the other's changes with a picture from its own
    /// startup. Measured on the real file 2026-08-21: the other Mac's write landed
    /// on disk at 12:34 and was still unread at 13:55, when a local edit flattened
    /// it. It also explains the ten conflict branches from July — nobody re-read.
    ///
    /// Building the value afresh sidesteps the cache; `removeAllCachedResourceValues()`
    /// would need the bridged `NSURL` to be the same object every time, which is not
    /// something to rely on.
    private static func uncached(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path)
    }
}
