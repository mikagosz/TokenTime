import Foundation

// MARK: - Dostęp do pliku kont w iCloud Drive

/// Cała praca na `accounts.json`: rozpoznanie stanu, odczyt, zapis, żądanie pobrania.
///
/// Każdy odczyt i zapis idzie przez `NSFileCoordinator`, bo plik podmienia nam pod
/// ręką demon iCloud. Nieskoordynowany `Data(contentsOf:)` potrafi trafić w połowę
/// podmiany i zwrócić urwaną treść, której dekodowanie się nie powiedzie (P2-02).
///
/// Typ jest bezstanowy i `Sendable`, a wszystkie metody są synchroniczne i blokujące —
/// koordynacja potrafi czekać sekundami, więc strona wołająca odsuwa je poza główny
/// wątek. Jedyny wyjątek to zamykanie aplikacji, gdzie nie ma już na co czekać.
///
/// `nonisolated`, bo projekt domyślnie izoluje wszystko do `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`), a to jedyny typ, który ma się wykonywać obok.
nonisolated struct AccountsFile: Sendable {
    /// Co da się dziś powiedzieć o pliku. Kluczowe jest odróżnienie `missing`
    /// od `notDownloaded` — mylenie ich prowadziło do nadpisania chmury pustką (P1-01).
    enum Availability: Sendable, Equatable {
        case present          // plik jest na dysku, da się go czytać
        case notDownloaded    // plik istnieje w chmurze, ale nie na tym Macu
        case missing          // pliku nie ma nigdzie — pierwsze uruchomienie
        case cloudUnavailable // iCloud Drive nie jest włączony na tym Macu
    }

    struct Snapshot: Sendable {
        let data: Data
        let modificationDate: Date?
    }

    let url: URL

    /// Domyślne położenie: katalog iCloud Drive dostępny bez entitlements —
    /// system synchronizuje go tak samo jak resztę Dokumentów w iCloud.
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

    /// Zastępnik, którym starszy iCloud Drive oznacza niepobraną zawartość.
    private var placeholderURL: URL {
        directory.appendingPathComponent(".\(url.lastPathComponent).icloud", isDirectory: false)
    }

    // MARK: Rozpoznanie stanu

    func availability() -> Availability {
        let fm = FileManager.default

        // Nowszy iCloud Drive zostawia plik widocznym, tylko bez zawartości.
        // Wtedy poznajemy stan po atrybucie, nie po istnieniu ścieżki.
        if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus {
            return status == .notDownloaded ? .notDownloaded : .present
        }

        if fm.fileExists(atPath: url.path) { return .present }
        if fm.fileExists(atPath: placeholderURL.path) { return .notDownloaded }
        guard fm.fileExists(atPath: Self.cloudDocumentsURL.path) else { return .cloudUnavailable }
        return .missing
    }

    /// Tania sonda dla odpytywania — sam `stat`, bez koordynacji i bez czytania treści.
    func modificationDate() -> Date? {
        Self.modificationDate(of: url)
    }

    /// Prosi system o ściągnięcie zawartości na ten Mac.
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

    /// Zapisuje i zwraca datę modyfikacji **zapisanego przez nas** pliku.
    ///
    /// Data czytana jest jeszcze w obrębie koordynacji: gdyby wyjść poza nią,
    /// zapis z drugiego Maka mógłby wcisnąć się między `write` a odczyt atrybutów
    /// i zapamiętalibyśmy cudzą datę jako własną — jego zmiana nigdy by się
    /// wtedy nie wczytała (P3-03).
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

    /// Ustawia katalogowi flagę „hidden”, żeby nie zaśmiecał widoku w Finderze.
    /// Nazwa i synchronizacja iCloud pozostają bez zmian — w przeciwieństwie do
    /// nazwy z kropką, której iCloud Drive w ogóle by nie synchronizował.
    ///
    /// Wołane przy tworzeniu katalogu i raz przy starcie aplikacji (katalog mógł
    /// przyjechać z innego Maka bez flagi), a nie przy każdym zapisie (P3-04).
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
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
