import ServiceManagement
import os

// MARK: - Uruchamianie przy logowaniu (macOS 13+)

/// Login item registration that does not pretend to have worked.
///
/// A failed `register()` used to go to `print()` while the toggle stayed on — the
/// user found out only after a restart, which nothing connected to anything (P1-02).
enum LaunchAtLogin {

    /// How the attempt ended. `requiresApproval` is not a failure, but not a
    /// success either: the item is registered and waiting for approval in
    /// Ustawieniach systemowych. Bez niej aplikacja i tak nie wstanie.
    enum Outcome: Equatable {
        case enabled
        case disabled
        case requiresApproval
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Changes the setting and returns what actually happened. Throws when the
    /// system refuses — the caller then has something to show and something to undo.
    @discardableResult
    static func set(_ enabled: Bool) throws -> Outcome {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            Log.launchAtLogin.error(
                "Could not \(enabled ? "enable" : "disable", privacy: .public) the login item: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }

        let outcome = Self.outcome(for: service.status)
        Log.launchAtLogin.info("Pozycja logowania: \(String(describing: outcome), privacy: .public)")
        return outcome
    }

    private static func outcome(for status: SMAppService.Status) -> Outcome {
        switch status {
        case .enabled:          return .enabled
        case .requiresApproval: return .requiresApproval
        default:                return .disabled
        }
    }

    /// These reasons are often actions to take, so they are spelled out.
    static func advice(for error: any Error) -> String {
        let code = (error as NSError).code
        switch code {
        case kSMErrorAlreadyRegistered:
            return loc.t("System uważa, że pozycja już istnieje. Usuń TokenTime z Elementów logowania i spróbuj ponownie.",
                         "The system thinks the item already exists. Remove TokenTime from Login Items and try again.")
        case kSMErrorLaunchDeniedByUser:
            return loc.t("Zablokowane w Ustawieniach systemowych → Ogólne → Elementy logowania.",
                         "Blocked in System Settings → General → Login Items.")
        case kSMErrorInvalidSignature:
            return loc.t("Podpis aplikacji nie pozwala jej na rejestrację. Przenieś TokenTime do Programów i uruchom stamtąd.",
                         "The app signature does not allow registration. Move TokenTime to Applications and launch it from there.")
        default:
            return loc.t("Nie udało się zmienić ustawienia: \(error.localizedDescription)",
                         "Could not change the setting: \(error.localizedDescription)")
        }
    }
}
