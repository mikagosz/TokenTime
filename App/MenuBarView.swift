import SwiftUI
import AppKit

// MARK: - Główny panel (okno z paska menu)

struct MenuBarView: View {
    @Environment(AccountStore.self) private var store
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 320, height: 450)
    }

    private var header: some View {
        HStack {
            Image("MenuBarIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
            Text("TokenTime")
                .font(.headline)
            Text("v1.0.1")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                }
            Spacer()
            Button {
                store.add()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dodaj konto")
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Ustawienia")
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                SettingsView()
                    .environment(store)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var store = store
        if store.accounts.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Brak kont")
                    .foregroundStyle(.secondary)
                Text("Dodaj pierwsze konto, aby śledzić reset tokenów.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($store.accounts) { $account in
                        AccountCardView(account: $account)
                    }
                }
                .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Uruchom przy starcie", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, enabled in
                    LaunchAtLogin.set(enabled)
                }
            Spacer()
            Button("Zakończ") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(12)
    }
}
