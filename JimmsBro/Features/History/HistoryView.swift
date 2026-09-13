import SwiftUI

/// SPEC §4.10: sessions newest first, grouped by month.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    @State private var path: [HistoryRoute] = []
    /// D25 (v1.1): swipe-to-delete confirms, matching every other delete path.
    @State private var confirmDeleteId: UUID?
    /// D30 (v1.1): find one exercise without remembering which day you did it on.
    @State private var query = ""
    /// D45 (v1.3): the picker behind "Import from another app".
    @State private var choosingHistory = false

    private var matches: [String] { ExerciseText.search(query, sessions: model.sessions) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.sessions.isEmpty {
                    // D45 (v1.3): the one place an empty History can offer what fills it.
                    ContentUnavailableView {
                        Label("No workouts yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Finished workouts appear here.")
                    } actions: {
                        Button("Import from another app") { choosingHistory = true }
                    }
                } else if !query.trimmed.isEmpty {
                    List {
                        if matches.isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                        ForEach(matches, id: \.self) { name in
                            NavigationLink(value: HistoryRoute.exercise(name: name,
                                                                       units: model.displayUnits)) {
                                Text(name)
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
                } else {
                    List {
                        // D39 (v1.2): the numbers over time, one tap from the list of workouts
                        // that produced them.
                        Section {
                            NavigationLink(value: HistoryRoute.metrics) {
                                Label("Metrics", systemImage: "chart.bar")
                            }
                            // D59 (v1.6): the search field is not drawn on every iOS; the fastest
                            // route to an exercise's chart needs a row of its own.
                            NavigationLink(value: HistoryRoute.exercises) {
                                Label("Find an exercise", systemImage: "magnifyingglass")
                            }
                        }
                        // D54 (v1.5): the goals, and how close each is.
                        GoalsSection()
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
                }
            }
            .navigationTitle("History")
            .searchable(text: $query, prompt: "Find an exercise")
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

    private func row(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.dayName)
            Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))
                .font(.footnote).foregroundStyle(.secondary)
            Text(ExerciseText.summary(session))
                .font(.footnote).foregroundStyle(.secondary)
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

/// D59 (v1.6): the list behind History's **Find an exercise** row.
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
