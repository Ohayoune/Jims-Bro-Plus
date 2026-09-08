import SwiftUI

/// SPEC §4.3 / §6.21 (D44, v1.3): **Progression**, the chatbot round-trip run the other way.
/// One screen: with no progression, the period, "Use my history", the three steps Add plan
/// already taught, the reply, and a review before it is saved; with one, what it says and
/// where you are in it, **Plan the next one**, and Remove.
struct ProgressionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let planId: UUID

    @State private var planning = false
    @State private var weeks = 8
    @State private var useHistory = true
    @State private var text = ""
    @State private var issues: [Issue] = []
    @State private var review: ReviewItem?
    @State private var copied = false
    @State private var showEditor = false
    @State private var showDetails = false
    @State private var confirmRemove = false

    private var plan: Plan? { model.plans.first { $0.id == planId } }
    private var errors: [Issue] { issues.filter { $0.severity == .error } }
    private var hasDraft: Bool { !text.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    if let current = plan.progression, !planning {
                        currentSections(plan, current)
                    } else {
                        planningSections(plan)
                    }
                } else {
                    ContentUnavailableView("Plan deleted", systemImage: "trash")
                }
            }
            .navigationTitle("Progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                if let plan, plan.progression != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if planning {
                                Button("Keep the current one") { planning = false }
                            }
                            Button("Remove progression", role: .destructive) { confirmRemove = true }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More")
                    }
                }
            }
            .confirmationDialog("Remove this progression?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Task { await model.setProgression(nil, for: planId); planning = false }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The plan goes back to its own targets. Nothing you logged changes.")
            }
            .sheet(item: $review) { item in
                if let plan {
                    ProgressionReviewSheet(progression: item.progression, plan: plan, warnings: item.warnings) {
                        Task {
                            await model.setProgression(item.progression, for: planId)
                            review = nil
                            planning = false
                            text = ""
                            issues = []
                        }
                    }
                }
            }
        }
    }

    // MARK: - With one

    private func currentSections(_ plan: Plan, _ current: Progression) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ProgressionText.status(current, on: Date()))
                        .font(.title3.weight(.semibold))
                    Text("Started \(current.startDate.formatted(date: .abbreviated, time: .omitted)) · "
                         + "ends \(current.endDate().formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            ForEach(plan.days) { day in
                let entries = day.exercises.compactMap { exercise -> (Exercise, ProgressionEntry)? in
                    current.entry(day: day.name, exercise: exercise.name).map { (exercise, $0) }
                }
                if !entries.isEmpty {
                    Section(day.name) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, pair in
                            entryRow(pair.0, pair.1, current: current, units: plan.units)
                        }
                    }
                }
            }
        }
        .bottomAction {
            PrimaryButton(title: "Plan the next one") { planning = true }
        }
    }

    private func entryRow(_ exercise: Exercise, _ entry: ProgressionEntry, current: Progression,
                          units: WeightUnit) -> some View {
        let week = current.weekIndex(on: Date())
        return VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
            if let week, let change = entry.weeks[safe: week] {
                Text("This week: " + ProgressionText.change(change, units: units, bodyweight: exercise.bodyweight))
                    .font(.footnote)
            }
            Text(ProgressionText.weeksLine(entry, units: units, bodyweight: exercise.bodyweight))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Planning one

    private func planningSections(_ plan: Plan) -> some View {
        List {
            if !errors.isEmpty { errorSection }
            Section {
                Picker("Weeks", selection: $weeks) {
                    ForEach(Progression.periods, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("How many weeks")
            } footer: {
                Text("Week 1 starts the day you save it.")
            }
            if model.hasHistory(for: planId) {
                Section {
                    Toggle("Use my history", isOn: $useHistory)
                } footer: {
                    Text("The prompt includes your last sessions of each exercise, so the chatbot progresses from what you actually did.")
                }
            }
            Section("Plan it with a chatbot") {
                step(1, "Copy the prompt.") {
                    Button(copied ? "Copied" : "Copy prompt") {
                        if let prompt = model.progressionPrompt(for: planId, weeks: weeks, includeHistory: useHistory) {
                            Clipboard.write(prompt)
                        }
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
                step(2, "Paste it into ChatGPT, Claude or another chatbot.")
                step(3, "Copy its reply, come back, and tap Paste progression.")
            }
            Section {
                HStack {
                    Label("Paste progression", systemImage: "doc.on.clipboard")
                    Spacer()
                    PasteButton(payloadType: String.self) { strings in
                        guard let first = strings.first else { return }
                        text = first
                        issues = []
                        runImport()
                    }
                    .labelStyle(.titleOnly)
                    .buttonBorderShape(.capsule)
                }
                DisclosureGroup("Show text", isExpanded: $showEditor) {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                }
                .font(.footnote)
            } footer: {
                Text(hasDraft ? "Review progression checks it against the plan and shows you every week."
                              : "The reply goes here.")
            }
        }
        .bottomAction {
            if hasDraft { PrimaryButton(title: "Review progression") { runImport() } }
        }
    }

    @ViewBuilder private func step(_ number: Int, _ text: String,
                                   @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Color.secondary.opacity(0.15), in: Circle())
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 2)
    }

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
            Text(errors.count == 1 ? "This progression can't be saved yet" : "\(errors.count) things to fix")
        }
    }

    private func runImport() {
        showDetails = false
        let result = model.runProgressionImport(text, planId: planId)
        issues = result.issues
        if let progression = result.progression {
            review = ReviewItem(progression: progression, warnings: result.issues.filter { $0.severity == .warning })
        }
    }

    private struct ReviewItem: Identifiable {
        let id = UUID()
        let progression: Progression
        let warnings: [Issue]
    }
}

/// What the chatbot actually planned, week by week, before it is saved — D26's review, for a
/// progression. Material warnings (an exercise left out, a weight ignored, a short list) are
/// shown; tidying (a rounded weight, an unknown field) goes behind Details.
struct ProgressionReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let progression: Progression
    let plan: Plan
    let warnings: [Issue]
    let save: () -> Void

    @State private var showCleanup = false

    private var split: (material: [Issue], cleanup: [Issue]) { IssueText.split(warnings) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(progression.weeks) week\(progression.weeks == 1 ? "" : "s") from today · "
                         + "\(progression.entries.count) exercise\(progression.entries.count == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !split.material.isEmpty {
                    Section("Worth knowing") {
                        ForEach(Array(split.material.enumerated()), id: \.offset) { _, warning in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.message).font(.footnote).fixedSize(horizontal: false, vertical: true)
                                if let where_ = IssueText.location(warning.path) {
                                    Text(where_).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .listRowBackground(Color.yellow.opacity(0.15))
                        }
                    }
                }
                ForEach(plan.days) { day in
                    let entries = day.exercises.compactMap { exercise -> (Exercise, ProgressionEntry)? in
                        progression.entry(day: day.name, exercise: exercise.name).map { (exercise, $0) }
                    }
                    if !entries.isEmpty {
                        Section(day.name) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { _, pair in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pair.0.name).font(.footnote)
                                    Text(ProgressionText.weeksLine(pair.1, units: plan.units, bodyweight: pair.0.bodyweight))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if !split.cleanup.isEmpty {
                    Section {
                        DisclosureGroup("Details (\(split.cleanup.count))", isExpanded: $showCleanup) {
                            ForEach(Array(split.cleanup.enumerated()), id: \.offset) { _, warning in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(warning.message).font(.caption)
                                    if !warning.path.isEmpty {
                                        Text(warning.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .font(.footnote)
                    } footer: {
                        Text("Tidying the app did on its own. None of it changes a target you'll see.")
                    }
                }
            }
            .navigationTitle("Review progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .bottomAction {
                PrimaryButton(title: "Save progression") { save() }
            }
        }
    }
}
