import Foundation
import os

// MARK: - Logowanie diagnostyczne

/// Jedno miejsce na loggery aplikacji.
///
/// Wcześniej jedyna diagnostyka szła przez `print()`, a w aplikacji uruchamianej
/// z Findera standardowe wyjście nie trafia nigdzie, gdzie ktokolwiek zajrzy.
/// `os.Logger` widać w Konsoli także po fakcie (P2-09).
///
/// Podgląd na żywo:
/// `log stream --predicate 'subsystem == "com.mikagosz.tokentime"' --level info`
nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mikagosz.tokentime"

    /// Synchronizacja pliku kont z iCloud Drive.
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Rejestracja pozycji logowania.
    static let launchAtLogin = Logger(subsystem: subsystem, category: "launch-at-login")
}
