import SwiftUI

/// SPEC §6.18 (D42, v1.3): the machine is taken and you want to do *something* now. One
/// sheet: what to do instead, an optional weight, **Change**. The exercise's remaining sets
/// become sets of the new exercise, which keeps its own history — its own "last time", its
/// own suggestion, its own records.
struct ChangeExerciseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let exerciseIndex: Int
    let currentName: String
    let units: WeightUnit

    @State private var name = ""
    @State private var weightText = ""
    @FocusState private var focused: Bool

    private var trimmedName: String { name.trimmed }
    private var isSameName: Bool { normalized(trimmedName) == normalized(currentName) }
    /// The same name with a weight is a weight change for the remaining sets; the same name
    /// with no weight is nothing.
    private var canChange: Bool { !trimmedName.isEmpty && (!isSameName || !weightText.isEmpty) }

    /// Exercises done before, most recent first, narrowed as the name is typed.
    private var suggestions: [String] {
        Array(ExerciseNames.known(plans: [], history: model.sessions, query: trimmedName)
            .map(\.name)
            .filter { normalized($0) != normalized(currentName) && normalized($0) != normalized(trimmedName) }
            .prefix(6))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Exercise", text: $name)
                        .focused($focused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    HStack {
                        Text(units.rawValue.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        TextField("Plan's weight", text: Binding(
                            get: { weightText },
                            set: { weightText = InputRules.weight($0, previous: weightText) }))
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Instead of \(currentName)")
                } footer: {
                    Text("Its remaining sets keep their targets. Leave the weight empty to keep the plan's. "
                         + "The new exercise keeps its own history.")
                }
                if !suggestions.isEmpty {
                    Section("Done before") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { name = suggestion }
                                .buttonStyle(PressableRow())
                        }
                    }
                }
            }
            .navigationTitle("Change exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .bottomAction {
                PrimaryButton(title: isSameName ? "Change weight" : "Change", enabled: canChange) { change() }
            }
            .onAppear { focused = true }
        }
    }

    private func change() {
        let weight = InputRules.weightValue(weightText)
        Task {
            await model.apply(.substituteExercise(exerciseIndex: exerciseIndex, name: trimmedName,
                                                  weight: weight))
            dismiss()
        }
    }
}
