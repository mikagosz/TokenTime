import SwiftUI
import AppKit

// MARK: - Main panel (the menu bar window)

struct MenuBarView: View {
    @Environment(AccountStore.self) private var store
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchNote: String?
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if case .downloading(stalled: true) = store.syncState {
                stalledBanner
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: 320, height: 450)
        // The login item state is read every time the panel opens, not once when
        // the view is created — the user may have disabled it in the meantime
        // w Ustawieniach systemowych.
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image("MenuBarIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text("TokenTime")
                .font(.headline)
            Text(Self.appVersion)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                }
                .accessibilityLabel("Wersja \(Self.appVersion.dropFirst())")
            SyncBadge(state: store.syncState)
            Spacer()
            Button {
                store.add()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dodaj konto")
            .accessibilityLabel("Dodaj konto")
            .disabled(!store.canEdit)
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Ustawienia")
            .accessibilityLabel("Ustawienia")
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                SettingsView()
                    .environment(store)
            }
        }
        .padding(12)
    }

    /// The version comes from the bundle rather than a literal — the number in the
    /// interface has to match what was actually built (P2-05).
    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v" + (short ?? "?")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        @Bindable var store = store
        if !store.canEdit && store.accounts.isEmpty {
            // Until the cloud state is known, "no accounts" must not be shown —
            // that view is exactly what invited adding an account and overwriting
            // the file with emptiness (P1-01).
            waitingForCloud
        } else if store.accounts.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($store.accounts) { $account in
                        AccountCardView(account: $account)
                    }
                }
                .padding(12)
            }
            .disabled(!store.canEdit)
        }
    }

    private var waitingForCloud: some View {
        let downloading = { if case .downloading = store.syncState { return true } else { return false } }()
        return VStack(spacing: 10) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(downloading ? "Pobieram dane z iCloud…" : "Sprawdzam iCloud…")
                .foregroundStyle(.secondary)
            if downloading {
                Text(loc.t("Konta są w chmurze, ale nie ma ich jeszcze na tym Macu. Do tego czasu nic nie zapisujemy, żeby ich nie nadpisać.",
                           "The accounts are in the cloud but have not reached this Mac yet. Nothing is saved until they do, so they cannot be overwritten."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    /// The download is dragging on. Falling back to local work has to be a
    /// deliberate choice rather than something one slides into — hence its own button.
    private var stalledBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud nie oddaje pliku z kontami")
                    .font(.caption.weight(.semibold))
                Text(loc.t("Możesz pracować na tym, co jest na tym Macu. Zmiany trafią do chmury dopiero, gdy plik się pobierze.",
                           "You can work with what is on this Mac. Changes reach the cloud once the file arrives."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Pracuj lokalnie") {
                store.continueLocally()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Brak kont")
                .foregroundStyle(.secondary)
            Text(loc.t("Dodaj pierwsze konto, aby śledzić reset tokenów.", "Add your first account to track when tokens reset."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    // MARK: Stopka

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // A custom binding rather than `onChange`: the change travels one
                // path, so correcting the toggle after a failed registration does
                // not trigger itself again.
                Toggle("Uruchom przy starcie", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                Spacer()
                Button(loc.t("Zakończ", "Quit")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if let launchNote {
                Text(launchNote)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            switch try LaunchAtLogin.set(enabled) {
            case .enabled, .disabled:
                launchNote = nil
            case .requiresApproval:
                launchNote = loc.t("Pozycja czeka na zgodę: Ustawienia systemowe → Ogólne → Elementy logowania.",
                               "Waiting for approval: System Settings → General → Login Items.")
            }
        } catch {
            launchNote = LaunchAtLogin.advice(for: error)
        }
        // Whatever happened, the toggle shows what is true, not what was wished for.
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

// MARK: - Sync indicator

/// A small marker next to the app name. Without it a failed sync looked exactly
/// like a successful one, and Macs could drift apart unnoticed for weeks (P2-08).
private struct SyncBadge: View {
    let state: AccountStore.SyncState

    var body: some View {
        Image(systemName: symbol)
            .imageScale(.small)
            .foregroundStyle(tint)
            .help(message)
            .accessibilityLabel("Synchronizacja: \(message)")
    }

    private var symbol: String {
        switch state {
        case .resolving:   return "arrow.triangle.2.circlepath.icloud"
        case .downloading: return "icloud.and.arrow.down"
        case .synced:      return "checkmark.icloud"
        case .failed:      return "exclamationmark.icloud"
        case .localOnly:   return "icloud.slash"
        case .detached:    return "icloud.slash"
        }
    }

    private var tint: Color {
        switch state {
        case .resolving, .synced:      return .secondary
        case .downloading:             return .blue
        case .failed:                  return .red
        case .localOnly, .detached:    return .orange
        }
    }

    private var message: String {
        switch state {
        case .resolving:
            return "Sprawdzam iCloud…"
        case .downloading:
            return "Pobieram dane z iCloud…"
        case .synced(let date):
            return "Zsynchronizowano o \(date.formatted(date: .omitted, time: .standard))"
        case .failed(let reason):
            return reason
        case .localOnly:
            return loc.t("iCloud Drive niedostępny — dane tylko na tym Macu", "iCloud Drive unavailable — data stays on this Mac")
        case .detached:
            return loc.t("Praca lokalna — dane z iCloud nie zostały pobrane", "Working locally — iCloud data has not arrived")
        }
    }
}
