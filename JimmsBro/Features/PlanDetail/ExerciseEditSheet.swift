import SwiftUI

/// SPEC §4.3 (D29, v1.1): the fields a plan edit can change. Two forms edit the same fields —
/// name, set count, reps, rep range, weight, rest, in reserve — decided in Core
/// (`PlanEdit.ExerciseFields`), and TN3 holds them to the same exercise:
///
/// - **The operation form**, Plan detail's: each changed field commits one `PlanEdit.Operation`,
///   so every change goes through the import pipeline on its own and a refusal never leaves the
///   sheet in a state the plan does not have.
/// - **The value form** (D93, v1.11): the exercise of a day that belongs to no plan — a day
///   written for one date — edited as a value and handed to `save`, which checks the whole day
///   and returns what it refused; the sheet stays open with the sentence until it is fixed.
struct ExerciseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let units: WeightUnit
    /// D43 (v1.3): hands over to the JSON sheet for what the fields cannot say — one set
    /// unlike the others, drops, a warning beep.
    var editAsJSON: (() -> Void)? = nil
    private let output: Output

    private enum Output {
        /// Called with a builder, so the sheet doesn't need to know its own address.
        case operations((@escaping (ExerciseAddress) -> PlanEdit.Operation) -> Void)
        case value((Exercise) -> [Issue])
    }

    @State private var fields: PlanEdit.ExerciseFields
    /// The value form's refusal, until the next Save.
    @State private var refusal: String?
    /// F3 (2026-09-24): Cancel with a field changed, asking before the change goes.
    @State private var discarding = false

    /// The operation form (D29).
    init(exercise: Exercise, units: WeightUnit, editAsJSON: (() -> Void)? = nil,
         commit: @escaping (@escaping (ExerciseAddress) -> PlanEdit.Operation) -> Void) {
        self.exercise = exercise
        self.units = units
        self.editAsJSON = editAsJSON
        output = .operations(commit)
        _fields = State(initialValue: PlanEdit.ExerciseFields(exercise))
    }

    /// The value form (D93, v1.11).
    init(exercise: Exercise, units: WeightUnit, save: @escaping (Exercise) -> [Issue]) {
        self.exercise = exercise
        self.units = units
        output = .value(save)
        _fields = State(initialValue: PlanEdit.ExerciseFields(exercise))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $fields.name)
                } footer: {
                    Text("The name is how the app finds this exercise in your history, so keep it the same as last time.")
                }

                Section("Sets") {
                    Stepper("\(fields.sets) set\(fields.sets == 1 ? "" : "s")", value: $fields.sets, in: 1...50)
                }

                Section {
                    LabeledContent("Reps") {
                        TextField("8-12", text: $fields.reps)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Rep range") {
                        TextField("optional", text: $fields.range)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(units.rawValue) {
                        TextField("none", text: Binding(
                            get: { fields.weight },
                            set: { fields.weight = InputRules.weight($0, previous: fields.weight) }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Rest") {
                        HStack(spacing: 4) {
                            TextField("90", text: Binding(
                                get: { fields.rest },
                                set: { fields.rest = InputRules.seconds($0, previous: fields.rest) }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("s").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("In reserve") {
                        TextField("none", text: Binding(
                            get: { fields.reserve },
                            set: { fields.reserve = String($0.filter(\.isNumber).prefix(2)) }))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Reps takes a number, a range like 8-12, AMRAP or 5+, or a time: 45s, 30s+ for a minimum hold, or open. "
                         + "In reserve is how many reps (or seconds, on a hold) short of failure to stop, 0 to 20.")
                }
                if let refusal {
                    Section {
                        RefusedBand(sentence: refusal)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if let editAsJSON {
                    Section {
                        Button("Edit as JSON") { editAsJSON() }
                    } footer: {
                        Text("For what these fields can't say: one set unlike the others, drop sets, a warning beep.")
                    }
                }
            }
            .navigationTitle("Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { if dirty { discarding = true } else { dismiss() } } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!fields.canSave)
                }
            }
            .discardGuard(dirty, asking: $discarding) { dismiss() }
        }
    }

    /// F3 (2026-09-24): a field changed from the exercise as it opened.
    private var dirty: Bool { fields != PlanEdit.ExerciseFields(exercise) }

    /// Only the fields that actually changed are sent, so an untouched exercise is untouched.
    private func save() {
        let changes = fields.changes(from: exercise)
        switch output {
        case let .operations(commit):
            for change in changes {
                commit { change.operation(day: $0.day, exercise: $0.exercise) }
            }
            dismiss()
        case let .value(save):
            guard let edited = PlanEdit.edited(exercise, changes) else {
                refusal = "That edit doesn't apply to this exercise."
                return
            }
            if let error = save(edited).first(where: { $0.severity == .error }) {
                refusal = IssueText.friendly(error)
            } else {
                dismiss()
            }
        }
    }
}
