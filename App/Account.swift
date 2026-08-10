import SwiftUI

// MARK: - Mac kinds

/// The Macs a profile can be signed in on.
/// The order of `allCases` sets the checkbox order, left to right.
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
/// `updatedAt` is bumped automatically on every real field change — views mutate
/// the account through `@Binding`, so there is no other place where
/// it could be done once and properly. This stamp is what allows changes from two
/// Macs to be merged per account instead of replacing the whole array (P2-03).
struct Account: Identifiable, Codable, Equatable, Sendable {
    var id: UUID

    var name: String {
        didSet { if name != oldValue { updatedAt = Date() } }
    }

    /// nil = brak aktywnego licznika
    var resetDate: Date? {
        didSet { if resetDate != oldValue { updatedAt = Date() } }
    }

    /// The full window (for the progress bar), 5 h by default. Overridden by a typed duration.
    var windowHours: Double {
        didSet { if windowHours != oldValue { updatedAt = Date() } }
    }

    /// The Macs this profile is signed in on.
    var computers: Set<Computer> {
        didSet { if computers != oldValue { updatedAt = Date() } }
    }

    /// When the weekly limit resets on this account, e.g. `Sat 12 AM`. nil = not set.
    ///
    /// A recurring rule, not a date: it survives every reset without being re-entered.
    var weeklyReset: WeeklyReset? {
        didSet { if weeklyReset != oldValue { updatedAt = Date() } }
    }

    /// When the account last changed. Decides merges between Macs.
    private(set) var updatedAt: Date

    /// Tombstone of a deleted account. Kept in the file until the other Macs learn
    /// about the deletion — otherwise the account would return from their copies.
    private(set) var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    init(id: UUID = UUID(),
         name: String,
         resetDate: Date? = nil,
         windowHours: Double = 5,
         computers: Set<Computer> = [],
         weeklyReset: WeeklyReset? = nil,
         updatedAt: Date = Date(),
         deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.resetDate = resetDate
        self.windowHours = windowHours
        self.computers = computers
        self.weeklyReset = weeklyReset
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    // Tolerant decoding — older files without `windowHours`/`computers` must not
    // break the whole load (the user would lose their accounts).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        resetDate = try c.decodeIfPresent(Date.self, forKey: .resetDate)
        windowHours = try c.decodeIfPresent(Double.self, forKey: .windowHours) ?? 5
        computers = try c.decodeIfPresent(Set<Computer>.self, forKey: .computers) ?? []
        // Added after the first release — files written by an older TokenTime, or by
        // a Mac that has not updated yet, simply carry no weekly reset.
        weeklyReset = try c.decodeIfPresent(WeeklyReset.self, forKey: .weeklyReset)
        // A file written before merging existed carries no stamps.
        // `stampIfMissing(_:)` fills them in from the file's modification date.
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    /// Fills a missing change stamp from the date of the file the account came from.
    /// Without it every entry from an old file would hold `.distantPast` and lose
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

// MARK: - Status and derived values

enum ResetStatus {
    case idle    // brak aktywnego licznika
    case ok      // > 1h do resetu (licznik biegnie)
    case soon    // < 1h do resetu (licznik biegnie)
    case done    // the reset moment arrived — done, waiting for a click on "Reset"

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
    /// Time left until the reset (never negative). nil = no countdown.
    func remaining(now: Date = Date()) -> TimeInterval? {
        guard let resetDate else { return nil }
        return max(0, resetDate.timeIntervalSince(now))
    }

    /// The account's status as of `now`.
    func status(now: Date = Date()) -> ResetStatus {
        guard let resetDate else { return .idle }
        let remaining = resetDate.timeIntervalSince(now)
        if remaining <= 0 { return .done }
        if remaining < 3600 { return .soon }
        return .ok
    }

    /// Progress through the window (0 = just set, 1 = reset reached).
    func progress(now: Date = Date()) -> Double {
        guard let resetDate else { return 0 }
        let total = max(1, windowHours * 3600)
        let remaining = max(0, resetDate.timeIntervalSince(now))
        return min(1, max(0, 1 - remaining / total))
    }
}
