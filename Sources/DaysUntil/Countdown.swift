import Foundation

struct Countdown: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title = ""
    var note = ""
    var targetDate = Date.now

    /// Whole days from the start of today to the start of the target day.
    /// Negative once the date has passed.
    var daysRemaining: Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: .now)
        let to = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    var isToday: Bool { daysRemaining == 0 }
}
