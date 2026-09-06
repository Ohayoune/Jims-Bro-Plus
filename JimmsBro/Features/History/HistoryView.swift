import SwiftUI

/// SPEC §4.10: sessions newest first, grouped by month.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    @State private var path: [HistoryRoute] = []
    /// D25 (v1.1): swipe-to-delete confirms, matching every other delete path.
    @State private var confirmDeleteId: UUID?
    /// D30 (v1.1): find one exercise without remembering which day you did it on.
    @State private var query = ""

    private var matches: [String] { ExerciseText.search(query, sessions: model.sessions) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.sessions.isEmpty {
                    ContentUnavailableView("No workouts yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Finished workouts appear here."))
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
                        }
                    }
                } else {
                    List {
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
                        }
                    }
                }
            }
            .navigationTitle("History")
            .searchable(text: $query, prompt: "Find an exercise")
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
                while !model.loaded { try? await Task.sleep(for: .milliseconds(50)) }
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
}
