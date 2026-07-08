import SwiftUI

// MARK: - Etykieta w pasku menu

/// Pokazuje ikonę + najkrótszy aktywny countdown. Odświeżana lekkim taskiem,
/// bo `Text(timerInterval:)` nie działa w etykiecie `MenuBarExtra`.
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
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
