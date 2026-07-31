import SwiftUI
import Observation

// MARK: - Przechowywanie kont (iCloud Drive + lokalny fallback)

@Observable
@MainActor
final class AccountStore {
    var accounts: [Account] {
        didSet {
            // Nie zapisujemy z powrotem zmian przychodzących z innego Maka (uniknięcie pętli).
            guard !isApplyingRemoteChange else { return }
            save()
        }
    }

    /// Komputery, które użytkownik posiada (włączane w Ustawieniach).
    /// To one pojawiają się jako checkboxy przy każdym profilu.
    var enabledComputers: Set<Computer> = Set(Computer.allCases) {
        didSet { saveEnabledComputers() }
    }

    @ObservationIgnored private let storageKey = "tokentime.accounts"
    @ObservationIgnored private let enabledComputersKey = "tokentime.enabledComputers"
    @ObservationIgnored private let iCloudURL: URL?
    @ObservationIgnored private var isApplyingRemoteChange = false
    @ObservationIgnored private var lastKnownModDate: Date?
    @ObservationIgnored private var pollTimer: Timer?

    init() {
        // Task 1 — ścieżka w iCloud Drive (dostępna bez entitlements; system synchronizuje katalog).
        let cloudDocs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/TokenTime/accounts.json")
        iCloudURL = cloudDocs

        accounts = []
        accounts = loadInitial()
        enabledComputers = loadEnabledComputers()

        // Task 3 — polling co 7 sekund zamiast powiadomień KVS.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.checkForRemoteChanges() }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: Operacje

    func add() {
        accounts.append(Account(name: "Nowe konto"))
    }

    func remove(id: Account.ID) {
        accounts.removeAll { $0.id == id }
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

    // MARK: Pasek menu

    func menuBarInfo(now: Date = Date()) -> (text: String?, status: ResetStatus) {
        let active = accounts.compactMap { account -> (Account, TimeInterval)? in
            guard let date = account.resetDate else { return nil }
            let remaining = date.timeIntervalSince(now)
            return remaining > 0 ? (account, remaining) : nil
        }
        guard let soonest = active.min(by: { $0.1 < $1.1 }) else {
            return (nil, .idle)
        }
        return (Self.shortCountdown(soonest.1), soonest.0.status(now: now))
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

    // MARK: Wczytywanie i zapis

    // Task 1+4 — przy starcie próbujemy iCloud Drive, potem UserDefaults jako fallback.
    private func loadInitial() -> [Account] {
        if let url = iCloudURL,
           let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([Account].self, from: data) {
            UserDefaults.standard.set(data, forKey: storageKey)
            lastKnownModDate = modificationDate(of: url)
            return loaded
        }
        // iCloud Drive niedostępny lub plik nie istnieje — lokalny fallback.
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([Account].self, from: data) {
            return loaded
        }
        return []
    }

    // Task 3 — sprawdza datę modyfikacji co 7 sekund; ładuje plik tylko gdy się zmieniła.
    private func checkForRemoteChanges() {
        guard let url = iCloudURL,
              let modDate = modificationDate(of: url),
              modDate != lastKnownModDate else { return }

        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([Account].self, from: data) else { return }

        lastKnownModDate = modDate
        UserDefaults.standard.set(data, forKey: storageKey)
        isApplyingRemoteChange = true
        accounts = loaded
        isApplyingRemoteChange = false
    }

    // Task 2 — zapis do iCloud Drive + lokalnego cache.
    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)

        guard let url = iCloudURL else { return }
        // Task 1 — utwórz katalog TokenTime jeśli nie istnieje.
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Ukryj katalog w Finderze (flaga hidden). Nazwa i synchronizacja iCloud
        // pozostają bez zmian — w przeciwieństwie do nazwy z kropką, której iCloud
        // Drive w ogóle by nie synchronizował.
        hideDirectory(dir)
        // Task 4 — błąd zapisu nie crashuje appki; działa lokalnie.
        do {
            try data.write(to: url, options: .atomic)
            // Zapamiętaj własną datę zapisu, żeby polling nie wczytał własnego pliku.
            lastKnownModDate = modificationDate(of: url)
        } catch {
            // Zapis do iCloud Drive nie powiódł się — kontynuujemy tylko lokalnie.
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Ustawia folderowi flagę „hidden”, żeby nie zaśmiecał widoku w Finderze.
    private func hideDirectory(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isHidden = true
        try? url.setResourceValues(values)
    }

    // MARK: Ustawienia komputerów (lokalne — nie synchronizowane)

    private func loadEnabledComputers() -> Set<Computer> {
        // Brak zapisu = pierwsze uruchomienie → wszystkie komputery włączone.
        guard let raw = UserDefaults.standard.array(forKey: enabledComputersKey) as? [String] else {
            return Set(Computer.allCases)
        }
        return Set(raw.compactMap(Computer.init(rawValue:)))
    }

    private func saveEnabledComputers() {
        UserDefaults.standard.set(enabledComputers.map(\.rawValue), forKey: enabledComputersKey)
    }
}
