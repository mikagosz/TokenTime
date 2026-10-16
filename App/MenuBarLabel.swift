import SwiftUI

// MARK: - Etykieta w pasku menu

/// Shows the icon plus the shortest active countdown. Refreshed by a light task,
/// because `Text(timerInterval:)` does not work in a `MenuBarExtra` label.
struct MenuBarLabel: View {
    let store: AccountStore
    @State private var now = Date()

    var body: some View {
        let info = store.menuBarInfo(now: now)
        HStack(spacing: 4) {
            Image("MenuBarIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
            if let text = info.text {
                Text(text)
            }
        }
        .task {
            // The label exists from launch, the panel only once opened — so commands
            // from tokentime:// get the store here (`URLCommands.swift`).
            URLCommandRouter.shared.attach(store)
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
