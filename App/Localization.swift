import Foundation
import Observation

/// UI language of the app. Persisted in `UserDefaults`; switching it updates the
/// interface live, with no restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case pl, en

    var id: String { rawValue }

    /// Native name shown in the language picker.
    var displayName: String {
        switch self {
        case .pl: return "Polski"
        case .en: return "English"
        }
    }
}

/// Runtime localization shared across the app.
///
/// A menu bar app has no room for a translation pipeline, and its strings are few
/// enough that the pair sits at the point of use: `loc.t("Usuń konto", "Delete
/// account")`. Both variants stay visible in the same line, which is what keeps
/// them from drifting apart.
@Observable
final class Localization {
    static let shared = Localization()
    static let key = "TokenTime_Language"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        // With no stored choice, follow the system: a Polish Mac opens in Polish,
        // every other one in English.
        let systemIsPolish = Locale.preferredLanguages.first?.hasPrefix("pl") ?? false
        language = AppLanguage(rawValue: stored ?? "") ?? (systemIsPolish ? .pl : .en)
    }

    /// Returns the Polish or English variant for the current UI language.
    func t(_ pl: String, _ en: String) -> String {
        language == .pl ? pl : en
    }
}

/// Short alias for the shared instance — these calls appear inline in view code,
/// where `Localization.shared.t(…)` would bury the strings it is meant to show.
var loc: Localization { Localization.shared }
