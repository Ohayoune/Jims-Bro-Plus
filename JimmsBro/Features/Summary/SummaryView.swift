import SwiftUI

/// SPEC §4.9 (rewritten in v1.1's R4): what happened, in words you can read in a few seconds.
/// It leads by saying the workout was saved, then one comparison per exercise; set durations —
/// which include walking and fiddling now that the Continue gate is gone (D19) — sit behind
/// Details rather than beside the numbers you care about.
struct SummaryView: View {
    @Environment(AppModel.self) private var model
    let session: Session
    let done: () -> Void

    @State private var showDetails = false

    var body: some View {
        // D96 (v1.12 L6): Core's lines, worked out once per draw — the records included, which
        // were read again for every exercise.
        let exercises = SummaryText.exercises(session, history: model.sessions,
                                              wording: model.settings.wording)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workout saved")
                        .font(.title2.weight(.semibold))
                    Text(SummaryText.headline(session))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // D57 (v1.6): what happens next, from the schedule the calendar draws.
                    if let next = model.summaryNext(for: session) {
                        Text(next)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }

            ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(exercise.comparison.headline)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let record = exercise.record {
                            PRBadge(text: record)
                        }
                    }
                    if let was = exercise.insteadOf {
                        Text(was)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    // Only when no single sentence is true of the whole exercise.
                    ForEach(Array(exercise.comparison.rows.enumerated()), id: \.offset) { _, row in
                        Text(row)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let advice = exercise.advice {
                        Text(advice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if showDetails, let took = exercise.took {
                        Text(took).font(.caption).foregroundStyle(.tertiary)
                    }
                } header: {
                    // O16: reachable from the summary as well.
                    NavigationLink(value: HistoryRoute.exercise(name: exercise.name,
                                                                units: session.units)) {
                        Text(exercise.name)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }

            Section {
                Button(showDetails ? "Hide times" : "Details") { showDetails.toggle() }
                    .font(.footnote)
            }
        }
        .bottomAction {
            PrimaryButton(title: "Done") { done() }
        }
    }
}
