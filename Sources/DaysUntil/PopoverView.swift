import SwiftUI

struct PopoverView: View {
    let store: CountdownStore
    let countdownID: UUID
    let openSettings: @MainActor () -> Void

    var body: some View {
        if let countdown = store.countdown(id: countdownID) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(countdown.title.isEmpty ? "Untitled" : countdown.title)
                        .font(.headline)
                    Spacer()
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("Open settings")
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(abs(countdown.daysRemaining))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(caption(for: countdown.daysRemaining))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text(countdown.targetDate.formatted(date: .complete, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !countdown.note.isEmpty {
                    Divider()
                    Text(countdown.note)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if countdown.daysRemaining <= 0 {
                    Divider()
                    Button("Remove Countdown", systemImage: "trash", role: .destructive) {
                        store.remove(countdown.id)
                    }
                }
            }
            .padding(14)
            .frame(width: 280, alignment: .leading)
        }
    }

    private func caption(for days: Int) -> String {
        switch days {
        case 0: "it's today 🎉"
        case 1: "day to go"
        case -1: "day ago"
        case ..<0: "days ago"
        default: "days to go"
        }
    }
}
