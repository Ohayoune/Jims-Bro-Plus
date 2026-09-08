import SwiftUI

/// SPEC §4.3 (D43, v1.3): one exercise or one day, as text. The same sheet edits a part of the
/// plan and adds a new one; what differs is the title, the text it opens with, and the
/// `PlanEdit.Operation` its Save becomes. Every Save goes through the import pipeline, so the
/// errors it shows are the ones a paste would get, with the real path behind Details.
struct JSONFragmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initialText: String
    let footer: String
    /// Runs the edit; returns the errors that stopped it, or nothing when it was saved.
    let commit: (String) async -> [Issue]

    @State private var text = ""
    @State private var errors: [Issue] = []
    @State private var showDetails = false
    @State private var saving = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                if !errors.isEmpty { errorSection }
                Section {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 280)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text(footer)
                }
                Section {
                    HStack {
                        Label("Replace with the clipboard", systemImage: "doc.on.clipboard")
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            guard let first = strings.first else { return }
                            text = first
                            errors = []
                        }
                        .labelStyle(.titleOnly)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .bottomAction {
                PrimaryButton(title: "Save", enabled: !text.trimmed.isEmpty && !saving) { save() }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                text = initialText
            }
        }
    }

    /// D26's rule for errors: the sentence first, the path and the code behind Details.
    private var errorSection: some View {
        Section {
            ForEach(Array(errors.enumerated()), id: \.offset) { _, issue in
                VStack(alignment: .leading, spacing: 4) {
                    Text(IssueText.friendly(issue))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if showDetails {
                        VStack(alignment: .leading, spacing: 1) {
                            if !issue.path.isEmpty { Text(issue.path).font(.caption.monospaced()) }
                            Text("\(issue.code) · \(issue.message)")
                                .font(.caption2.monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.red.opacity(0.08))
            }
            Button(showDetails ? "Hide details" : "Details (\(errors.count))") { showDetails.toggle() }
                .font(.footnote)
        } header: {
            Text(errors.count == 1 ? "This can't be saved yet" : "\(errors.count) things to fix")
        }
    }

    private func save() {
        saving = true
        showDetails = false
        Task {
            let refused = await commit(text)
            saving = false
            if refused.isEmpty { dismiss() } else { errors = refused }
        }
    }
}

/// D43: what a fragment sheet is for — which part of the plan, or which kind of new part.
enum FragmentTarget: Identifiable, Equatable {
    case exercise(day: Int, exercise: Int)
    case addExercise(day: Int)
    case day(Int)
    case addDay

    var id: String {
        switch self {
        case let .exercise(day, exercise): return "exercise.\(day).\(exercise)"
        case let .addExercise(day): return "addExercise.\(day)"
        case let .day(day): return "day.\(day)"
        case .addDay: return "addDay"
        }
    }

    var title: String {
        switch self {
        case .exercise: return "Edit exercise as JSON"
        case .addExercise: return "Add exercise"
        case .day: return "Edit day as JSON"
        case .addDay: return "Add day"
        }
    }

    var footer: String {
        switch self {
        case .exercise:
            return "The same fields as a pasted plan's exercise. Sets can be a count or a list, so one set can differ from the others."
        case .addExercise:
            return "One exercise, or a list of them, in the plan format. Fill in the name; the rest has sensible defaults."
        case .day:
            return "The whole day. Rename it here and the repeat block follows."
        case .addDay:
            return "A day, or a whole plan whose days are added — the way to finish a week the chatbot cut short. A new day joins the repeat block."
        }
    }

    /// The text the sheet opens with: the part's own JSON, or a template to fill in.
    func initialText(_ plan: Plan) -> String {
        switch self {
        case let .exercise(day, exercise):
            guard let value = plan.days[safe: day]?.exercises[safe: exercise] else { return "" }
            return PlanJSON.render(exercise: value)
        case let .day(day):
            guard let value = plan.days[safe: day] else { return "" }
            return PlanJSON.render(day: value)
        case .addExercise:
            return Self.exerciseTemplate
        case .addDay:
            return "{\n  \"name\": \"Day \(plan.days.count + 1)\",\n  \"exercises\": [\n"
                + Self.exerciseTemplate.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
                + "\n  ]\n}\n"
        }
    }

    /// Blank where it must be filled in, so Save says "Every exercise needs a name" rather
    /// than quietly saving a placeholder.
    static let exerciseTemplate = """
    {
      "name": "",
      "sets": 3,
      "reps": "8-12",
      "repRange": "8-12",
      "weight": null,
      "restSeconds": 90
    }

    """

    func operation(_ text: String) -> PlanEdit.Operation {
        switch self {
        case let .exercise(day, exercise): return .replaceExerciseJSON(day: day, exercise: exercise, text: text)
        case let .addExercise(day): return .insertExercisesJSON(day: day, at: nil, text: text)
        case let .day(day): return .replaceDayJSON(day: day, text: text)
        case .addDay: return .insertDaysJSON(text: text)
        }
    }
}
