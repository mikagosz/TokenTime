import SwiftUI
import Observation

// MARK: - Przechowywanie kont (iCloud Key-Value Storage + lokalny fallback)

@Observable
@MainActor
final class AccountStore {
    var accounts: [Account] {
        didSet {
            // Nie zapisujemy z powrotem zmian przyszłych z innego Maka (uniknięcie pętli).
            guard !isApplyingRemoteChange else { return }
            save()
        }
    }

    @ObservationIgnored private let storageKey = "tokentime.accounts"
    @ObservationIgnored private let kvs = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var isApplyingRemoteChange = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        accounts = []

        // Task 3 — nasłuch zmian wypchniętych z innych urządzeń.
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadFromRemote() }
        }

        kvs.synchronize()
        accounts = loadInitial()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
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

    /// Najkrótszy aktywny countdown + jego status (do etykiety w pasku).
    /// Bierze pod uwagę tylko liczniki jeszcze biegnące (resetDate w przyszłości) —
    /// zakończone są pomijane, więc pasek przeskakuje na kolejne aktywne konto.
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

    /// Zwięzły zapis czasu dla paska:
    /// - ≥ 60 min: "3h 25m"
    /// - < 60 min, ≥ 1 min: same minuty, "53m"
    /// - < 1 min: same sekundy, "53s"
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

    /// Task 4 — źródło danych przy starcie: iCloud, a jeśli puste, lokalny fallback.
    private func loadInitial() -> [Account] {
        if let remote = decode(kvs.data(forKey: storageKey)) {
            saveLocalMirror(remote)
            return remote
        }
        // KVS puste (np. brak logowania do iCloud) — działamy lokalnie jak dotąd.
        return decode(UserDefaults.standard.data(forKey: storageKey)) ?? []
    }

    /// Task 3 — przeładowanie po powiadomieniu o zmianie zewnętrznej.
    private func reloadFromRemote() {
        guard let remote = decode(kvs.data(forKey: storageKey)) else { return }
        isApplyingRemoteChange = true
        accounts = remote
        isApplyingRemoteChange = false
        saveLocalMirror(remote)
    }

    /// Zapis do iCloud + lokalnego mirrora (offline).
    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        kvs.set(data, forKey: storageKey)
        kvs.synchronize()
    }

    private func saveLocalMirror(_ accounts: [Account]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func decode(_ data: Data?) -> [Account]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([Account].self, from: data)
    }
}
