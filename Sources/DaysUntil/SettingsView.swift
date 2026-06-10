import SwiftUI

struct SettingsView: View {
    @Bindable var store: CountdownStore

    var body: some View {
        VStack(spacing: 0) {
            if store.countdowns.isEmpty {
                ContentUnavailableView(
                    "No Countdowns",
                    systemImage: "calendar.badge.plus",
                    description: Text("Add a countdown to put it on the menubar.")
                )
                .frame(maxHeight: .infinity)
            } else {
                Form {
                    ForEach($store.countdowns) { $countdown in
                        CountdownEditorSection(countdown: $countdown) {
                            store.remove(countdown.id)
                        }
                    }

                    Section {
                        Toggle("Flames as day zero approaches", isOn: $store.flamesEnabled)
                    }
                }
                .formStyle(.grouped)
            }

            Divider()
            HStack {
                Button("Add Countdown", systemImage: "plus") {
                    store.add()
                }
                Spacer()
                Button("Quit DaysUntil") {
                    NSApp.terminate(nil)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 460, minHeight: 380)
    }
}

/// SwiftUI's field-style date pickers always present the system's tiny
/// calendar overlay when clicked — NSDatePicker.presentsCalendarOverlay,
/// which SwiftUI doesn't expose. Hosting the same built-in control directly
/// lets us turn that off, leaving the popover calendar as the only calendar.
private struct DateStepperField: NSViewRepresentable {
    @Binding var date: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .yearMonthDay
        picker.datePickerMode = .single
        picker.presentsCalendarOverlay = false
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        if picker.dateValue != date {
            picker.dateValue = date
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(date: $date)
    }

    @MainActor
    final class Coordinator: NSObject {
        var date: Binding<Date>

        init(date: Binding<Date>) {
            self.date = date
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            date.wrappedValue = sender.dateValue
        }
    }
}

/// The text fields escape the grouped form's automatic field styling
/// (bordered, `labelsHidden`, explicit leading alignment) because the form
/// right-aligns field text and AppKit's typesetter "hangs" trailing
/// whitespace in right-aligned text — a typed space doesn't move the caret
/// until the next glyph arrives. Genuinely left-aligned fields render
/// trailing spaces immediately. Title/note also stay in row-local @State so
/// per-keystroke store saves never write back into the active field editor.
private struct CountdownEditorSection: View {
    @Binding var countdown: Countdown
    let onRemove: () -> Void

    @State private var title: String
    @State private var note: String
    @State private var showingCalendar = false

    private static let calendarScale: CGFloat = 1.8

    init(countdown: Binding<Countdown>, onRemove: @escaping () -> Void) {
        _countdown = countdown
        self.onRemove = onRemove
        _title = State(initialValue: countdown.wrappedValue.title)
        _note = State(initialValue: countdown.wrappedValue.note)
    }

    var body: some View {
        Section {
            LabeledContent("Title") {
                TextField("Title", text: $title, prompt: Text("Title"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)
            }
            LabeledContent("Date") {
                HStack(spacing: 6) {
                    DateStepperField(date: $countdown.targetDate)
                        .fixedSize()
                    Button {
                        showingCalendar = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .buttonStyle(.borderless)
                    .help("Pick from calendar")
                    .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                        // The graphical picker is the fixed-size AppKit
                        // NSDatePicker (139×148 intrinsic) — a bigger frame
                        // only pads it. scaleEffect genuinely enlarges it:
                        // SwiftUI applies a layer transform that AppKit
                        // hit-testing follows (verified empirically), so
                        // clicks land on the right day cells.
                        DatePicker("Date", selection: $countdown.targetDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .scaleEffect(Self.calendarScale)
                            .frame(width: 139 * Self.calendarScale, height: 148 * Self.calendarScale)
                            .padding(16)
                    }
                }
            }
            LabeledContent("Note") {
                TextField("Note", text: $note, prompt: Text("Note"), axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2...5)
                    .frame(maxWidth: .infinity)
            }
            LabeledContent("Days") {
                Text("\(countdown.daysRemaining)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
        }
        .onChange(of: title) { countdown.title = title }
        .onChange(of: note) { countdown.note = note }
        // Back-sync for store-side changes from elsewhere; the equality
        // guards stop the commit above from ping-ponging.
        .onChange(of: countdown.title) { if countdown.title != title { title = countdown.title } }
        .onChange(of: countdown.note) { if countdown.note != note { note = countdown.note } }
    }
}
