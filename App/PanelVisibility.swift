import AppKit
import SwiftUI

// MARK: - Widoczność panelu

extension EnvironmentValues {
    /// Whether the menu bar panel is on screen. `true` by default, so a view that
    /// never learns otherwise behaves as it always did.
    @Entry var panelVisible: Bool = true
}

/// Reports whether the window hosting this view is on screen.
///
/// A `.window` menu bar extra is ordered out, not destroyed, when it closes — its
/// SwiftUI content lives on and `onDisappear` is not a reliable signal. The
/// window's occlusion state is: it loses `.visible` the moment the panel closes.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> Tracker {
        let tracker = Tracker()
        tracker.report = { visible in
            // Never during a view update — the change goes out one turn later.
            Task { @MainActor in self.visible = visible }
        }
        return tracker
    }

    func updateNSView(_ nsView: Tracker, context: Context) {}

    final class Tracker: NSView {
        var report: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            report?(window.occlusionState.contains(.visible))
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.report?(window.occlusionState.contains(.visible))
                }
            }
        }
    }
}
