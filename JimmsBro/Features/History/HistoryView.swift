import SwiftUI

/// SPEC §4.10: the calendar and the week's line (D63, v1.7), then sessions newest first,
/// grouped by month.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    @State private var path: [HistoryRoute] = []
    /// D25 (v1.1): swipe-to-delete confirms, matching every other delete path.
    @State private var confirmDeleteId: UUID?
    /// D45 (v1.3): the picker behind "Import from another app".
    @State private var choosingHistory = false
    /// D62 (v1.7): the gear, top-left, pushes Settings — the same place as on Today.
    @State private var showingSettings = false

    /// D64 (v1.7): Metrics and Find an exercise are earned by the first workout (§6.40) —
    /// before it there is nothing to count or to find.
    private var finding: Bool { Gates.metricsAndFind(sessions: model.sessions) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // D63 (v1.7): the calendar is the record's — what happened and what the
                // plan expects — so History opens with it, the week's line under it. A
                // finished day opens here, pushed like its row below.
                Section {
                    CalendarView { path.append(.session($0)) }
                    // With no workouts the strip still shows: the plan's week is worth
                    // seeing on day one.
                    Text(model.sessions.isEmpty ? "No workouts yet"
                                                : HomeActivity.line(sessions: model.sessions))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.sessions.isEmpty {
                    // D45 (v1.3): the one place an empty History can offer what fills it.
                    Section {
                        Button("Import from another app") { choosingHistory = true }
                    } footer: {
                        Text("Finished workouts appear here.")
                    }
                }
                if finding {
                    // D39 (v1.2): the numbers over time, one tap from the list of workouts
                    // that produced them.
                    Section {
                        NavigationLink(value: HistoryRoute.metrics) {
                            Label("Metrics", systemImage: "chart.bar")
                        }
                        // D66 (v1.7): the one way to an exercise's chart. D59 added the row
                        // because the search field was not drawn on every iOS; the field was
                        // then a second way to the same list, and it went.
                        NavigationLink(value: HistoryRoute.exercises) {
                            Label("Find an exercise", systemImage: "magnifyingglass")
                        }
                    }
                }
                // D54 (v1.5): the goals, and how close each is — once there is a workout
                // to measure them against (D64, §6.40).
                if Gates.goals(sessions: model.sessions) {
                    GoalsSection()
                }
                ForEach(model.historyMonths) { month in
                    Section(month.title) {
                        ForEach(month.sessions) { session in
                            NavigationLink(value: HistoryRoute.session(session.id)) {
                                row(session)
                            }
                        }
                        .onDelete { offsets in
                            confirmDeleteId = offsets.first.map { month.sessions[$0].id }
                        }
                    }
                }
            }
            .navigationDestination(for: HistoryRoute.self) { route in
                switch route {
                case let .session(id): SessionDetailView(sessionId: id)
                case let .exercise(name, units): ExerciseHistoryView(name: name, units: units)
                case .metrics: MetricsView()
                case .exercises: ExercisesListView()
                }
            }
            .navigationTitle("History")
            // D62 (v1.7): Settings, from the same gear as Today's, in the same place.
            .settingsGear($showingSettings)
            .historyImportFlow(choosing: $choosingHistory)
            .confirmationDialog("Delete this workout?", isPresented: Binding(
                get: { confirmDeleteId != nil }, set: { if !$0 { confirmDeleteId = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = confirmDeleteId { Task { await model.deleteHistorySession(id) } }
                    confirmDeleteId = nil
                }
                Button("Cancel", role: .cancel) { confirmDeleteId = nil }
            }
            .task {
                #if DEBUG
                // Debug-only: open the newest session, or one exercise, for screenshot runs.
                let arguments = ProcessInfo.processInfo.arguments
                await model.waitUntilLoaded()
                if arguments.contains("-uiSessionDetail"),
                   let newest = model.historyMonths.first?.sessions.first {
                    path = [.session(newest.id)]
                } else if let index = arguments.firstIndex(of: "-uiExercise"),
                          let name = arguments[safe: index + 1] {
                    path = [.exercise(name: name, units: model.displayUnits)]
                }
                #endif
            }
        }
    }

    /// D65 (v1.7): each row leads with its day's square, so a month of workouts reads as the
    /// plan's days rather than as a column of identical grey rows.
    private func row(_ session: Session) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            DaySquare(colour: DayColour.of(session: session, plans: model.plans))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.dayName)
                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))
                    .font(.footnote).foregroundStyle(.secondary)
                Text(ExerciseText.summary(session))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Both history destinations, so any screen can push either one.
enum HistoryRoute: Hashable {
    case session(UUID)
    case exercise(name: String, units: WeightUnit)
    /// D39 (v1.2): what a run of workouts adds up to.
    case metrics
    /// D59 (v1.6): every exercise in history, most recent first, each a way to its chart.
    case exercises
}

/// D59 (v1.6): the list behind History's **Find an exercise** row — since D66 (v1.7) the only
/// way to it.
struct ExercisesListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(ExerciseText.search("", sessions: model.sessions), id: \.self) { name in
            NavigationLink(value: HistoryRoute.exercise(name: name, units: model.displayUnits)) {
                Text(name)
            }
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
    }
}
