import AppKit
import Observation
import SwiftUI
import os

// MARK: - Przechowywanie kont (iCloud Drive + lokalny cache)

@Observable
@MainActor
final class AccountStore {

    // MARK: Stan synchronizacji

    /// What is currently known about the file in the cloud. The state is shown in
    /// the panel, because a failed sync used to look exactly like a successful one (P2-08).
    enum SyncState: Equatable, Sendable {
        /// Working out what is in the cloud. Saving is on hold.
        case resolving
        /// Plik jest w chmurze, ale nie na tym Macu. Zapis wstrzymany — lokalna
        /// emptiness must not replace something we have not seen yet (P1-01).
        /// `stalled` = the download is taking long enough to offer a way out.
        case downloading(stalled: Bool)
        /// The last exchange with the file succeeded.
        case synced(Date)
        /// The last attempt failed. Local work carries on.
        case failed(String)
        /// iCloud Drive is not enabled on this Mac.
        case localOnly
        /// The file is in the cloud, could not be downloaded, and the user has
        /// deliberately chosen to work locally. Still nothing is written to the cloud.
        case detached
    }

    // MARK: Dane

    var accounts: [Account] {
        didSet {
            // Neither the initial load nor a change arriving from another Mac is
            // saved back (that would loop).
            guard !isLoading, !isApplyingRemoteChange, accounts != oldValue else { return }
            cacheLocally()
            scheduleSave()
        }
    }

    /// The Macs the user owns (enabled in Settings).
    /// These are the ones that appear as checkboxes on every profile.
    var enabledComputers: Set<Computer> = Set(Computer.allCases) {
        didSet {
            guard !isLoading else { return }
            saveEnabledComputers()
        }
    }

    private(set) var syncState: SyncState = .resolving

    /// Whether user changes may be accepted right now. Until the cloud state is
    /// known the panel stays locked — the first change made blind used to overwrite
    /// the file and throw the other Macs out of sync.
    var canEdit: Bool {
        switch syncState {
        case .resolving, .downloading: return false
        case .synced, .failed, .localOnly, .detached: return true
        }
    }

    /// Whether writing to the cloud file is allowed.
    private var canWriteToCloud: Bool {
        switch syncState {
        case .synced, .failed, .localOnly: return true
        case .resolving, .downloading, .detached: return false
        }
    }

    // MARK: Konfiguracja

    @ObservationIgnored private static let storageKey = "tokentime.accounts"
    @ObservationIgnored private static let enabledComputersKey = "tokentime.enabledComputers"

    /// After this many days a deleted account's tombstone is no longer needed —
    /// every Mac has had time to learn about the deletion.
    @ObservationIgnored private static let tombstoneLifetime: TimeInterval = 30 * 24 * 3600

    /// How long to wait for typing to stop before sending the file to the cloud.
    /// Without this, every character of an account name was its own save and its
    /// own sync event
    /// synchronizacji (P2-01).
    @ObservationIgnored private static let saveDelay: Duration = .milliseconds(800)

    /// After this many seconds of a stuck download the panel offers local work.
    @ObservationIgnored private static let downloadPatience: TimeInterval = 20

    @ObservationIgnored private let file: AccountsFile?
    @ObservationIgnored private let pollInterval: Duration

    // MARK: Internal state

    /// Tombstones of deleted accounts — they go into the file, not into the UI.
    @ObservationIgnored private var tombstones: [Account] = []

    /// The initial load is running — observers must stay quiet.
    ///
    /// Counter-intuitively, `didSet` **does fire** for assignments made in `init`:
    /// the `@Observable` macro turns these properties into computed ones over
    /// `_accounts`, so every assignment goes through the setter. Without this flag,
    /// merely launching the app wrote the file to iCloud Drive with nothing changed.
    @ObservationIgnored private var isLoading = true
    @ObservationIgnored private var isApplyingRemoteChange = false
    @ObservationIgnored private var lastKnownModDate: Date?
    @ObservationIgnored private var downloadStartedAt: Date?
    @ObservationIgnored private var isExchanging = false
    /// Whether anything has not reached the file yet. Kept apart from `saveTask`,
    /// because the task outlives itself even once the save has succeeded.
    @ObservationIgnored private var hasPendingSave = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: TerminationObserver?

    /// Wszystko, co idzie do pliku: konta widoczne i nagrobki.
    private var allEntries: [Account] { accounts + tombstones }

    // MARK: Lifecycle

    /// - Parameters:
    ///   - fileURL: where the accounts file lives; `nil` = purely local (tests).
    ///   - pollInterval: how often to check the file for changes from another Mac.
    ///   - observeTermination: whether to add the emergency save on app termination.
    init(fileURL: URL? = AccountsFile.defaultURL,
         pollInterval: Duration = .seconds(7),
         observeTermination: Bool = true) {
        self.file = fileURL.map { AccountsFile(url: $0) }
        self.pollInterval = pollInterval

        // The local cache is shown at once, so the panel does not flash empty while
        // the cloud state is being resolved. `isLoading` keeps that load from being
        // taken for a user change and written back to the file.
        accounts = []
        let cached = Self.split(Self.decode(UserDefaults.standard.data(forKey: Self.storageKey)))
        accounts = cached.live
        tombstones = cached.deleted
        enabledComputers = Self.loadEnabledComputers()
        isLoading = false

        guard file != nil else {
            syncState = .localOnly
            return
        }

        if observeTermination {
            terminationObserver = TerminationObserver { [weak self] in self?.flushNow() }
        }

        Task { await self.resolve() }
        startPolling()
    }

    deinit {
        saveTask?.cancel()
        pollTask?.cancel()
    }

    // MARK: Operacje

    func add() {
        accounts.append(Account(name: "Nowe konto"))
    }

    /// Removes an account from view and leaves a tombstone, so it does not come
    /// back at the next merge with another Mac's file.
    func remove(id: Account.ID) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var removed = accounts[index]
        removed.markDeleted()
        tombstones.append(removed)
        accounts.remove(at: index)
    }

    func rename(id: Account.ID, to name: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].name = name
    }

    func setReset(id: Account.ID, date: Date) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].resetDate = date
    }

    func clearReset(id: Account.ID) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].resetDate = nil
    }

    /// A deliberate way out of a stuck download: work with what is local, while
    /// still not touching the cloud file. Polling carries on, so once the file does
    /// arrive the changes are merged.
    func continueLocally() {
        guard case .downloading = syncState else { return }
        Log.sync.notice("User chose local work despite the iCloud file not being downloaded")
        syncState = .detached
    }

    // MARK: Pasek menu

    func menuBarInfo(now: Date = Date()) -> (text: String?, status: ResetStatus) {
        Self.menuBarInfo(for: accounts, now: now)
    }

    /// A pure form of the menu bar summary — it touches no store state, so it can
    /// be tested without an iCloud file.
    static func menuBarInfo(for accounts: [Account], now: Date) -> (text: String?, status: ResetStatus) {
        let active = accounts.compactMap { account -> (Account, TimeInterval)? in
            guard let date = account.resetDate else { return nil }
            let remaining = date.timeIntervalSince(now)
            return remaining > 0 ? (account, remaining) : nil
        }
        guard let soonest = active.min(by: { $0.1 < $1.1 }) else {
            return (nil, .idle)
        }
        return (shortCountdown(soonest.1), soonest.0.status(now: now))
    }

    static func shortCountdown(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        if total >= 3600 {
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            return "\(hours)h \(minutes)m"
        } else if total >= 60 {
            return "\(total / 60)m"
        } else {
            return "\(total)s"
        }
    }

    // MARK: Resolving the cloud state

    private func resolve() async {
        guard let file else { return }
        file.hideDirectoryIfNeeded()

        switch await Self.offMain({ file.availability() }) {
        case .cloudUnavailable:
            Log.sync.notice("iCloud Drive unavailable on this Mac — working locally")
            syncState = .localOnly

        case .missing:
            // There is no file. The local cache is the only version of the truth,
            // so it may be pushed. If a file arrives later from another Mac, merging
            // per
            // konto i tak niczego nie zgubi.
            syncState = .synced(Date())
            if !allEntries.isEmpty { scheduleSave(immediately: true) }

        case .notDownloaded:
            Log.sync.notice("The accounts file is in the cloud but not on this Mac — requesting a download")
            syncState = .downloading(stalled: false)
            downloadStartedAt = Date()
            do {
                try await Self.offMainThrowing { try file.startDownload() }
            } catch {
                Log.sync.error("Could not request the download: \(error.localizedDescription, privacy: .public)")
                syncState = .downloading(stalled: true)
            }

        case .present:
            await exchange()
        }
    }

    // MARK: Odpytywanie

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled, let self else { return }
                await self.poll()
            }
        }
    }

    private func poll() async {
        guard let file, !isExchanging else { return }

        // While downloading, the only question is whether the file has arrived.
        if case .downloading(let stalled) = syncState {
            if await Self.offMain({ file.availability() }) == .present {
                await exchange()
            } else if !stalled,
                      let started = downloadStartedAt,
                      Date().timeIntervalSince(started) > Self.downloadPatience {
                syncState = .downloading(stalled: true)
            }
            return
        }

        // A cheap probe — a full coordinated read only when the date has changed.
        let modDate = await Self.offMain { file.modificationDate() }
        if modDate == nil, lastKnownModDate != nil {
            // The file is gone (or iCloud evicted it). Resolve the state again.
            await resolve()
            return
        }
        guard let modDate, modDate != lastKnownModDate else { return }
        await exchange()
    }

    // MARK: Wymiana z plikiem

    /// Reads the file, merges it with what we hold and — if the merge contributed
    /// something of ours — sends the result back so the other Macs see it too.
    private func exchange() async {
        guard let file, !isExchanging else { return }
        isExchanging = true
        defer { isExchanging = false }

        let snapshot: AccountsFile.Snapshot
        do {
            snapshot = try await Self.offMainThrowing { try file.read() }
        } catch {
            Log.sync.error("Could not read the accounts file: \(error.localizedDescription, privacy: .public)")
            syncState = .failed(loc.t("Nie udało się odczytać danych z iCloud.", "Could not read the data from iCloud."))
            return
        }

        let stamp = snapshot.modificationDate ?? Date()
        let remote = Self.decode(snapshot.data).map { entry -> Account in
            var entry = entry
            entry.stampIfMissing(stamp)
            return entry
        }

        let merged = Self.prune(Self.merge(local: allEntries, remote: remote), now: Date())
        lastKnownModDate = snapshot.modificationDate
        apply(merged)
        syncState = .synced(Date())

        // The merge contributed something the file lacks — it has to go back, or
        // our change dies at the next save from the other side.
        if Self.differs(merged, from: remote) { scheduleSave(immediately: true) }
    }

    private func apply(_ entries: [Account]) {
        tombstones = entries.filter(\.isDeleted)
        isApplyingRemoteChange = true
        accounts = entries.filter { !$0.isDeleted }
        isApplyingRemoteChange = false
        cacheLocally()
    }

    // MARK: Scalanie

    /// Merges two account lists by `id`, taking the newer version of each.
    ///
    /// On equal timestamps the file wins: an account untouched on this Mac has no
    /// reason to carry a newer stamp than the remote one. Order comes from the local
    /// list; accounts new to us are appended at the end.
    static func merge(local: [Account], remote: [Account]) -> [Account] {
        var byID: [Account.ID: Account] = [:]
        var order: [Account.ID] = []

        for entry in local where byID[entry.id] == nil {
            byID[entry.id] = entry
            order.append(entry.id)
        }
        for entry in remote {
            guard let mine = byID[entry.id] else {
                byID[entry.id] = entry
                order.append(entry.id)
                continue
            }
            if entry.updatedAt >= mine.updatedAt { byID[entry.id] = entry }
        }

        return order.compactMap { byID[$0] }
    }

    /// Whether the merged result contributes anything the file does not have.
    ///
    /// The comparison goes by `id` and deliberately ignores order: each Mac keeps
    /// its own card arrangement, and comparing arrays directly would have two Macs
    /// with different orders bouncing the same file at each other every seven seconds.
    static func differs(_ merged: [Account], from remote: [Account]) -> Bool {
        func byID(_ entries: [Account]) -> [Account.ID: Account] {
            Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        }
        return byID(merged) != byID(remote)
    }

    /// Drops tombstones older than `tombstoneLifetime`.
    static func prune(_ entries: [Account], now: Date) -> [Account] {
        entries.filter { entry in
            guard let deletedAt = entry.deletedAt else { return true }
            return now.timeIntervalSince(deletedAt) < tombstoneLifetime
        }
    }

    // MARK: Zapis

    /// Delays the cloud save by `saveDelay`, so a burst of changes (typing a name)
    /// leaves as one file rather than a dozen sync events.
    private func scheduleSave(immediately: Bool = false) {
        hasPendingSave = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: Self.saveDelay)
                guard !Task.isCancelled else { return }
            }
            await self?.push()
        }
    }

    private func push() async {
        guard let file, canWriteToCloud, let data = encodeEntries() else { return }
        do {
            let written = try await Self.offMainThrowing { try file.write(data) }
            lastKnownModDate = written
            hasPendingSave = false
            syncState = .synced(Date())
        } catch {
            Log.sync.error("Saving to iCloud Drive failed: \(error.localizedDescription, privacy: .public)")
            syncState = .failed(loc.t("Nie udało się zapisać do iCloud. Zmiany są bezpieczne na tym Macu.",
                                      "Could not save to iCloud. The changes are safe on this Mac."))
        }
    }

    /// Zapis awaryjny przy zamykaniu aplikacji — synchronicznie, bo proces zaraz
    /// disappears and the deferred task never wakes.
    ///
    /// Only when there is something to write: launching and quitting the app has no
    /// reason to touch the cloud file.
    private func flushNow() {
        guard hasPendingSave else { return }
        saveTask?.cancel()
        saveTask = nil
        guard let file, canWriteToCloud, let data = encodeEntries() else { return }
        do {
            lastKnownModDate = try file.write(data)
            hasPendingSave = false
        } catch {
            Log.sync.error("The save on termination failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The local cache is always written, immediately — it is cheap, and when the
    /// process ends abruptly it is what saves the last change.
    private func cacheLocally() {
        guard let data = encodeEntries() else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func encodeEntries() -> Data? {
        try? JSONEncoder().encode(allEntries)
    }

    private static func decode(_ data: Data?) -> [Account] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Account].self, from: data)) ?? []
    }

    private static func split(_ entries: [Account]) -> (live: [Account], deleted: [Account]) {
        (entries.filter { !$0.isDeleted }, entries.filter(\.isDeleted))
    }

    /// File work off the main thread — coordination can block for seconds, and the
    /// interface has no reason to watch it.
    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .utility, operation: work).value
    }

    private static func offMainThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .utility, operation: work).value
    }

    // MARK: Mac settings (local — not synchronised)

    private static func loadEnabledComputers() -> Set<Computer> {
        // Nothing stored = first launch → every Mac enabled.
        guard let raw = UserDefaults.standard.array(forKey: enabledComputersKey) as? [String] else {
            return Set(Computer.allCases)
        }
        return Set(raw.compactMap(Computer.init(rawValue:)))
    }

    private func saveEnabledComputers() {
        UserDefaults.standard.set(enabledComputers.map(\.rawValue), forKey: Self.enabledComputersKey)
    }
}

// MARK: - Zapis przy zamykaniu aplikacji

/// Cel dla `NSApplication.willTerminateNotification`.
///
/// The notification has to be handled synchronously — the process disappears right
/// after it and nothing asynchronous will run. A separate `NSObject` allows the
/// selector-based variant, without a `@Sendable` closure the store could not satisfy.
@MainActor
private final class TerminationObserver: NSObject {
    private let onTerminate: @MainActor () -> Void

    init(onTerminate: @escaping @MainActor () -> Void) {
        self.onTerminate = onTerminate
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func applicationWillTerminate() {
        onTerminate()
    }
}
