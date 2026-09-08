import SwiftUI

/// SPEC §4.10 (D39, v1.2): what a run of workouts adds up to. Reached from History, because
/// that is where you go to ask what you have been doing.
struct MetricsView: View {
    @Environment(AppModel.self) private var model
    /// The window the summary is over. A month is the default because it is the shortest
    /// window in which "how often do I train" has an answer.
    @State private var days = 30

    private var metrics: [Metric] { TrendMetrics.summary(model.sessions, days: days) }

    var body: some View {
        List {
            Section {
                Picker("Over", selection: $days) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
            }
            if metrics.isEmpty {
                Section {
                    Text("Finish a workout and its numbers appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(metrics) { MetricRow(metric: $0) }
                }
            }
            // The recent workouts themselves, so a number can always be traced to the days
            // that made it.
            let recent = TrendMetrics.recent(model.sessions, days: days)
            if !recent.isEmpty {
                Section("Workouts") {
                    ForEach(recent) { session in
                        NavigationLink(value: HistoryRoute.session(session.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.dayName)
                                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated)
                                                                 .day().month(.abbreviated)))
                                    .font(.footnote).foregroundStyle(.secondary)
                                Text(ExerciseText.summary(session))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Metrics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
