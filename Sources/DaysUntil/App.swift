import AppKit
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.bn-l.days-until", category: "App")

@main
@MainActor
enum DaysUntilMain {
    // NSApplication.delegate is unowned — keep the strong reference here.
    private static var delegate: AppDelegate?

    static func main() {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-icons"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            BadgeIcon.writePreviews(to: URL(filePath: CommandLine.arguments[flagIndex + 1], directoryHint: .isDirectory))
            return
        }
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-settings"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            writeSettingsPreview(to: URL(filePath: CommandLine.arguments[flagIndex + 1], directoryHint: .notDirectory))
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    /// Debug helper (`--render-settings <png>`): snapshot of the settings
    /// view against a throwaway store, for layout inspection. Uses a real
    /// window parked far offscreen — ImageRenderer can't rasterize the
    /// Form's NSScrollView-backed internals.
    private static func writeSettingsPreview(to url: URL) {
        _ = NSApplication.shared
        let store = CountdownStore(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "daysuntil-preview/\(UUID().uuidString).json"),
            defaults: UserDefaults(suiteName: "daysuntil-preview") ?? .standard
        )
        store.countdowns[0].title = "Trip to Japan"
        store.countdowns[0].note = "Bring the good camera."

        let window = NSWindow(
            contentRect: NSRect(x: -5000, y: -5000, width: 480, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.orderFront(nil)
        RunLoop.current.run(until: .now + 0.5)

        guard let contentView = window.contentView,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            logger.error("Settings preview render failed")
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            logger.error("Settings preview encode failed")
            return
        }
        do {
            try png.write(to: url)
            window.close()
        } catch {
            logger.error("Settings preview write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: CountdownStore?
    private var statusItems: StatusItemController?
    private var settingsWindow: SettingsWindowController?

    /// Posted by a second launch just before it quits, so the surviving
    /// instance can make the relaunch visibly do something.
    private static let showSettingsNotification = Notification.Name("com.bn-l.days-until.show-settings")

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if alreadyRunning {
            logger.notice("Another instance is already running — deferring to it and quitting")
            DistributedNotificationCenter.default().postNotificationName(
                Self.showSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("DaysUntil launching")
        // LSUIElement in Info.plist covers the bundled app; this covers
        // running the bare executable via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        // Never displayed (accessory app), but key equivalents — ⌘Q, ⌘W,
        // and clipboard/undo shortcuts in text fields — only work when a
        // main menu defines them.
        NSApp.mainMenu = Self.makeMainMenu()

        let store = CountdownStore()
        let settings = SettingsWindowController(store: store)
        self.store = store
        settingsWindow = settings
        statusItems = StatusItemController(store: store) {
            settings.show()
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showSettingsRequested),
            name: Self.showSettingsNotification, object: nil
        )
    }

    @objc private nonisolated func showSettingsRequested() {
        Task { @MainActor in
            logger.info("Second instance launch detected — showing settings")
            self.settingsWindow?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("DaysUntil terminating")
    }

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DaysUntil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }
}
