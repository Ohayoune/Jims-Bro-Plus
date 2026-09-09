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

    private var volume: Double { SessionStats.volume(session.steps) }
    /// D30 (v1.1): the sets that beat everything logged for that exercise before today.
    private var records: Set<Int> {
        SessionStats.personalRecords(session: session, history: model.sessions)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workout saved")
                        .font(.title2.weight(.semibold))
                    Text(headlineLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // D57 (v1.6): what happens next, from the schedule the calendar draws.
                    if let next = model.summaryNext(for: session) {
                        Text(next)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // D54 (v1.5): a goal this workout was the first to reach, in the colour
                    // reserved for "this happened" (§4.0), like a record.
                    ForEach(model.goalsReached(by: session)) { goal in
                        Text(Goals.reachedLine(goal))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.done)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }

            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                Section {
                    let comparison = SessionStats.comparison(
                        for: exercise.name, session: session,
                        history: model.sessions.filter { $0.id != session.id })
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(comparison.headline)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let record = recordText(index: index) {
                            PRBadge(text: record)
                        }
                    }
                    // D42 (v1.3): what it stood in for, said once.
                    if let was = exercise.substitutedFor {
                        Text("Instead of \(was)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    // Only when no single sentence is true of the whole exercise.
                    ForEach(Array(comparison.rows.enumerated()), id: \.offset) { _, row in
                        Text(row)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let advice = adviceLine(index: index, exercise: exercise) {
                        Text(advice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if showDetails, let detail = detailLine(index: index) {
                        Text(detail).font(.caption).foregroundStyle(.tertiary)
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

    /// "Push · 48 min · 16 of 18 sets · Volume 12,400 kg", each part only when it has data (§4.0).
    private var headlineLine: String {
        var parts = [session.dayName,
                     HomeActivity.duration(SessionStats.duration(session)),
                     "\(SessionStats.loggedCount(session)) of \(session.steps.count) sets"]
        // P5: a bare number is not a label. Zero volume is a bodyweight day, not a failure.
        if volume > 0 { parts.append("Volume \(TargetText.grouped(volume)) \(session.units.rawValue)") }
        // D44 (v1.3): which week of the progression this was, when it was one.
        if let week = ProgressionText.weekLine(session) { parts.append(week) }
        return parts.joined(separator: " · ")
    }

    /// "PR 85 kg × 5" for the best record this exercise set today, or nil when it set none.
    private func recordText(index: Int) -> String? {
        let mine = records.filter { session.steps[$0].exerciseIndex == index }
        guard !mine.isEmpty else { return nil }
        let results = mine.compactMap { session.steps[$0].result }
        guard let best = SessionStats.best(mine.map { session.steps[$0] }) ?? results.last
        else { return nil }
        if let seconds = best.seconds { return "PR \(TargetText.time(seconds))" }
        guard let reps = best.reps else { return "PR" }
        guard let weight = best.weight else { return "PR \(reps) reps" }
        return "PR \(TargetText.number(weight)) \(session.units.rawValue) × \(reps)"
    }

    private func adviceLine(index: Int, exercise: SessionExercise) -> String? {
        guard let advice = exercise.advice, let range = exercise.repRange else { return nil }
        let logged = session.steps.filter { $0.exerciseIndex == index && $0.status == .logged }
        return ProgressionAdvice.message(advice, range: range, loggedSets: logged.count,
                                         currentWeight: logged.first?.result?.weight,
                                         units: session.units)
    }

    /// D19: how long the exercise took, behind Details.
    private func detailLine(index: Int) -> String? {
        let steps = session.steps.filter { $0.exerciseIndex == index }
        guard let block = steps.first?.blockIndex,
              let seconds = SessionStats.blockDuration(block, session: session) else { return nil }
        let sets = steps.compactMap(\.setSeconds)
        var text = "Took \(TargetText.time(seconds))"
        if let average = mean(sets.map(Double.init)) {
            text += " · \(TargetText.time(Int(average.rounded()))) a set"
        }
        return text
    }
}
