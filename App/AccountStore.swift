import AppKit
import Observation
import SwiftUI
import os

// MARK: - Przechowywanie kont (iCloud Drive + lokalny cache)

@Observable
@MainActor
final class AccountStore {

    // MARK: Stan synchronizacji

    /// Co dziś wiadomo o pliku w chmurze. Stan jest widoczny w panelu, bo
    /// nieudana synchronizacja wyglądała wcześniej dokładnie tak samo jak udana (P2-08).
    enum SyncState: Equatable, Sendable {
        /// Sprawdzamy, co leży w chmurze. Zapis wstrzymany.
        case resolving
        /// Plik jest w chmurze, ale nie na tym Macu. Zapis wstrzymany — lokalna
        /// pustka nie może zastąpić czegoś, czego jeszcze nie widzieliśmy (P1-01).
        /// `stalled` = pobieranie trwa na tyle długo, że warto zaproponować wyjście.
        case downloading(stalled: Bool)
        /// Ostatnia wymiana z plikiem się udała.
        case synced(Date)
        /// Ostatnia próba się nie powiodła. Praca lokalna trwa dalej.
        case failed(String)
        /// iCloud Drive nie jest włączony na tym Macu.
        case localOnly
        /// Plik jest w chmurze i nie udało się go pobrać, a użytkownik świadomie
        /// wybrał pracę lokalną. Do chmury nadal nie piszemy.
        case detached
    }

    // MARK: Dane

    var accounts: [Account] {
        didSet {
            // Nie zapisujemy ani wczytywania startowego, ani zmian przychodzących
            // z innego Maka (uniknięcie pętli).
            guard !isLoading, !isApplyingRemoteChange, accounts != oldValue else { return }
            cacheLocally()
            scheduleSave()
        }
    }

    /// Komputery, które użytkownik posiada (włączane w Ustawieniach).
    /// To one pojawiają się jako checkboxy przy każdym profilu.
    var enabledComputers: Set<Computer> = Set(Computer.allCases) {
        didSet {
            guard !isLoading else { return }
            saveEnabledComputers()
        }
    }

    private(set) var syncState: SyncState = .resolving

    /// Czy wolno dziś przyjmować zmiany od użytkownika. Dopóki nie wiadomo, co
    /// jest w chmurze, panel nie pozwala nic ruszyć — pierwsza zmiana wykonana
    /// „na ślepo” nadpisywała plik i rozsynchronizowywała pozostałe Maki.
    var canEdit: Bool {
        switch syncState {
        case .resolving, .downloading: return false
        case .synced, .failed, .localOnly, .detached: return true
        }
    }

    /// Czy wolno pisać do pliku w chmurze.
    private var canWriteToCloud: Bool {
        switch syncState {
        case .synced, .failed, .localOnly: return true
        case .resolving, .downloading, .detached: return false
        }
    }

    // MARK: Konfiguracja

    @ObservationIgnored private static let storageKey = "tokentime.accounts"
    @ObservationIgnored private static let enabledComputersKey = "tokentime.enabledComputers"

    /// Po tylu dniach nagrobek po usuniętym koncie przestaje być potrzebny —
    /// wszystkie Maki zdążyły się o usunięciu dowiedzieć.
    @ObservationIgnored private static let tombstoneLifetime: TimeInterval = 30 * 24 * 3600

    /// Ile czekamy na koniec pisania, zanim wyślemy plik do chmury. Bez tego
    /// każdy znak nazwy konta był osobnym zapisem i osobnym zdarzeniem
    /// synchronizacji (P2-01).
    @ObservationIgnored private static let saveDelay: Duration = .milliseconds(800)

    /// Po tylu sekundach nieudanego pobierania panel proponuje pracę lokalną.
    @ObservationIgnored private static let downloadPatience: TimeInterval = 20

    @ObservationIgnored private let file: AccountsFile?
    @ObservationIgnored private let pollInterval: Duration

    // MARK: Stan wewnętrzny

    /// Nagrobki po usuniętych kontach — trafiają do pliku, ale nie do interfejsu.
    @ObservationIgnored private var tombstones: [Account] = []

    /// Trwa wczytywanie startowe — obserwatory mają milczeć.
    ///
    /// Wbrew intuicji `didSet` **odpala się** przy przypisaniach w `init`: makro
    /// `@Observable` zamienia te właściwości na obliczane nad `_accounts`, więc
    /// każde przypisanie idzie przez seter. Bez tej flagi samo uruchomienie
    /// aplikacji zapisywało plik w iCloud Drive, choć nic się nie zmieniło.
    @ObservationIgnored private var isLoading = true
    @ObservationIgnored private var isApplyingRemoteChange = false
    @ObservationIgnored private var lastKnownModDate: Date?
    @ObservationIgnored private var downloadStartedAt: Date?
    @ObservationIgnored private var isExchanging = false
    /// Czy jest coś, czego plik jeszcze nie widział. Trzymane osobno od `saveTask`,
    /// bo zadanie zostaje po sobie także wtedy, gdy zapis już się udał.
    @ObservationIgnored private var hasPendingSave = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: TerminationObserver?

    /// Wszystko, co idzie do pliku: konta widoczne i nagrobki.
    private var allEntries: [Account] { accounts + tombstones }

    // MARK: Cykl życia

    /// - Parameters:
    ///   - fileURL: położenie pliku kont; `nil` = praca wyłącznie lokalna (testy).
    ///   - pollInterval: co ile sprawdzać plik pod kątem zmian z innego Maka.
    ///   - observeTermination: czy dopisać zapis awaryjny przy zamykaniu aplikacji.
    init(fileURL: URL? = AccountsFile.defaultURL,
         pollInterval: Duration = .seconds(7),
         observeTermination: Bool = true) {
        self.file = fileURL.map { AccountsFile(url: $0) }
        self.pollInterval = pollInterval

        // Lokalny cache pokazujemy od razu, żeby panel nie mrugał pustką, zanim
        // rozstrzygnie się stan chmury. `isLoading` pilnuje, żeby samo wczytanie
        // nie zostało wzięte za zmianę użytkownika i nie poszło do pliku.
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

    /// Usuwa konto z widoku i zostawia po nim nagrobek, żeby nie wróciło
    /// przy najbliższym scaleniu z plikiem innego Maka.
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

    /// Świadome wyjście z zawieszonego pobierania: pracujemy na tym, co lokalnie,
    /// ale nadal nie dotykamy pliku w chmurze. Odpytywanie chodzi dalej, więc gdy
    /// plik w końcu przyjedzie, zmiany zostaną scalone.
    func continueLocally() {
        guard case .downloading = syncState else { return }
        Log.sync.notice("Użytkownik wybrał pracę lokalną mimo niepobranego pliku z iCloud")
        syncState = .detached
    }

    // MARK: Pasek menu

    func menuBarInfo(now: Date = Date()) -> (text: String?, status: ResetStatus) {
        Self.menuBarInfo(for: accounts, now: now)
    }

    /// Czysta postać podsumowania do paska menu — bez dotykania stanu składnicy,
    /// dzięki czemu da się ją przetestować bez pliku w iCloud.
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

    // MARK: Rozstrzygnięcie stanu chmury

    private func resolve() async {
        guard let file else { return }
        file.hideDirectoryIfNeeded()

        switch await Self.offMain({ file.availability() }) {
        case .cloudUnavailable:
            Log.sync.notice("iCloud Drive niedostępny na tym Macu — pracujemy lokalnie")
            syncState = .localOnly

        case .missing:
            // Pliku nie ma. Lokalny cache jest jedyną wersją prawdy, więc wolno go
            // wypchnąć. Gdyby plik przyjechał później z innego Maka, scalanie per
            // konto i tak niczego nie zgubi.
            syncState = .synced(Date())
            if !allEntries.isEmpty { scheduleSave(immediately: true) }

        case .notDownloaded:
            Log.sync.notice("Plik kont jest w chmurze, ale nie na tym Macu — żądam pobrania")
            syncState = .downloading(stalled: false)
            downloadStartedAt = Date()
            do {
                try await Self.offMainThrowing { try file.startDownload() }
            } catch {
                Log.sync.error("Nie udało się zażądać pobrania: \(error.localizedDescription, privacy: .public)")
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

        // W trakcie pobierania sprawdzamy tylko, czy plik już dojechał.
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

        // Tania sonda — pełny, koordynowany odczyt tylko gdy data się zmieniła.
        let modDate = await Self.offMain { file.modificationDate() }
        if modDate == nil, lastKnownModDate != nil {
            // Plik zniknął (albo iCloud go eksmitował). Rozstrzygamy stan od nowa.
            await resolve()
            return
        }
        guard let modDate, modDate != lastKnownModDate else { return }
        await exchange()
    }

    // MARK: Wymiana z plikiem

    /// Czyta plik, scala go z tym, co mamy, i — jeśli scalenie wniosło coś naszego —
    /// odsyła wynik z powrotem, żeby pozostałe Maki też go zobaczyły.
    private func exchange() async {
        guard let file, !isExchanging else { return }
        isExchanging = true
        defer { isExchanging = false }

        let snapshot: AccountsFile.Snapshot
        do {
            snapshot = try await Self.offMainThrowing { try file.read() }
        } catch {
            Log.sync.error("Nie udało się odczytać pliku kont: \(error.localizedDescription, privacy: .public)")
            syncState = .failed("Nie udało się odczytać danych z iCloud.")
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

        // Scalenie wniosło coś, czego w pliku nie ma — trzeba to odesłać, inaczej
        // nasza zmiana zginie przy następnym zapisie z drugiej strony.
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

    /// Scala dwie listy kont po `id`, wybierając nowszą wersję każdego z osobna.
    ///
    /// Przy równych znacznikach wygrywa wersja z pliku: konto, którego na tym Macu
    /// nie tknięto, nie ma powodu mieć nowszego znacznika niż zdalne. Kolejność
    /// bierzemy z lokalnej listy, nowe konta z pliku dochodzą na koniec.
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

    /// Czy scalony wynik wnosi coś, czego w pliku nie ma.
    ///
    /// Porównanie idzie po `id`, celowo z pominięciem kolejności: każdy Mac trzyma
    /// własne ułożenie kart, a porównywanie tablic wprost kazałoby dwóm Makom o
    /// różnej kolejności odsyłać sobie ten sam plik w kółko co siedem sekund.
    static func differs(_ merged: [Account], from remote: [Account]) -> Bool {
        func byID(_ entries: [Account]) -> [Account.ID: Account] {
            Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        }
        return byID(merged) != byID(remote)
    }

    /// Wyrzuca nagrobki starsze niż `tombstoneLifetime`.
    static func prune(_ entries: [Account], now: Date) -> [Account] {
        entries.filter { entry in
            guard let deletedAt = entry.deletedAt else { return true }
            return now.timeIntervalSince(deletedAt) < tombstoneLifetime
        }
    }

    // MARK: Zapis

    /// Odkłada zapis do chmury o `saveDelay`, żeby seria zmian (pisanie nazwy)
    /// zeszła jako jeden plik, a nie jako kilkanaście zdarzeń synchronizacji.
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
            Log.sync.error("Zapis do iCloud Drive nie powiódł się: \(error.localizedDescription, privacy: .public)")
            syncState = .failed("Nie udało się zapisać do iCloud. Zmiany są bezpieczne na tym Macu.")
        }
    }

    /// Zapis awaryjny przy zamykaniu aplikacji — synchronicznie, bo proces zaraz
    /// zniknie i odłożone zadanie już się nie obudzi.
    ///
    /// Tylko gdy jest co dopisać: samo uruchomienie i zamknięcie aplikacji nie ma
    /// powodu dotykać pliku w chmurze.
    private func flushNow() {
        guard hasPendingSave else { return }
        saveTask?.cancel()
        saveTask = nil
        guard let file, canWriteToCloud, let data = encodeEntries() else { return }
        do {
            lastKnownModDate = try file.write(data)
            hasPendingSave = false
        } catch {
            Log.sync.error("Zapis przy zamykaniu nie powiódł się: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Lokalny cache trzymamy zawsze i natychmiast — jest tani, a przy nagłym
    /// końcu procesu to on ratuje ostatnią zmianę.
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

    /// Praca na pliku poza głównym wątkiem — koordynacja potrafi czekać sekundami,
    /// a interfejs nie ma powodu na to patrzeć.
    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .utility, operation: work).value
    }

    private static func offMainThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .utility, operation: work).value
    }

    // MARK: Ustawienia komputerów (lokalne — nie synchronizowane)

    private static func loadEnabledComputers() -> Set<Computer> {
        // Brak zapisu = pierwsze uruchomienie → wszystkie komputery włączone.
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
/// Powiadomienie trzeba odebrać synchronicznie — po nim proces znika i nic
/// asynchronicznego już się nie wykona. Osobny `NSObject` pozwala użyć wariantu
/// z selektorem, bez zamknięcia `@Sendable`, którego składnica by nie przeszła.
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
