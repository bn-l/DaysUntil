import Foundation

struct Countdown: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title = ""
    var note = ""
    var targetDate = Date.now

    /// Whole days from the start of `reference`'s day to the start of the
    /// target day. Negative once the date has passed. SwiftUI bodies must
    /// pass `store.today` here — `.now` is invisible to Observation, so a
    /// view computing from it goes stale at midnight.
    func daysRemaining(asOf reference: Date) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: reference)
        let to = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Wall-clock snapshot — fine outside SwiftUI bodies (badges re-render
    /// via NSCalendarDayChanged), stale inside them.
    var daysRemaining: Int { daysRemaining(asOf: .now) }

    var isToday: Bool { daysRemaining == 0 }
}
