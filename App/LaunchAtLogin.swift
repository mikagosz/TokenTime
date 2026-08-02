import ServiceManagement
import os

// MARK: - Uruchamianie przy logowaniu (macOS 13+)

/// Rejestracja pozycji logowania, która nie udaje, że się udała.
///
/// Wcześniej nieudany `register()` szedł do `print()` i przełącznik zostawał
/// zaznaczony — użytkownik dowiadywał się o tym dopiero po restarcie, którego
/// nic z niczym nie łączyło (P1-02).
enum LaunchAtLogin {

    /// Jak skończyła się próba zmiany. `requiresApproval` to nie porażka, ale
    /// i nie sukces: pozycja jest zarejestrowana, tylko czeka na zgodę w
    /// Ustawieniach systemowych. Bez niej aplikacja i tak nie wstanie.
    enum Outcome: Equatable {
        case enabled
        case disabled
        case requiresApproval
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Zmienia ustawienie i zwraca stan faktyczny. Rzuca, gdy system odmówił —
    /// wywołujący ma wtedy co pokazać i co cofnąć.
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
                "Nie udało się \(enabled ? "włączyć" : "wyłączyć", privacy: .public) pozycji logowania: \(error.localizedDescription, privacy: .public)"
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

    /// Powody bywają tu działaniami do wykonania, więc warto je nazwać wprost.
    static func advice(for error: any Error) -> String {
        let code = (error as NSError).code
        switch code {
        case kSMErrorAlreadyRegistered:
            return "System uważa, że pozycja już istnieje. Usuń TokenTime z Elementów logowania i spróbuj ponownie."
        case kSMErrorLaunchDeniedByUser:
            return "Zablokowane w Ustawieniach systemowych → Ogólne → Elementy logowania."
        case kSMErrorInvalidSignature:
            return "Podpis aplikacji nie pozwala jej na rejestrację. Przenieś TokenTime do Programów i uruchom stamtąd."
        default:
            return "Nie udało się zmienić ustawienia: \(error.localizedDescription)"
        }
    }
}
