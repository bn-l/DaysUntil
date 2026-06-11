import AppKit
import Observation
import OSLog

private let logger = Logger(subsystem: "com.bn-l.days-until", category: "StatusItemController")

/// Owns one `CountdownStatusItem` per countdown and keeps the menubar in
/// sync with the store: additions, removals, edits, and day rollovers.
@MainActor
final class StatusItemController: NSObject {
    private let store: CountdownStore
    private let openSettings: @MainActor () -> Void
    private var items: [UUID: CountdownStatusItem] = [:]
    private var placeholder: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?

    init(store: CountdownStore, openSettings: @escaping @MainActor () -> Void) {
        self.store = store
        self.openSettings = openSettings
        super.init()

        NotificationCenter.default.addObserver(
            self, selector: #selector(dayChanged),
            name: .NSCalendarDayChanged, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(dayChanged),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        // Flame badges are non-template images, so they don't adapt to
        // light/dark menubar changes by themselves — re-render on change.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                logger.info("System appearance changed — re-rendering badges")
                self?.sync()
            }
        }

        observeStore()
        sync()
    }

    /// Re-arming Observation loop: `onChange` fires once per registration,
    /// so re-register after every sync.
    private func observeStore() {
        withObservationTracking {
            _ = store.countdowns
            _ = store.flamesEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                sync()
                observeStore()
            }
        }
    }

    @objc private nonisolated func dayChanged() {
        Task { @MainActor in
            logger.info("Day changed or woke from sleep — refreshing badges")
            self.store.refreshDay()
            self.sync()
        }
    }

    private func sync() {
        let current = store.countdowns

        let currentIDs = Set(current.map(\.id))
        for (id, item) in items where !currentIDs.contains(id) {
            item.tearDown()
            items[id] = nil
        }

        for countdown in current {
            if let item = items[countdown.id] {
                item.update(with: countdown, flamesEnabled: store.flamesEnabled)
            } else {
                items[countdown.id] = CountdownStatusItem(
                    countdown: countdown,
                    store: store,
                    flamesEnabled: store.flamesEnabled,
                    openSettings: openSettings
                )
            }
        }

        syncPlaceholder(visible: current.isEmpty)
        logger.debug("Synced \(self.items.count, privacy: .public) status items")
    }

    /// With no countdowns there would be no menubar presence at all — and no
    /// way back into the app. Show a single calendar icon that opens settings.
    private func syncPlaceholder(visible: Bool) {
        if visible, placeholder == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(
                systemSymbolName: "calendar.badge.plus",
                accessibilityDescription: "Add a countdown"
            )
            item.button?.target = self
            item.button?.action = #selector(openSettingsAction)
            placeholder = item
            logger.info("No countdowns — showing placeholder status item")
        } else if !visible, let item = placeholder {
            NSStatusBar.system.removeStatusItem(item)
            placeholder = nil
            logger.info("Removed placeholder status item")
        }
    }

    @objc private func openSettingsAction() {
        openSettings()
    }
}
