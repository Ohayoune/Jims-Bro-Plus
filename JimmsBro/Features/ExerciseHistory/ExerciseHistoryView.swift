import SwiftUI
import Charts

/// One exercise over time (SPEC §4.10, §6.7): its best set, the chart of D13 — which v1.1's R5
/// moved out of SPEC §10 "Later" — and every session that included it.
struct ExerciseHistoryView: View {
    @Environment(AppModel.self) private var model
    let name: String
    let units: WeightUnit

    private var points: [ExercisePoint] { model.history(for: name, units: units) }
    private var allSteps: [SessionStep] {
        model.sessions.filter { $0.units == units }.flatMap { ExerciseHistory.steps(name: name, session: $0) }
    }

    var body: some View {
        Group {
            if points.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Log \(name) to build its history."))
            } else {
                List {
                    if let best = ExerciseText.best(steps: allSteps, units: units) {
                        Section {
                            Text(best).font(.title3.weight(.semibold))
                        }
                    }
                    // D13: top weight over time, with the reps behind each point. Two points
                    // are the fewest that can show a direction; one is just a dot.
                    if chartPoints.count > 1 {
                        Section("Top set") { chart }
                    }
                    Section {
                        // Newest first, matching the History list.
                        ForEach(Array(points.enumerated().reversed()), id: \.offset) { _, point in
                            row(point)
                        }
                    }
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The points that have a weight to plot. A bodyweight or timed exercise has none, and
    /// gets no chart rather than a flat line at zero.
    private var chartPoints: [ExercisePoint] { points.filter { $0.topWeight != nil } }

    private var chart: some View {
        Chart(Array(chartPoints.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Date", point.date),
                     y: .value(units.rawValue, point.topWeight ?? 0))
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", point.date),
                      y: .value(units.rawValue, point.topWeight ?? 0))
                .foregroundStyle(Color.accentColor)
                .annotation(position: .top, spacing: 2) {
                    if let reps = point.topSetReps {
                        Text("\(reps)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
        }
        .chartYAxisLabel(units.rawValue)
        .frame(height: 160)
        .padding(.vertical, 4)
        .accessibilityLabel("Top set over time")
        .accessibilityValue(chartSummary)
    }

    /// VoiceOver gets the shape of the line in words; a chart it cannot read is not a feature.
    private var chartSummary: String {
        guard let first = chartPoints.first?.topWeight, let last = chartPoints.last?.topWeight
        else { return "No weights logged" }
        let direction = last > first ? "up from" : (last < first ? "down from" : "unchanged from")
        return "\(chartPoints.count) sessions, \(TargetText.number(last)) \(units.rawValue), "
            + "\(direction) \(TargetText.number(first))"
    }

    private func row(_ point: ExercisePoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(point.date.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.footnote).foregroundStyle(.secondary)
            Text(sets(point)).font(.callout)
            if let detail = detail(point) {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func sets(_ point: ExercisePoint) -> String {
        point.sets.map { result in
            let value = result.reps.map(String.init) ?? result.seconds.map(TargetText.time) ?? "–"
            return value + (result.weight.map { "@\(TargetText.number($0))" } ?? "")
        }
        .joined(separator: ", ")
    }

    /// Only the parts that have content, per SPEC §4.0.
    private func detail(_ point: ExercisePoint) -> String? {
        var parts: [String] = []
        if point.volume > 0 { parts.append("\(TargetText.grouped(point.volume)) \(units.rawValue)") }
        if let weight = point.topWeight, let reps = point.topSetReps {
            parts.append("top \(TargetText.number(weight)) \(units.rawValue) × \(reps)")
        } else if let seconds = point.topSeconds {
            parts.append("longest \(TargetText.time(seconds))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
