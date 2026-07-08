import SwiftUI
import AppKit

// MARK: - App entry

@main
struct TokenTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AccountStore()

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

/// Ukrywa ikonę w Docku — aplikacja żyje tylko w pasku menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
