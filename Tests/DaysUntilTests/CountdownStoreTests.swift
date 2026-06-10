import Foundation
import Testing
@testable import DaysUntil

/// End-to-end persistence tests against real (temporary) files — each test
/// gets a fresh path and a fresh UserDefaults suite so the user's actual
/// data is never touched.
@MainActor
@Suite("CountdownStore persistence")
struct CountdownStoreTests {
    private func freshFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "daysuntil-tests/\(UUID().uuidString)/countdowns.json")
    }

    private func freshDefaults() throws -> (UserDefaults, cleanup: () -> Void) {
        let suiteName = "daysuntil-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    @Test("First launch seeds one sensible default countdown and writes it to disk")
    func firstRunSeedsDefault() throws {
        let url = freshFileURL()
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }

        let store = CountdownStore(fileURL: url, defaults: defaults)

        #expect(store.countdowns.count == 1)
        let seeded = try #require(store.countdowns.first)
        #expect(CountdownStore.defaultTitles.contains(seeded.title))
        #expect(CountdownStore.defaultNotes.contains(seeded.note))
        #expect((5...20).contains(seeded.daysRemaining))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Countdowns survive a relaunch — full launch-to-launch round-trip")
    func persistsAcrossLaunches() throws {
        let url = freshFileURL()
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let first = CountdownStore(fileURL: url, defaults: defaults)
        first.countdowns[0].title = "Trip to Japan"
        first.countdowns[0].note = "Bring the good camera "  // trailing space must survive
        first.add()

        let relaunched = CountdownStore(fileURL: url, defaults: defaults)

        #expect(relaunched.countdowns == first.countdowns)
        #expect(relaunched.countdowns[0].title == "Trip to Japan")
        #expect(relaunched.countdowns[0].note == "Bring the good camera ")
    }

    @Test("Every mutation hits the disk immediately — no explicit save step")
    func mutationsSaveImmediately() throws {
        let url = freshFileURL()
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let store = CountdownStore(fileURL: url, defaults: defaults)

        store.countdowns[0].title = "Changed without saving"

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let onDisk = try decoder.decode([Countdown].self, from: Data(contentsOf: url))
        #expect(onDisk == store.countdowns)
    }

    @Test("A corrupted file loads as empty instead of crashing or destroying state silently")
    func corruptedFileLoadsEmpty() throws {
        let url = freshFileURL()
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json {][".utf8).write(to: url)

        let store = CountdownStore(fileURL: url, defaults: defaults)

        #expect(store.countdowns.isEmpty)
    }

    @Test("Add appends, remove deletes exactly the matching id")
    func addAndRemove() throws {
        let url = freshFileURL()
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let store = CountdownStore(fileURL: url, defaults: defaults)
        let originalID = try #require(store.countdowns.first).id

        store.add()
        #expect(store.countdowns.count == 2)

        store.remove(originalID)
        #expect(store.countdowns.count == 1)
        #expect(store.countdown(id: originalID) == nil)

        store.remove(UUID())  // unknown id must be a no-op, not a crash
        #expect(store.countdowns.count == 1)
    }

    @Test("Removing every countdown persists an empty list (not a reseeded default)")
    func emptyListPersists() throws {
        let url = freshFileURL()
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let store = CountdownStore(fileURL: url, defaults: defaults)
        store.countdowns.forEach { store.remove($0.id) }

        let relaunched = CountdownStore(fileURL: url, defaults: defaults)

        #expect(relaunched.countdowns.isEmpty)
    }

    @Test("Flames toggle persists across relaunch via UserDefaults")
    func flamesTogglePersists() throws {
        let url = freshFileURL()
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let store = CountdownStore(fileURL: url, defaults: defaults)
        #expect(store.flamesEnabled)  // default is on

        store.flamesEnabled = false

        let relaunched = CountdownStore(fileURL: url, defaults: defaults)
        #expect(!relaunched.flamesEnabled)
    }

    @Test("Default countdowns always land 5–20 days out with title and note from the canned lists")
    func defaultCountdownRanges() throws {
        let url = freshFileURL()
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let store = CountdownStore(fileURL: url, defaults: defaults)

        for _ in 0..<30 { store.add() }

        for countdown in store.countdowns {
            #expect((5...20).contains(countdown.daysRemaining),
                    "got \(countdown.daysRemaining) days for \(countdown.title)")
            #expect(CountdownStore.defaultTitles.contains(countdown.title))
            #expect(CountdownStore.defaultNotes.contains(countdown.note))
        }
    }
}
