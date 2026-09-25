import SwiftUI

// D63 (v1.7, T3): the calendar is History's. Its drawing is the one Home had in v1.6; what
// changed is where it sits, the tapped-day line (Core's `CalendarText.line` — no Start this,
// since a workout starts on Today) and how a finished day opens: pushed on History's stack,
// like its row below, where over Home it opened in a sheet.
/// SPEC §4.10 (v1.1, D18): a 7-day strip by default, with a disclosure to the month grid. Cells
/// are at least 44 pt in both (P6, O73).
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var month = Date()
    @State private var selected: Date?
    @State private var expanded = false
    /// A day with more than one session offers a chooser before it opens.
    @State private var choosingAmong: [Session]?
    /// Opens a finished workout; History pushes it.
    private let open: (UUID) -> Void

    init(open: @escaping (UUID) -> Void) { self.open = open }

    private var calendar: Calendar { .current }

    var body: some View {
        let days = expanded
            ? CalendarProjection.entries(month: month, activePlan: model.activePlan, plans: model.plans,
                                         sessions: model.sessions, swaps: model.swaps, today: Date())
            : CalendarProjection.week(containing: Date(), activePlan: model.activePlan, plans: model.plans,
                                      sessions: model.sessions, swaps: model.swaps, today: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // D59 (v1.6): ink, not accent — `.primary` inside an accent-styled row resolved
                // to blue, and a header that looks like a link gets tapped.
                Text(expanded ? month.formatted(.dateTime.month(.wide).year()) : "This week")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                Spacer()
                if expanded {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month")
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month")
                        .padding(.trailing, 4)
                }
                // D64 (v1.7): Month is earned by a workout older than this week (§6.40); until
                // then the strip is the whole record. Week stays while the grid is open, so it
                // can always be closed.
                if expanded || Gates.month(sessions: model.sessions, today: Date(), calendar: calendar) {
                    Button(expanded ? "Week" : "Month") {
                        withAnimation(.snappy) {
                            expanded.toggle()
                            month = Date()
                            selected = nil
                        }
                    }
                    .font(.footnote)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                // Weekday initials repeat (S M T W T F S), so index them rather than use the value.
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2).foregroundStyle(.secondary)
                }
                if expanded {
                    ForEach(0..<leadingBlanks(days), id: \.self) { _ in Color.clear.frame(height: 44) }
                }
                ForEach(days, id: \.date) { day in
                    DayCell(day: day, isToday: calendar.isDateInToday(day.date),
                            isSelected: selected.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false,
                            label: CalendarText.label(day.entry, plans: model.plans),
                            colour: day.entry.dayColour(plans: model.plans),
                            spoken: CalendarText.spoken(day, plans: model.plans, calendar: calendar))
                        .contentShape(Rectangle())
                        .onTapGesture { tapped(day) }
                }
            }

            if let day = selectedDay(days),
               let line = CalendarText.line(day, plans: model.plans, calendar: calendar) {
                if line.sessions.isEmpty {
                    // A planned or rest day's line is text (D63): a workout starts on Today.
                    Text(line.text).font(.footnote).foregroundStyle(.secondary)
                } else {
                    // A finished day's line is the way into it (D39, v1.2). v1.1 wanted a second
                    // tap on the cell, which nothing on the screen said you could do.
                    Button { openAny(line.sessions) } label: {
                        HStack(spacing: 4) {
                            Text(line.text)
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .font(.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHint("Opens this workout")
                }
            }
        }
        .confirmationDialog("Which workout?", isPresented: Binding(isPresent: $choosingAmong)) {
            if let sessions = choosingAmong {
                ForEach(sessions) { session in
                    Button("\(session.dayName) · \(session.startedAt.formatted(date: .omitted, time: .shortened))") {
                        choosingAmong = nil
                        open(session.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) { choosingAmong = nil }
        }
    }

    /// SPEC §4.10: tapping a day shows the line; tapping the same, already-selected, finished
    /// day again opens it — a chooser first when it holds more than one session (v1.1).
    private func tapped(_ day: CalendarDay) {
        let alreadySelected = selected.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false
        if alreadySelected {
            if case let .completed(sessions) = day.entry { openAny(sessions) }
            selected = nil
        } else {
            selected = day.date
        }
    }

    private func openAny(_ sessions: [Session]) {
        if sessions.count > 1 { choosingAmong = sessions } else if let only = sessions.first { open(only.id) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func leadingBlanks(_ days: [CalendarDay]) -> Int {
        guard let first = days.first?.date else { return 0 }
        return (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    }

    private func step(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) { month = next }
        selected = nil
    }

    private func selectedDay(_ days: [CalendarDay]) -> CalendarDay? {
        guard let selected else { return nil }
        return days.first { calendar.isDate($0.date, inSameDayAs: selected) }
    }
}

/// D38 (v1.2): a cell says which workout it is. v1.1 drew every day as the same 5 pt dot, so
/// the shape of a week — two on, one off — could not be read off the grid at all.
private struct DayCell: View {
    let day: CalendarDay
    let isToday: Bool
    let isSelected: Bool
    let label: String?
    /// D65 (v1.7): the day's colour — a finished day's fill, a planned day's name.
    let colour: DayColour?
    let spoken: String

    var body: some View {
        VStack(spacing: 1) {
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(numberColour)
            // The label is the point; a rest day gets a short dash instead, which reads as a
            // gap rather than as another kind of workout.
            Group {
                if let label {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if case .rest = day.entry {
                    Text("–").font(.system(size: 9))
                } else {
                    Text(" ").font(.system(size: 9))
                }
            }
            .foregroundStyle(labelColour)
        }
        // P6/O73: a 44 pt target, in the week strip and in the month grid alike.
        .frame(minWidth: 44, minHeight: 44)
        .frame(maxWidth: .infinity)
        .background {
            // A finished day is filled; a planned one is its label alone — D59 (v1.6): twenty
            // outlined boxes in a six-day month shouted as loudly as the two done days and
            // Start. D65 (v1.7): both in the day's colour, where the reserved green and the
            // accent were, so the grid says which day as well as whether (§6.41).
            if case .completed = day.entry {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(dayColour.opacity(0.18))
                    .frame(width: 38, height: 40)
            }
        }
        .overlay {
            if isToday || isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary, lineWidth: isSelected ? 2 : 1.5)
                    .frame(width: 38, height: 40)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// D65 (v1.7): the day's colour; grey for a finished day whose plan no longer has it.
    private var dayColour: Color { colour?.color ?? .secondary }

    private var numberColour: Color {
        switch day.entry {
        case .completed: return dayColour
        case .projected, .own: return .primary
        case .rest, .none: return .secondary
        }
    }

    /// D76 (v1.9): an own day is planned but in no plan, so its label is ink, not a colour.
    private var labelColour: Color {
        switch day.entry {
        case .completed, .projected: return dayColour
        case .own: return .primary
        case .rest, .none: return .secondary
        }
    }
}
