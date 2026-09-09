import SwiftUI

/// SPEC §4.10 (D54, v1.5): the Goals section at the top of History — each goal's line and how
/// far along it is, **Set a goal**, swipe to delete. It computes nothing: `Goals` does.
struct GoalsSection: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var confirmDeleteId: UUID?

    var body: some View {
        Section {
            ForEach(model.goals) { goal in
                let progress = model.goalProgress(goal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.exerciseName)
                    Text(Goals.line(goal, progress: progress))
                        .font(.footnote)
                        .foregroundStyle(goal.reachedAt == nil ? .secondary : Color.done)
                    // A bar for a number you are working towards; done, it is the reserved
                    // green like a record (§4.0).
                    ProgressView(value: goal.reachedAt == nil ? progress.fraction : 1)
                        .tint(goal.reachedAt == nil ? Color.accentColor : Color.done)
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in confirmDeleteId = offsets.first.map { model.goals[$0].id } }
            Button("Set a goal") { adding = true }
        } header: {
            Text("Goals")
        } footer: {
            if model.goals.isEmpty {
                Text("A weight for so many reps, a hold, or a number of reps. History shows how close you are, and Progression plans towards it.")
            }
        }
        .sheet(isPresented: $adding) { GoalSheet(units: model.displayUnits) }
        .confirmationDialog("Remove this goal?", isPresented: Binding(
            get: { confirmDeleteId != nil }, set: { if !$0 { confirmDeleteId = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let id = confirmDeleteId { Task { await model.removeGoal(id) } }
                confirmDeleteId = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteId = nil }
        }
    }
}

/// One sheet: the exercise, what kind of target, the numbers, an optional date, Save.
struct GoalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var name: String = ""
    let units: WeightUnit

    private enum Kind: String, CaseIterable, Identifiable {
        case weight = "Weight × reps", hold = "Hold", reps = "Reps"
        var id: String { rawValue }
    }

    @State private var exercise = ""
    @State private var kind: Kind = .weight
    @State private var weight = ""
    @State private var reps = "5"
    @State private var seconds = ""
    @State private var hasDate = false
    @State private var by = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise", text: $exercise)
                    if exercise.trimmed.isEmpty || !model.exerciseNames.contains(where: { normalized($0) == normalized(exercise) }) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestions, id: \.self) { candidate in
                                    Button(candidate) { exercise = candidate }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Spelt as in your history, so the app can find its sets.")
                }
                Section("Target") {
                    Picker("Kind", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch kind {
                    case .weight:
                        LabeledContent(units.rawValue) {
                            TextField("100", text: Binding(get: { weight }, set: { weight = InputRules.weight($0, previous: weight) }))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("For reps") {
                            TextField("5", text: Binding(get: { reps }, set: { reps = String($0.filter(\.isNumber).prefix(4)) }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    case .hold:
                        LabeledContent("Seconds") {
                            TextField("60", text: Binding(get: { seconds }, set: { seconds = InputRules.seconds($0, previous: seconds) }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    case .reps:
                        LabeledContent("Reps") {
                            TextField("10", text: Binding(get: { reps }, set: { reps = String($0.filter(\.isNumber).prefix(4)) }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section {
                    Toggle("By a date", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Date", selection: $by, in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    Text("The app shows the date and never nags about it.")
                }
            }
            .navigationTitle("Set a goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { save() }.disabled(target == nil || exercise.trimmed.isEmpty) }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                exercise = name
            }
        }
    }

    private var suggestions: [String] {
        let needle = normalized(exercise)
        return Array(model.exerciseNames.filter { needle.isEmpty || normalized($0).contains(needle) }.prefix(8))
    }

    private var target: GoalTarget? {
        switch kind {
        case .weight:
            guard let w = InputRules.weightValue(weight), w > 0, let r = Int(reps), r > 0 else { return nil }
            return .weight(w, reps: r)
        case .hold:
            guard let s = InputRules.secondsValue(seconds), s > 0 else { return nil }
            return .seconds(s)
        case .reps:
            guard let r = Int(reps), r > 0 else { return nil }
            return .reps(r)
        }
    }

    private func save() {
        guard let target else { return }
        let goal = Goal(exerciseName: exercise.trimmed, units: units, target: target,
                        by: hasDate ? by : nil, createdAt: Date())
        Task { await model.addGoal(goal) }
        dismiss()
    }
}
