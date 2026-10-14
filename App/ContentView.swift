import SwiftUI
import AppKit

// MARK: - App entry

@main
struct TokenTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TokenTimeApp.hostsTests || HelpExport.requested
        ? AccountStore(fileURL: nil, observeTermination: false)
        : AccountStore()

    init() {
        // `--export-help` / `--export-help-window`: PNGs of Help, then quit — before the menu bar item appears.
        HelpExport.runIfRequested()
    }

    /// Under `xcodebuild test` this app is the test host, so its own store would
    /// start talking to the real accounts file in iCloud Drive. The tests never
    /// need it — they check pure functions — so the host store stays local.
    static var hostsTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Hides the Dock icon — the app lives in the menu bar only.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Not as the test host: the tests check pure functions and must not ask the server.
        if !TokenTimeApp.hostsTests { Updates.shared.start() }
        // `--show-help`: the Help window right away — for a look after changes, without opening the panel.
        if CommandLine.arguments.contains("--show-help") { HelpWindow.shared.show() }
    }
}
