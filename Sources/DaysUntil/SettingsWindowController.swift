import AppKit
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.bn-l.days-until", category: "SettingsWindow")

/// The single floating settings window shared by every menubar popover.
@MainActor
final class SettingsWindowController {
    private let store: CountdownStore
    private var window: NSWindow?

    init(store: CountdownStore) {
        self.store = store
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        logger.info("Settings window shown")
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Countdowns"
        // Floats above normal windows; .moveToActiveSpace brings it to
        // whichever space the user opened it from.
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // Closing only hides it — the same instance is reused on every open.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.center()
        logger.debug("Settings window created")
        return window
    }
}
