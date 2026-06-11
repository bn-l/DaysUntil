import Foundation
import Testing
@testable import DaysUntil

@Suite("Countdown day math")
struct CountdownTests {
    private var calendar: Calendar { Calendar.current }

    @Test("Target right now is day zero")
    func todayIsZero() {
        let countdown = Countdown(targetDate: .now)

        #expect(countdown.daysRemaining == 0)
        #expect(countdown.isToday)
    }

    @Test("Time of day never changes the day count — one second into today and one second before midnight are both day zero")
    func timeOfDayIsIrrelevant() throws {
        let startOfToday = calendar.startOfDay(for: .now)
        let almostMidnight = try #require(
            calendar.date(byAdding: DateComponents(hour: 23, minute: 59, second: 59), to: startOfToday)
        )

        let early = Countdown(targetDate: startOfToday.addingTimeInterval(1))
        let late = Countdown(targetDate: almostMidnight)

        #expect(early.daysRemaining == 0)
        #expect(late.daysRemaining == 0)
    }

    @Test("Whole-day offsets", arguments: [1, 2, 30, 100, 365, 1000, -1, -30])
    func wholeDayOffsets(offset: Int) throws {
        let target = try #require(calendar.date(byAdding: .day, value: offset, to: .now))

        let countdown = Countdown(targetDate: target)

        #expect(countdown.daysRemaining == offset)
        #expect(countdown.isToday == (offset == 0))
    }

    @Test("Day count rolls over at midnight of the reference day, not 24h elapsed")
    func rolloverAtMidnight() throws {
        let startOfToday = calendar.startOfDay(for: .now)
        let target = try #require(
            calendar.date(byAdding: DateComponents(day: 12, hour: 12), to: startOfToday)
        )
        let lateTonight = try #require(
            calendar.date(byAdding: DateComponents(hour: 23, minute: 59, second: 59), to: startOfToday)
        )
        let justPastMidnight = try #require(
            calendar.date(byAdding: DateComponents(day: 1, second: 1), to: startOfToday)
        )

        let countdown = Countdown(targetDate: target)

        #expect(countdown.daysRemaining(asOf: lateTonight) == 12)
        #expect(countdown.daysRemaining(asOf: justPastMidnight) == 11)
    }

    @Test("Codable round-trip preserves everything")
    func codableRoundTrip() throws {
        let original = Countdown(title: "Sp ace™", note: "line one\nline two", targetDate: .now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Countdown.self, from: encoder.encode(original))

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.note == original.note)
        // ISO-8601 has second precision; identity of the day is what matters.
        #expect(abs(decoded.targetDate.timeIntervalSince(original.targetDate)) < 1)
    }
}
