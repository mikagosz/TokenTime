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

struct Account: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var resetDate: Date?          // nil = brak aktywnego licznika
    var windowHours: Double = 5   // pełne okno (do paska postępu), domyślnie 5h
    var computers: Set<Computer> = []   // komputery, na których profil jest zalogowany

    init(id: UUID = UUID(),
         name: String,
         resetDate: Date? = nil,
         windowHours: Double = 5,
         computers: Set<Computer> = []) {
        self.id = id
        self.name = name
        self.resetDate = resetDate
        self.windowHours = windowHours
        self.computers = computers
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
