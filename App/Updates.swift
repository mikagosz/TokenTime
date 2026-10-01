import AppKit
import Combine
import ErrorUpdate
import SwiftUI

enum Setting {
    /// Look for a newer version once a month (`Updates`).
    static let checkUpdates = "checkUpdates"
}

/// Checking for a newer TokenTime and installing it from inside the app — the same way Master
/// info, VoiceAI, ColorMyFolder, Switch-Work and CWMac do it, on the same package (ErrorUpdate):
/// once a month, a window with "Install and Restart", "Skip This Version" and a manual download,
/// and a switch under the gear.
///
/// TokenTime has its own update file: ErrorUpdate appends `api/error-update/version-check` to
/// the server address, and the address here ends in `/TokenTime`, so the file is
/// `downloads.fractal8.eu/TokenTime/api/error-update/version-check`. The file at the root belongs
/// to Master info and is never touched by TokenTime's releases.
///
/// Texts go through `loc.t(pl, en)` like the rest of TokenTime, so the window follows the
/// language picked under the gear.
///
/// Crash reporting stays off (`reportingOptIn: false`): a report carries stack paths, and a path
/// under `/Users/<name>/` gives the account name away.
@MainActor
final class Updates: ObservableObject, ErrorUpdateDelegate {
    static let shared = Updates()

    enum Install: Equatable {
        case idle, downloading, installing, busy
        case failed(String)
    }

    private static let productionServer = URL(string: "https://downloads.fractal8.eu/TokenTime")!

    /// A debug build can point at a server on this Mac to test the whole path without uploading
    /// anything: `defaults write com.mikagosz.tokentime updatesServer "http://127.0.0.1:8899"`.
    /// The release build does not read the key at all.
    private static var server: URL {
        #if DEBUG
        if let own = UserDefaults.standard.string(forKey: "updatesServer"), let url = URL(string: own) { return url }
        #endif
        return productionServer
    }

    /// Opened next to a manual download.
    private static let page = URL(string: "https://fractal8.eu/program?p=tokentime")!

    /// Once a month: a check protects against nothing urgent, and every question leaves the
    /// user's address in the server's logs.
    private static let interval: TimeInterval = 30 * 24 * 60 * 60

    private static let lastCheckKey = "updatesLastCheck"
    /// The key ErrorUpdate's own skipped-version store uses, so both remember the same version.
    private static let skippedKey = "ErrorUpdate_SkippedVersion"

    @Published private(set) var available: UpdateInfo?
    @Published private(set) var install: Install = .idle
    /// Why the last check got no answer — without it a failed check would read "up to date".
    @Published private(set) var checkError: String?

    /// TokenTime has no long work a restart could cut off, so nothing holds the update back.
    var isBusy: () -> Bool = { false }

    /// The package reports download and install failures to the delegate instead of throwing.
    private var lastError: String?
    private var timer: Timer?
    private var window: NSWindow?

    private init() {
        UserDefaults.standard.register(defaults: [Setting.checkUpdates: true])
    }

    /// Switching it off stops the timer and closes the window at once.
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Setting.checkUpdates) }
        set {
            UserDefaults.standard.set(newValue, forKey: Setting.checkUpdates)
            if newValue { schedule() } else {
                timer?.invalidate(); timer = nil
                available = nil
                closeWindow()
            }
        }
    }

    var lastCheck: Date? { UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date }

    func start() {
        ErrorUpdateManager.shared.configure(ErrorUpdateConfig(
            serverURL: Self.server,
            appID: Bundle.main.bundleIdentifier ?? "com.mikagosz.tokentime",
            // Releases are not signed with an Ed25519 key yet, so the package checks the SHA-256
            // alone — the weaker mode: the sum travels in the same file as the address. What
            // protects it today is that both live on our R2 and go over HTTPS. The installer also
            // requires the new app to meet the running one's code signature requirement.
            allowUnsignedUpdates: true,
            reportingOptIn: false,
            supportEmail: "support@fractal8.eu"
        ))
        ErrorUpdateManager.shared.delegate = self
        schedule()
    }

    /// The timer runs daily, because a background app can run for weeks without a restart — a
    /// check only at launch would never reach such a user.
    private func schedule() {
        timer?.invalidate()
        guard enabled else { return }
        Task { await checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
    }

    private func checkIfDue() async {
        guard enabled else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.interval { return }
        await check(manually: false)
    }

    /// `manually`: "Check Now" — asks even when switched off, and "you are up to date" is an
    /// answer worth showing too.
    func check(manually: Bool) async {
        if !manually && !enabled { return }
        lastError = nil
        // Not forced for the monthly check: only then does the package honour "Skip This Version"
        // and its guard against offering an update that already installed without effect.
        await ErrorUpdateManager.shared.checkForUpdates(force: manually)
        guard let info = ErrorUpdateManager.shared.availableUpdate else {
            available = nil
            install = .idle
            checkError = lastError
            // A failed automatic check is tried again tomorrow, not in a month.
            if lastError == nil { UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey) }
            if manually { showWindow() }
            return
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        checkError = nil
        if available?.latestVersion != info.latestVersion { install = .idle }
        available = info
        if manually { showWindow() } else { await showWhenIdle() }
    }

    /// Kept from the other apps: with `isBusy` always false the window shows at once.
    private func showWhenIdle() async {
        while isBusy() {
            try? await Task.sleep(for: .seconds(5))
        }
        guard available != nil else { return }
        showWindow()
    }

    // MARK: - Installing

    func updateDidFail(_ error: Error) {
        lastError = error.localizedDescription
    }

    /// Download, replace, restart. Any step that fails leaves the running app on the old
    /// version with a message and the manual way out.
    func installNow() {
        guard let info = available else { return }
        if install == .downloading || install == .installing { return }
        guard DownloadAddress.allowed(info.downloadURL) else {
            install = .failed(loc.t("Adres paczki prowadzi poza serwer fractal8.eu — program jej nie pobierze.",
                                 "The package address leads outside fractal8.eu — the app will not download it."))
            return
        }
        guard !isBusy() else { install = .busy; return }
        let app = Bundle.main.bundleURL
        guard RestartAfterUpdate.writablePlace(app) else {
            install = .failed(loc.t("Program stoi w miejscu, którego nie da się nadpisać (np. otwarty prosto z Pobranych). Przenieś go do katalogu Aplikacje albo pobierz nową wersję ręcznie.",
                                 "The app sits where it cannot be overwritten (e.g. opened straight from Downloads). Move it to the Applications folder or download the new version manually."))
            return
        }
        Task { await installing(info, app: app) }
    }

    private func installing(_ info: UpdateInfo, app: URL) async {
        lastError = nil
        install = .downloading
        guard await ErrorUpdateManager.shared.downloadUpdate() != nil else {
            install = .failed(withDetail(loc.t("Nie udało się pobrać nowej wersji.",
                                 "Could not download the new version.")))
            return
        }
        guard !isBusy() else { install = .busy; return }
        install = .installing
        await ErrorUpdateManager.shared.installUpdate(relaunch: false)
        // The package returns no verdict; the version on disk under the running app's path does.
        guard RestartAfterUpdate.versionOnDisk(app) == info.latestVersion else {
            install = .failed(withDetail(loc.t("Nie udało się zainstalować nowej wersji. Program działa dalej w obecnej.",
                                 "Could not install the new version. The app keeps running the current one.")))
            return
        }
        do {
            try RestartAfterUpdate.launchAfterExit(pid: ProcessInfo.processInfo.processIdentifier, app: app)
        } catch {
            install = .failed(loc.t("Nowa wersja jest zainstalowana, ale restart się nie udał. Zamknij i otwórz program ręcznie.",
                                 "The new version is installed, but the restart failed. Quit and reopen the app manually."))
            return
        }
        NSApp.terminate(nil)
    }

    private func withDetail(_ sentence: String) -> String {
        guard let lastError, !lastError.isEmpty else { return sentence }
        return sentence + "\n" + lastError
    }

    // MARK: - The user's choice

    /// The download first, then the page — a slow page should not hold up what was clicked for.
    func downloadManually() {
        guard let info = available else { return }
        install = .idle
        if DownloadAddress.allowed(info.downloadURL) { NSWorkspace.shared.open(info.downloadURL) }
        NSWorkspace.shared.open(Self.page)
        closeWindow()
    }

    /// Silences this one version; any newer one speaks up as usual.
    func skip() {
        guard let info = available else { return }
        UserDefaults.standard.set(info.latestVersion, forKey: Self.skippedKey)
        available = nil
        closeWindow()
    }

    // MARK: - Window

    func showWindow() {
        if install != .downloading && install != .installing { install = .idle }
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = loc.t("TokenTime — Aktualizacja", "TokenTime — Update")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdateView(model: self))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

/// "A newer version is available": install and restart, skip this version, or download by hand.
/// Closing the window means "ask me next time" and is none of the three.
struct UpdateView: View {
    @ObservedObject var model: Updates

    private var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var working: Bool { model.install == .downloading || model.install == .installing }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let info = model.available { newer(info) } else if let error = model.checkError { failed(error) } else { upToDate }
        }
        .padding(26)
        .frame(width: 460, alignment: .leading)
    }

    @ViewBuilder
    private func newer(_ info: UpdateInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 30)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("Jest nowsza wersja", "A newer version is available")).font(.system(size: 18, weight: .semibold))
                Text(loc.t("Masz \(current), dostępna jest \(info.latestVersion).", "You have \(current), version \(info.latestVersion) is available.")).foregroundStyle(.secondary)
            }
        }
        if !info.releaseNotes.isEmpty {
            ScrollView {
                Text(verbatim: info.releaseNotes).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
        Text(loc.t("Program pobierze nową wersję, sprawdzi ją, podmieni się i uruchomi ponownie. Konta i ustawienia zostają.", "The app downloads the new version, checks it, replaces itself and restarts. Your accounts and settings stay."))
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        state
        Button(loc.t("Pobierz ręcznie i podmień sam", "Download manually and replace it yourself")) { model.downloadManually() }
            .buttonStyle(.link).font(.callout).disabled(working)
        HStack {
            Button(loc.t("Pomiń tę wersję", "Skip This Version")) { model.skip() }.disabled(working)
            Spacer()
            Button(loc.t("Zainstaluj i uruchom ponownie", "Install and Restart")) { model.installNow() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(working)
        }
    }

    @ViewBuilder
    private var state: some View {
        switch model.install {
        case .idle:
            EmptyView()
        case .downloading, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.install == .downloading
                     ? loc.t("Pobieram i sprawdzam paczkę…", "Downloading and verifying the package…")
                     : loc.t("Instaluję — za chwilę program uruchomi się ponownie…", "Installing — the app will restart in a moment…"))
                    .font(.callout.weight(.medium))
            }
        case .busy:
            Text(loc.t("Program jest zajęty — kliknij ponownie za chwilę.", "The app is busy — click again in a moment."))
                .font(.callout.weight(.medium)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(verbatim: message)
                .font(.callout.weight(.medium)).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func failed(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("Nie udało się sprawdzić aktualizacji", "Could not check for updates")).font(.system(size: 18, weight: .semibold))
                Text(verbatim: error).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        HStack {
            Spacer()
            Button(loc.t("Zamknij", "Close")) { model.closeWindow() }.keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var upToDate: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("Masz najnowszą wersję", "You are up to date")).font(.system(size: 18, weight: .semibold))
                Text(loc.t("Wersja \(current).", "Version \(current).")).foregroundStyle(.secondary)
            }
        }
        HStack {
            Spacer()
            Button(loc.t("Zamknij", "Close")) { model.closeWindow() }.keyboardShortcut(.defaultAction)
        }
    }
}
