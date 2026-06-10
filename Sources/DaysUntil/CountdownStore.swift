import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.bn-l.days-until", category: "CountdownStore")

@MainActor
@Observable
final class CountdownStore {
    var countdowns: [Countdown] {
        didSet { save() }
    }

    /// Flame effect on badges as a countdown approaches day zero.
    var flamesEnabled: Bool {
        didSet {
            defaults.set(flamesEnabled, forKey: Self.flamesKey)
            logger.info("Flames \(self.flamesEnabled ? "enabled" : "disabled", privacy: .public)")
        }
    }

    private let fileURL: URL
    private let defaults: UserDefaults

    private static let flamesKey = "flamesEnabled"
    static let defaultFileURL = URL.applicationSupportDirectory
        .appending(path: "DaysUntil/countdowns.json", directoryHint: .notDirectory)

    /// `fileURL`/`defaults` are injectable so tests never touch real data.
    init(fileURL: URL = CountdownStore.defaultFileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        flamesEnabled = defaults.object(forKey: Self.flamesKey) as? Bool ?? true
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            countdowns = try decoder.decode([Countdown].self, from: data)
            logger.info("Loaded \(self.countdowns.count, privacy: .public) countdowns from \(fileURL.path, privacy: .public)")
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            logger.info("No countdown file yet at \(fileURL.path, privacy: .public) — seeding default countdown")
            countdowns = [Self.defaultCountdown()]
            save()
        } catch {
            logger.error("Failed to load countdowns from \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            countdowns = []
        }
    }

    func add() {
        let countdown = Self.defaultCountdown()
        countdowns.append(countdown)
        logger.info("Added countdown \(countdown.id, privacy: .public) targeting \(countdown.targetDate.formatted(date: .abbreviated, time: .omitted), privacy: .public)")
    }

    func remove(_ id: UUID) {
        countdowns.removeAll { $0.id == id }
        logger.info("Removed countdown \(id, privacy: .public)")
    }

    func countdown(id: UUID) -> Countdown? {
        countdowns.first { $0.id == id }
    }

    static let defaultTitles = [
        "The Big Reveal", "Almost There", "Mark the Calendar", "The Event",
        "Scheduled Chaos", "The Main Event", "Soon™", "Inevitable",
    ]
    static let defaultNotes = [
        "Well, here we are.", "Everything is proceeding as predicted.",
        "No last-minute changes.", "The countdown has officially begun.",
        "Good things come to those who wait.", "You know!",
        "The clock remains undefeated.", "No pressure.",
    ]

    /// Targets noon of the chosen day: deterministic regardless of the
    /// time of day the countdown was created, and whole-second so it
    /// survives ISO-8601 persistence losslessly (sub-second precision
    /// doesn't — caught by the relaunch round-trip test).
    private static func defaultCountdown() -> Countdown {
        let calendar = Calendar.current
        let day = calendar.date(
            byAdding: .day,
            value: Int.random(in: 5...20),
            to: calendar.startOfDay(for: .now)
        ) ?? .now
        return Countdown(
            title: defaultTitles.randomElement() ?? "",
            note: defaultNotes.randomElement() ?? "",
            targetDate: calendar.date(byAdding: .hour, value: 12, to: day) ?? day
        )
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(countdowns)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            logger.debug("Saved \(self.countdowns.count, privacy: .public) countdowns to \(self.fileURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to save countdowns to \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
