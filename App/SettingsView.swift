import SwiftUI

// MARK: - Settings (the gear in the header)

/// Lets you enable the Macs you use (2–4). Enabled ones appear as checkboxes on
/// every profile.
struct SettingsView: View {
    @Environment(AccountStore.self) private var store
    @State private var localization = Localization.shared

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
