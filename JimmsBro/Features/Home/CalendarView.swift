import SwiftUI

// D63 (v1.7, T3): the calendar leaves Today for History. Its drawing is unchanged; only
// its file is — it was `private` inside HomeView.swift until T1 took it off Today.
/// SPEC §4.1 (v1.1): a 7-day strip by default, with a disclosure to the month grid. Cells are
/// at least 44 pt in both (P6, O73).
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var month = Date()
    @State private var selected: Date?
    @State private var expanded = false
    /// Tapping an already-selected completed day opens it (SPEC §4.1); a day with more than
    /// one session offers a chooser first.
    @State private var openSessionId: UUID?
    @State private var choosingAmong: [Session]?

    private var calendar: Calendar { .current }

    var body: some View {
        let days = expanded
            ? CalendarProjection.entries(month: month, activePlan: model.activePlan,
                                         sessions: model.sessions, today: Date())
            : CalendarProjection.week(containing: Date(), activePlan: model.activePlan,
                                      sessions: model.sessions, today: Date())
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
                Button(expanded ? "Week" : "Month") {
                    withAnimation(.snappy) {
                        expanded.toggle()
                        month = Date()
                        selected = nil
                    }
                }
                .font(.footnote)
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
                            spoken: CalendarText.spoken(day, plans: model.plans, calendar: calendar))
                        .contentShape(Rectangle())
                        .onTapGesture { tapped(day) }
                }
            }

            if let line = selectedLine(days) {
                // A completed day's line is the way into it (D39, v1.2). v1.1 wanted a second
                // tap on the cell, which nothing on the screen said you could do.
                if let day = selectedDay(days), case let .completed(sessions) = day.entry,
                   !sessions.isEmpty {
                    Button {
                        if sessions.count == 1 { openSessionId = sessions[0].id }
                        else { choosingAmong = sessions }
                    } label: {
                        HStack(spacing: 4) {
                            Text(line)
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .font(.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHint("Opens this workout")
                } else {
                    Text(line).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Which workout?", isPresented: Binding(
            get: { choosingAmong != nil }, set: { if !$0 { choosingAmong = nil } })) {
            if let sessions = choosingAmong {
                ForEach(sessions) { session in
                    Button("\(session.dayName) · \(session.startedAt.formatted(date: .omitted, time: .shortened))") {
                        openSessionId = session.id
                        choosingAmong = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { choosingAmong = nil }
        }
        .sheet(isPresented: Binding(get: { openSessionId != nil }, set: { if !$0 { openSessionId = nil } })) {
            if let id = openSessionId {
                NavigationStack { SessionDetailView(sessionId: id) }.environment(model)
            }
        }
    }

    /// SPEC §4.1: tapping a day shows the line; tapping the same, already-selected, completed
    /// day again opens it — a chooser first when it holds more than one session (v1.1).
    private func tapped(_ day: CalendarDay) {
        let alreadySelected = selected.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false
        if alreadySelected {
            if case let .completed(sessions) = day.entry {
                if sessions.count == 1 { openSessionId = sessions[0].id } else { choosingAmong = sessions }
            }
            selected = nil
        } else {
            selected = day.date
        }
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

    /// One line under the grid; rest days show nothing (SPEC §4.1).
    private func selectedLine(_ days: [CalendarDay]) -> String? {
        guard let selected,
              let day = days.first(where: { calendar.isDate($0.date, inSameDayAs: selected) })
        else { return nil }
        let stamp = day.date.formatted(.dateTime.weekday(.abbreviated).day())
        switch day.entry {
        case let .completed(sessions):
            guard let session = sessions.first else { return nil }
            let minutes = Int(SessionStats.duration(session)) / 60
            return "\(stamp) · \(session.dayName) · \(minutes) min"
        case let .projected(planId, dayIndex):
            guard let plan = model.plans.first(where: { $0.id == planId }),
                  let name = plan.days[safe: dayIndex]?.name else { return nil }
            return "\(stamp) · \(name) · projected"
        case .rest:
            return "\(stamp) · Rest day"
        case .none:
            return nil
        }
    }
}

/// D38 (v1.2): a cell says which workout it is. v1.1 drew every day as the same 5 pt dot, so
/// the shape of a week — two on, one off — could not be read off the grid at all.
private struct DayCell: View {
    let day: CalendarDay
    let isToday: Bool
    let isSelected: Bool
    let label: String?
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
            // A finished day is filled in the colour reserved for "this happened" (§4.0);
            // a planned one is outlined. Both read at a glance; a dot did not.
            // D59 (v1.6): a planned day is its label in the accent, no box — twenty outlined
            // boxes in a six-day month shouted as loudly as the two done days and Start.
            if case .completed = day.entry {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.done.opacity(0.18))
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

    private var numberColour: Color {
        switch day.entry {
        case .completed: return Color.done
        case .projected: return .primary
        case .rest, .none: return .secondary
        }
    }

    private var labelColour: Color {
        switch day.entry {
        case .completed: return Color.done
        case .projected: return Color.accentColor
        case .rest, .none: return .secondary
        }
    }
}
