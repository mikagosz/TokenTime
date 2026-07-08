import SwiftUI
import AppKit

// MARK: - Główny panel (okno z paska menu)

struct MenuBarView: View {
    @Environment(AccountStore.self) private var store
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

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
            TokenTimeGlyph()
                .frame(width: 18, height: 18)
                .foregroundStyle(.tint)
            Text("TokenTime")
                .font(.headline)
            Spacer()
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
        VStack(spacing: 8) {
            Button {
                store.add()
            } label: {
                Label("Dodaj konto", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)

            Divider()

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
        }
        .padding(12)
    }
}
