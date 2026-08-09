import Foundation
import os

// MARK: - Logowanie diagnostyczne

/// Jedno miejsce na loggery aplikacji.
///
/// Diagnostics used to go through `print()`, and for an app launched from Finder
/// standard output goes nowhere anyone will look. `os.Logger` is visible in Console
/// after the fact as well (P2-09).
///
/// Live view:
/// `log stream --predicate 'subsystem == "com.mikagosz.tokentime"' --level info`
nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mikagosz.tokentime"

    /// Synchronizacja pliku kont z iCloud Drive.
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Rejestracja pozycji logowania.
    static let launchAtLogin = Logger(subsystem: subsystem, category: "launch-at-login")
}
