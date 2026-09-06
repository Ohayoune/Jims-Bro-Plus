import SwiftUI

/// SPEC §4.1 (D18, revised v1.1): Home leads with the workout. A start card that names the day,
/// the plan and its exercises; a week strip that opens into the month; one activity line.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var showImport: Bool
    @Binding var showWorkout: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                StartCardView(showImport: $showImport, showWorkout: $showWorkout)
                CalendarView()
                Text(HomeActivity.line(sessions: model.sessions))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }
}

/// The start card. One primary action that says what it will do (P5).
private struct StartCardView: View {
    @Environment(AppModel.self) private var model
    @Binding var showImport: Bool
    @Binding var showWorkout: Bool
    @State private var showDiscardConfirm = false
    @State private var previewing: PlanRoute?
    @State private var choosingDay = false

    var body: some View {
        let card = HomeStart.current(library: model.library)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if card.isInProgress {
                    Spacer()
                    Menu {
                        Button("Discard workout", role: .destructive) { showDiscardConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // P5/T1: Start is never blind — the day's exercises are named before you tap it.
            if !card.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(card.exercises.enumerated()), id: \.offset) { _, name in
                        Text(name).font(.footnote).foregroundStyle(.secondary)
                    }
                    if card.more > 0 {
                        Text("and \(card.more) more").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Exercises: " + card.exercises.joined(separator: ", ")
                                    + (card.more > 0 ? ", and \(card.more) more" : ""))
            }

            if let title = card.buttonTitle {
                PrimaryButton(title: title) { act(card) }
            }
            HStack(spacing: 18) {
                if card.isEmpty {
                    Button("Try the sample plan") { Task { await model.importSamplePlan() } }
                    Button("Try a short practice workout") { Task { await model.importPracticePlan() } }
                } else if let planId = card.planId, let dayIndex = card.dayIndex {
                    Button("Preview") { previewing = PlanRoute(id: planId, dayIndex: dayIndex) }
                    Button("Another day") { choosingDay = true }
                }
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            if model.showNotificationBanner {
                Text("Notifications are off, so alerts only sound while the app is open.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $showDiscardConfirm,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { Task { await model.discardSession() } }
            Button("Keep going", role: .cancel) {}
        }
        .confirmationDialog("Which day?", isPresented: $choosingDay, titleVisibility: .visible) {
            if let plan = model.activePlan {
                ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                    Button(day.name) { start(planId: plan.id, dayIndex: index) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $previewing) { route in
            NavigationStack { PlanDetailView(planId: route.id, showWorkout: $showWorkout) }
                .environment(model)
        }
    }

    private func act(_ card: HomeStart) {
        if card.isEmpty { showImport = true; return }
        if card.isInProgress { showWorkout = true; return }
        guard let planId = card.planId, let dayIndex = card.dayIndex else { return }
        start(planId: planId, dayIndex: dayIndex)
    }

    private func start(planId: UUID, dayIndex: Int) {
        Task {
            try? await model.startDay(planId: planId, dayIndex: dayIndex)
            showWorkout = true
        }
    }
}

/// Identifies the plan a Preview sheet opens.
private struct PlanRoute: Identifiable {
    let id: UUID
    let dayIndex: Int
}

/// SPEC §4.1 (v1.1): a 7-day strip by default, with a disclosure to the month grid. Cells are
/// at least 44 pt in both (P6, O73).
private struct CalendarView: View {
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
                Text(expanded ? month.formatted(.dateTime.month(.wide).year()) : "This week")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
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
                            isSelected: selected.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false)
                        .contentShape(Rectangle())
                        .onTapGesture { tapped(day) }
                }
            }

            if let line = selectedLine(days) {
                Text(line).font(.footnote).foregroundStyle(.secondary)
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

private struct DayCell: View {
    let day: CalendarDay
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.callout)
                .monospacedDigit()
            marker
                .frame(width: 5, height: 5)
        }
        // P6/O73: a 44 pt target, in the week strip and in the month grid alike.
        .frame(minWidth: 44, minHeight: 44)
        .frame(maxWidth: .infinity)
        .overlay {
            if isToday || isSelected {
                Circle().stroke(isSelected ? Color.accentColor : .secondary, lineWidth: 1)
                    .frame(width: 38, height: 38)
            }
        }
    }

    @ViewBuilder private var marker: some View {
        switch day.entry {
        case .completed: Circle().fill(Color.accentColor)
        case .projected: Circle().stroke(Color.accentColor, lineWidth: 1)
        case .rest: Circle().fill(Color.secondary.opacity(0.45))
        case .none: Color.clear
        }
    }
}
