import SwiftUI
import Combine

// MARK: - Settings (the gear in the header)

/// Lets you enable the Macs you use (2–4). Enabled ones appear as checkboxes on
/// every profile.
struct SettingsView: View {
    @Environment(AccountStore.self) private var store
    @State private var localization = Localization.shared
    @AppStorage(Setting.checkUpdates) private var checkUpdates = true
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.t("Ustawienia", "Settings"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("Twoje komputery", "Your Macs"))
                    .font(.subheadline.weight(.semibold))
                Text(loc.t("Zaznacz komputery, których używasz. Pojawią się jako przełączniki przy każdym profilu.",
                     "Tick the Macs you use. They show up as toggles on every profile."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Computer.allCases) { computer in
                    Toggle(isOn: binding(for: computer)) {
                        Label {
                            Text(computer.displayName)
                        } icon: {
                            Image(systemName: computer.systemImage)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t("Aktualizacje", "Updates"))
                    .font(.subheadline.weight(.semibold))
                Toggle(loc.t("Sprawdzaj aktualizacje raz w miesiącu", "Check for updates once a month"),
                       isOn: $checkUpdates)
                    .toggleStyle(.checkbox)
                    .onChange(of: checkUpdates) { _, on in updates.enabled = on }
                HStack {
                    Text(lastCheckText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(loc.t("Sprawdź teraz", "Check Now")) {
                        Task { await updates.check(manually: true) }
                    }
                }
                Text(loc.t("Program pyta stronę fractal8.eu o numer najnowszej wersji — nic więcej nie wysyła. Nowa wersja instaluje się dopiero, gdy klikniesz „Zainstaluj”.",
                     "The app asks fractal8.eu for the number of the newest version — it sends nothing else. A new version installs only when you click “Install”."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("Język", "Language"))
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private var lastCheckText: String {
        guard let date = updates.lastCheck else { return loc.t("Jeszcze nie sprawdzano", "Not checked yet") }
        let when = date.formatted(date: .abbreviated, time: .shortened)
        return loc.t("Ostatnio: \(when)", "Last: \(when)")
    }

    private func binding(for computer: Computer) -> Binding<Bool> {
        Binding(
            get: { store.enabledComputers.contains(computer) },
            set: { isOn in
                if isOn {
                    store.enabledComputers.insert(computer)
                } else {
                    store.enabledComputers.remove(computer)
                }
            }
        )
    }
}
