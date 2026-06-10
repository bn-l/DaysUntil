import AppKit
import QuartzCore
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.bn-l.days-until", category: "CountdownStatusItem")

/// One menubar icon and its popover, bound to a single countdown.
@MainActor
final class CountdownStatusItem: NSObject, NSPopoverDelegate {
    let countdownID: UUID
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var lastRenderKey: String?
    private var clickMonitor: Any?

    private static let flashAnimationKey = "flash"

    init(countdown: Countdown, store: CountdownStore, flamesEnabled: Bool, openSettings: @escaping @MainActor () -> Void) {
        countdownID = countdown.id
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.autosaveName = countdown.id.uuidString
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(
            store: store,
            countdownID: countdown.id,
            openSettings: { [weak self] in
                self?.popover.performClose(nil)
                openSettings()
            }
        ))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        update(with: countdown, flamesEnabled: flamesEnabled)
        logger.info("Created status item for countdown \(countdown.id, privacy: .public)")
    }

    func update(with countdown: Countdown, flamesEnabled: Bool) {
        let days = countdown.daysRemaining
        statusItem.button?.toolTip = countdown.title.isEmpty
            ? "\(days) days"
            : "\(countdown.title) — \(days) days"

        let isDark = statusItem.button?.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let intensity = flamesEnabled && (0...5).contains(days)
            ? (6.0 - Double(days)) / 6.0
            : 0
        let renderKey = "\(days)|\(intensity)|\(isDark)"
        if renderKey != lastRenderKey {
            statusItem.button?.image = BadgeIcon.image(
                days: days,
                flameIntensity: intensity,
                darkAppearance: isDark
            )
            lastRenderKey = renderKey
        }
        countdown.isToday ? startFlashing() : stopFlashing()
    }

    /// Must be called before releasing the instance — `NSStatusBar` keeps
    /// the item on screen until it is explicitly removed.
    func tearDown() {
        popover.performClose(nil)
        stopClickMonitor()
        NSStatusBar.system.removeStatusItem(statusItem)
        logger.info("Removed status item for countdown \(self.countdownID, privacy: .public)")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            logger.error("togglePopover: status item has no button")
            return
        }
        if popover.isShown {
            logger.debug("Closing popover for \(self.countdownID, privacy: .public)")
            popover.performClose(nil)
        } else {
            logger.debug("Showing popover for \(self.countdownID, privacy: .public)")
            // Transient dismissal only works while the app is active, and an
            // accessory app isn't activated by a status item click — without
            // this the popover only closes after it is clicked once itself.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startClickMonitor()
        }
    }

    /// Backstop for the activation quirk above: global monitors only see
    /// events delivered to *other* apps, i.e. exactly the outside clicks
    /// that should dismiss the popover.
    private func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popover.performClose(nil)
            }
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopClickMonitor()
    }

    private func startFlashing() {
        guard let button = statusItem.button else {
            logger.error("startFlashing: status item has no button")
            return
        }
        button.wantsLayer = true
        guard button.layer?.animation(forKey: Self.flashAnimationKey) == nil else { return }
        logger.info("Day-zero flash started for \(self.countdownID, privacy: .public)")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.0
        pulse.toValue = 1.0
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        button.layer?.add(pulse, forKey: Self.flashAnimationKey)
    }

    private func stopFlashing() {
        guard statusItem.button?.layer?.animation(forKey: Self.flashAnimationKey) != nil else { return }
        statusItem.button?.layer?.removeAnimation(forKey: Self.flashAnimationKey)
        logger.info("Day-zero flash stopped for \(self.countdownID, privacy: .public)")
    }
}
