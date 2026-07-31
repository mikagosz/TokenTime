import SwiftUI

// MARK: - Ustawienia (koło zębate w nagłówku)

/// Pozwala włączyć komputery, których używasz (2–4). Włączone pojawiają się
/// jako przełączane checkboxy przy każdym profilu.
struct SettingsView: View {
    @Environment(AccountStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ustawienia")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Twoje komputery")
                    .font(.subheadline.weight(.semibold))
                Text("Zaznacz komputery, których używasz. Pojawią się jako przełączniki przy każdym profilu.")
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
