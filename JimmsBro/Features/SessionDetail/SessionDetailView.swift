import SwiftUI

/// A finished session: every step, editable, with the exercise names opening their history (O16).
struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let sessionId: UUID

    @State private var editing: EditTarget?
    @State private var confirmDelete = false
    /// SPEC §4.5 (v1.1): Rename exercise moved here from the mid-workout menu, where it was a
    /// history-editing task competing for room with Skip and Finish.
    @State private var renaming: Int?
    @State private var draftName = ""
    @State private var choosingRename = false

    private var session: Session? { model.sessions.first { $0.id == sessionId } }
    private var records: Set<Int> {
        session.map { SessionStats.personalRecords(session: $0, history: model.sessions) } ?? []
    }

    var body: some View {
        Group {
            if let session {
                List {
                    Section {
                        Text(ExerciseText.summary(session))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    // D39 (v1.2): what the workout actually was. v1.1 opened a past session and
                    // showed the sets back, and nothing else — not how long it took, how much of
                    // that was rest, how much was lifted, or whether anything was a record.
                    Section("Metrics") {
                        ForEach(SessionMetrics.of(session, history: model.sessions)) { metric in
                            MetricRow(metric: metric)
                        }
                    }
                    ForEach(Array(SessionBlocks.indices(session).enumerated()), id: \.offset) { _, indices in
                        Section {
                            ForEach(indices, id: \.self) { index in
                                Button {
                                    editing = EditTarget(session: session, step: index)
                                } label: {
                                    row(session: session, index: index, named: SessionBlocks.namesRows(session, indices))
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            header(session: session, indices: indices)
                        }
                    }
                }
                .navigationTitle(session.dayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if !session.exercises.isEmpty {
                                Button("Rename exercise") { beginRename(session) }
                            }
                            Button("Delete workout", role: .destructive) { confirmDelete = true }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More")
                    }
                }
                // D56 (v1.6): an alert — from a menu, a dialog's Cancel is not drawn on iOS 26.
                .alert("Delete this workout?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) {
                        Task { await model.deleteHistorySession(sessionId); dismiss() }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(item: $editing) { target in
                    EditResultSheet(target: target) { result in
                        Task { await model.editHistorySession(sessionId, step: target.step, result: result) }
                    }
                }
                .confirmationDialog("Rename which exercise?", isPresented: $choosingRename,
                                    titleVisibility: .visible) {
                    ForEach(Array(session.exercises.enumerated()), id: \.offset) { index, exercise in
                        Button(exercise.name) { draftName = exercise.name; renaming = index }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Rename exercise", isPresented: Binding(get: { renaming != nil },
                                                               set: { if !$0 { renaming = nil } })) {
                    TextField("Name", text: $draftName)
                    Button("Cancel", role: .cancel) { renaming = nil }
                    Button("Rename") {
                        if let index = renaming {
                            Task { await model.renameHistoryExercise(sessionId, exerciseIndex: index,
                                                                     name: draftName) }
                        }
                        renaming = nil
                    }
                }
            } else {
                ContentUnavailableView("Workout deleted", systemImage: "trash")
            }
        }
    }

    /// One exercise renames straight away; several ask which first.
    private func beginRename(_ session: Session) {
        if session.exercises.count == 1 {
            draftName = session.exercises[0].name
            renaming = 0
        } else {
            choosingRename = true
        }
    }


    /// The block header names its exercises, and each name opens that exercise's history.
    /// The names and the duration come from Core, so this header and the Overview's — which is
    /// plain text — always say the same thing.
    private func header(session: Session, indices: [Int]) -> some View {
        let unique = SessionBlocks.names(session, indices)
        var duration = ""
        if let block = indices.first.map({ session.steps[$0].blockIndex }),
           let seconds = SessionStats.blockDuration(block, session: session) {
            duration = " · \(TargetText.time(seconds))"
        }
        return HStack(spacing: 4) {
            ForEach(Array(unique.enumerated()), id: \.offset) { offset, name in
                if offset > 0 { Text("+") }
                NavigationLink(value: HistoryRoute.exercise(name: name, units: session.units)) {
                    Text(name)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            Text(duration)
        }
    }

    private func row(session: Session, index: Int, named: Bool) -> some View {
        let step = session.steps[index]
        let label = StepCard.rowLabel(session: session, step: index, naming: named,
                                      wording: model.settings.wording)
        return HStack {
            Text(label).font(.footnote).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            // D30 (v1.1): the set that beat everything before it, marked where you go looking.
            if records.contains(index) { PRBadge(text: "PR") }
            Text(ExerciseText.result(step, wording: model.settings.wording))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(step.status == .logged ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}

/// Identifies the step being edited, and carries what the sheet needs to render itself.
struct EditTarget: Identifiable {
    let session: Session
    let step: Int
    var id: Int { step }

    var isTimed: Bool { session.target(at: step)?.work.isTimed ?? false }
    var showsWeight: Bool {
        guard let s = session.steps[safe: step] else { return false }
        return session.exercises[safe: s.exerciseIndex]?.bodyweight != true
    }
    var units: WeightUnit { session.units }
    var result: SetResult? { session.steps[safe: step]?.result }
}

/// Editing a logged value, used by both the live overview and session detail.
struct EditResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: EditTarget
    let save: (SetResult) -> Void

    @State private var valueText = ""
    @State private var weightText = ""
    @State private var loaded = false
    /// F3 (2026-09-24): Cancel with a field changed, asking before the change goes.
    @State private var discarding = false

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(target.isTimed ? "Seconds" : "Reps") {
                    TextField("", text: Binding(
                        get: { valueText },
                        set: { valueText = target.isTimed ? InputRules.seconds($0, previous: valueText)
                                                          : InputRules.reps($0, previous: valueText) }))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                if target.showsWeight {
                    LabeledContent(target.units.rawValue) {
                        TextField("", text: Binding(
                            get: { weightText },
                            set: { weightText = InputRules.weight($0, previous: weightText) }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { if dirty { discarding = true } else { dismiss() } } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { commit() }.disabled(!canSave)
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                valueText = originalValue
                weightText = originalWeight
            }
            .discardGuard(dirty, asking: $discarding) { dismiss() }
        }
    }

    /// The set as it was logged, as the fields first show it.
    private var originalValue: String {
        target.result?.reps.map(String.init) ?? target.result?.seconds.map(String.init) ?? ""
    }
    private var originalWeight: String { InputRules.weightText(target.result?.weight) }
    /// F3 (2026-09-24): a field changed from the set as it was logged.
    private var dirty: Bool { loaded && (valueText != originalValue || weightText != originalWeight) }

    private var canSave: Bool {
        target.isTimed ? InputRules.secondsValue(valueText) != nil
                       : InputRules.repsValue(valueText) != nil
    }

    private func commit() {
        let weight = target.showsWeight ? InputRules.weightValue(weightText) : nil
        let result: SetResult?
        if target.isTimed {
            result = InputRules.secondsValue(valueText).map { .duration(seconds: $0, weight: weight) }
        } else {
            result = InputRules.repsValue(valueText).map { .reps(count: $0, weight: weight) }
        }
        guard let result else { return }
        save(result)
        dismiss()
    }
}


/// D39 (v1.2): one metric, in the app's one list language (§4.0).
struct MetricRow: View {
    let metric: Metric

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.label)
                if let note = metric.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Text(metric.value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label), \(metric.value)"
                            + (metric.note.map { ", \($0)" } ?? ""))
    }
}
