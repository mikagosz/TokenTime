import SwiftUI

// MARK: - Typy komputerów

/// Komputery, na których dany profil może być zalogowany.
/// Kolejność `allCases` wyznacza kolejność checkboxów od lewej do prawej.
enum Computer: String, Codable, CaseIterable, Identifiable, Hashable {
    case macMini
    case iMac
    case macBook
    case macStudio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macMini:   return "Mac mini"
        case .iMac:      return "iMac"
        case .macBook:   return "MacBook"
        case .macStudio: return "Mac Studio"
        }
    }

    var systemImage: String {
        switch self {
        case .macMini:   return "macmini"
        case .iMac:      return "desktopcomputer"
        case .macBook:   return "laptopcomputer"
        case .macStudio: return "macstudio"
        }
    }
}

// MARK: - Model konta

/// Konto wraz ze znacznikiem ostatniej zmiany.
///
/// `updatedAt` jest podbijane automatycznie przy każdej realnej zmianie pola —
/// widoki mutują konto przez `@Binding`, więc nie ma innego miejsca, w którym
/// dałoby się to zrobić raz a dobrze. To ten znacznik pozwala scalać zmiany
/// z dwóch Maków per konto, zamiast podmieniać całą tablicę (P2-03).
struct Account: Identifiable, Codable, Equatable, Sendable {
    var id: UUID

    var name: String {
        didSet { if name != oldValue { updatedAt = Date() } }
    }

    /// nil = brak aktywnego licznika
    var resetDate: Date? {
        didSet { if resetDate != oldValue { updatedAt = Date() } }
    }

    /// Pełne okno (do paska postępu), domyślnie 5h. Nadpisywane wpisanym czasem.
    var windowHours: Double {
        didSet { if windowHours != oldValue { updatedAt = Date() } }
    }

    /// Komputery, na których profil jest zalogowany.
    var computers: Set<Computer> {
        didSet { if computers != oldValue { updatedAt = Date() } }
    }

    /// Kiedy konto ostatnio zmieniono. Rozstrzyga scalanie między Makami.
    private(set) var updatedAt: Date

    /// Nagrobek po usuniętym koncie. Trzymany w pliku, dopóki pozostałe Maki
    /// się o usunięciu nie dowiedzą — inaczej konto wracałoby z ich kopii.
    private(set) var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    init(id: UUID = UUID(),
         name: String,
         resetDate: Date? = nil,
         windowHours: Double = 5,
         computers: Set<Computer> = [],
         updatedAt: Date = Date(),
         deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.resetDate = resetDate
        self.windowHours = windowHours
        self.computers = computers
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    // Tolerancyjne dekodowanie — starsze pliki bez pól `windowHours`/`computers`
    // nie mogą wywalać całego wczytywania (inaczej użytkownik straciłby konta).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        resetDate = try c.decodeIfPresent(Date.self, forKey: .resetDate)
        windowHours = try c.decodeIfPresent(Double.self, forKey: .windowHours) ?? 5
        computers = try c.decodeIfPresent(Set<Computer>.self, forKey: .computers) ?? []
        // Plik zapisany przed wprowadzeniem scalania nie ma znaczników.
        // `stampIfMissing(_:)` uzupełnia je datą modyfikacji pliku.
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    /// Uzupełnia brakujący znacznik zmiany datą pliku, z którego konto pochodzi.
    /// Bez tego wszystkie wpisy ze starego pliku miałyby `.distantPast` i przegrywały
    /// nawet z dawno nieruszanym kontem po drugiej stronie.
    mutating func stampIfMissing(_ date: Date) {
        if updatedAt == .distantPast { updatedAt = date }
    }

    /// Zamienia konto w nagrobek. Sam wpis zostaje w pliku do czasu przedawnienia.
    mutating func markDeleted(at date: Date = Date()) {
        deletedAt = date
        updatedAt = date
    }
}

// MARK: - Status i wielkości pochodne

enum ResetStatus {
    case idle    // brak aktywnego licznika
    case ok      // > 1h do resetu (licznik biegnie)
    case soon    // < 1h do resetu (licznik biegnie)
    case done    // reset osiągnięty — gotowe, czeka na kliknięcie „Reset”

    var color: Color {
        switch self {
        case .idle:  return .secondary
        case .ok:    return .blue                              // biegnie, daleko
        case .soon:  return Color(red: 1.0, green: 0.7, blue: 0.0) // bursztyn — blisko
        case .done:  return .green                             // gotowe, czeka na Reset
        }
    }
}

extension Account {
    /// Czas pozostały do resetu (nigdy ujemny). nil = brak licznika.
    func remaining(now: Date = Date()) -> TimeInterval? {
        guard let resetDate else { return nil }
        return max(0, resetDate.timeIntervalSince(now))
    }

    /// Status konta wyliczony względem `now`.
    func status(now: Date = Date()) -> ResetStatus {
        guard let resetDate else { return .idle }
        let remaining = resetDate.timeIntervalSince(now)
        if remaining <= 0 { return .done }
        if remaining < 3600 { return .soon }
        return .ok
    }

    /// Postęp okna (0 = dopiero ustawiony, 1 = reset osiągnięty).
    func progress(now: Date = Date()) -> Double {
        guard let resetDate else { return 0 }
        let total = max(1, windowHours * 3600)
        let remaining = max(0, resetDate.timeIntervalSince(now))
        return min(1, max(0, 1 - remaining / total))
    }
}
