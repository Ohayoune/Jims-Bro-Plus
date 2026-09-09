import SwiftUI
import UniformTypeIdentifiers

/// SPEC §4.4 (D26, v1.1): **Add plan**. Three ways in — paste, get one from a chatbot, open a
/// file — with the JSON editor behind "Show text" rather than being the front door. The chatbot
/// round-trip is what makes this app what it is, and the v1 screen never explained it.
struct ImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Plan detail's Replace (D25 v1.1): when set, Save replaces this plan outright instead of
    /// going through the name-based conflict flow, and the editor opens pre-filled with its JSON.
    var replacingPlanId: UUID? = nil
    var prefillText: String = ""

    private enum Route: Hashable { case builtIns, draft }
    /// D46 (v1.4): the picker is pushed inside this sheet's own stack. Home's link and the
    /// intro's button open the sheet with the picker already on it, as the stack's initial
    /// path. `RootView` presents this sheet from an `AddPlanRequest` item rather than a Bool
    /// and a flag: a sheet's content closure runs with the values it captured *before* the
    /// tap that presented it, so a flag set in the same tap arrived here as false.
    @State private var path: [Route]

    init(replacingPlanId: UUID? = nil, prefillText: String = "", opening: AddPlanRequest = .plan) {
        self.replacingPlanId = replacingPlanId
        self.prefillText = prefillText
        let route: [Route]
        switch opening {
        case .plan: route = []
        case .builtIns: route = [.builtIns]
        case .draft: route = [.draft]
        }
        _path = State(initialValue: replacingPlanId == nil ? route : [])
    }

    @State private var text = ""
    @State private var issues: [Issue] = []
    @State private var preview: Plan?
    @State private var pending: Plan?
    @State private var conflicting: Plan?
    @State private var copiedPrompt = false
    @State private var copiedFixIt = false
    @State private var showFileImporter = false
    @State private var showEditor = false
    @State private var showDetails = false
    /// The review screen's "Set as current plan" toggle (D26/R0, v1.1), default on.
    @State private var makeActive = true

    private var errors: [Issue] { issues.filter { $0.severity == .error } }
    private var hasDraft: Bool { !text.trimmed.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !errors.isEmpty { errorSection }
                actionsSection
                chatbotSection
                editorSection
            }
            // D43 (v1.3): Plan detail's Replace is now called Edit JSON — the same sheet, with
            // the plan's text already open, titled for what you came to do.
            .navigationTitle(replacingPlanId == nil ? "Add plan" : "Edit JSON")
            .navigationBarTitleDisplayMode(.inline)
            // D46 (v1.4): saving a built-in plan in the picker closes this sheet with it.
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .builtIns: BuiltInPlansView { dismiss() }
                // D52 (v1.5): a plan in several pastes; saving there closes this sheet too.
                case .draft: DraftPlanView { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .bottomAction(if: hasDraft) {
                PrimaryButton(title: "Review plan") { runImport() }
            }
            .sheet(item: $preview, onDismiss: resolvePending) { plan in
                // Replace already targets a specific plan, so the toggle would be redundant.
                PlanReviewSheet(plan: plan, makeActive: replacingPlanId == nil ? $makeActive : nil) {
                    pending = plan; preview = nil
                }
            }
            .onAppear {
                if text.isEmpty { text = prefillText }
                if !prefillText.isEmpty { showEditor = true }
            }
            // An alert rather than a confirmationDialog: the dialog presentation drops the
            // cancel row when it comes up over a sheet, and O6 needs all three choices.
            .alert("A plan named \"\(conflicting?.name ?? "")\" already exists",
                   isPresented: Binding(get: { conflicting != nil },
                                        set: { if !$0 { conflicting = nil } })) {
                Button("Replace") { resolve(.replace) }
                Button("Keep both") { resolve(.keepBoth) }
                Button("Cancel", role: .cancel) { conflicting = nil }
            }
            .task {
                #if DEBUG
                // Debug-only: prefill and run the import for screenshot runs.
                let arguments = ProcessInfo.processInfo.arguments
                guard let index = arguments.firstIndex(of: "-uiImportText"),
                      let payload = arguments[safe: index + 1] else { return }
                text = payload
                while !model.loaded { try? await Task.sleep(for: .milliseconds(50)) }
                runImport()
                if arguments.contains("-uiImportSave") {
                    // Let the review sheet actually present, then do exactly what
                    // its Save plan button does, so the real ordering is exercised.
                    try? await Task.sleep(for: .milliseconds(900))
                    pending = preview
                    preview = nil
                }
                #endif
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
                guard case let .success(url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let contents = try? String(contentsOf: url, encoding: .utf8) {
                    text = contents
                    issues = []
                    runImport()
                }
            }
        }
    }

    // MARK: - The three ways in

    private var actionsSection: some View {
        Section {
            // D46 (v1.4): four routines the app ships, first in the list. Not offered when the
            // sheet is editing one plan's JSON, which is a different job.
            if replacingPlanId == nil {
                Button {
                    path.append(.builtIns)
                } label: {
                    Label("Choose a built-in plan", systemImage: "books.vertical")
                }
            }
            // A PasteButton is a no-op when the clipboard holds no text (O3), which is exactly
            // the "primary when the clipboard has text" rule without having to read the pasteboard.
            HStack {
                Label("Paste plan", systemImage: "doc.on.clipboard")
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
            Button {
                showFileImporter = true
            } label: {
                Label("Import file", systemImage: "folder")
            }
        } footer: {
            Text(hasDraft ? "Review plan checks it and shows you what it found."
                          : "Four routines to start from — or the plan you already have: paste it, or open the file.")
        }
    }

    /// The three numbered steps of the round-trip the app is built around. D50 (v1.5): step 1
    /// explains the mechanism once, its button is the accent one, and the footer says the
    /// other half — the app never talks to the chatbot itself.
    private var chatbotSection: some View {
        Section {
            step(1, PromptText.copyStep) {
                Button(copiedPrompt ? "Copied" : "Copy prompt") {
                    Clipboard.write(Prompts.render(settings: model.settings))
                    copiedPrompt = true
                    // "Copied" is feedback, not a new state; it goes back on its own (N12).
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedPrompt = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            step(2, "Paste it into ChatGPT, Claude or another chatbot, and describe your training.")
            step(3, "Copy its reply, come back, and tap Paste plan.")
            // D52 (v1.5): the same round-trip in several pastes, for long plans and free
            // chatbot tiers. A draft in progress says how far it got.
            if replacingPlanId == nil {
                Button {
                    path.append(.draft)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Build it day by day")
                        Text(model.draft.map { "Continue · " + $0.progress }
                             ?? "For long plans, or a chatbot that cuts replies short: the outline first, then one day at a time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(PressableRow())
            }
        } header: {
            Text("Create with a chatbot")
        } footer: {
            Text(PromptText.mechanism)
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

    /// The JSON itself is a detail now, not the screen (D26).
    private var editorSection: some View {
        Section {
            DisclosureGroup("Show text", isExpanded: $showEditor) {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("The plan's JSON goes here")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .font(.footnote)
        }
    }

    // MARK: - Errors

    /// D26 (v1.1): the sentence first, the path and the code behind Details.
    private var errorSection: some View {
        Section {
            ForEach(Array(errors.enumerated()), id: \.offset) { _, issue in
                VStack(alignment: .leading, spacing: 4) {
                    Text(IssueText.friendly(issue))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if showDetails {
                        VStack(alignment: .leading, spacing: 1) {
                            if !issue.path.isEmpty {
                                Text(issue.path).font(.caption.monospaced())
                            }
                            Text("\(issue.code) · \(issue.message)")
                                .font(.caption2.monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.red.opacity(0.08))
            }
            HStack {
                Button(showDetails ? "Hide details" : "Details (\(errors.count))") {
                    showDetails.toggle()
                }
                Spacer()
                Button(copiedFixIt ? "Copied" : "Copy fix-it prompt") {
                    Clipboard.write(Prompts.render(errors: errors))
                    copiedFixIt = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedFixIt = false
                    }
                }
            }
            .font(.footnote)
        } header: {
            Text(errors.count == 1 ? "This plan can't be imported yet"
                                   : "\(errors.count) things to fix")
        }
    }

    // MARK: - Saving

    private func runImport() {
        copiedFixIt = false
        showDetails = false
        let result = model.runImport(text)
        issues = result.issues
        preview = result.plan
    }

    /// Runs once the review sheet is fully dismissed: presenting the dialog in the same
    /// turn as the dismissal leaves it half-built.
    private func resolvePending() {
        guard let plan = pending else { return }
        pending = nil
        if let replacingPlanId {
            Task { await model.replacePlan(replacingPlanId, with: plan); dismiss() }
        } else if model.conflict(for: plan) != nil {
            conflicting = plan
        } else {
            Task { await model.save(plan, makeActive: makeActive); dismiss() }
        }
    }

    private func resolve(_ choice: ConflictChoice) {
        guard let plan = conflicting else { return }
        conflicting = nil
        Task {
            await model.save(plan, conflict: choice, makeActive: makeActive)
            dismiss()
        }
    }
}

/// SPEC §4.4 (D26, v1.1): **Review plan** — what the chatbot actually produced. Days expand to
/// their exercises with per-set targets, material warnings are shown and cleanup warnings are
/// folded behind Details, and the plan becomes the current one unless you say otherwise.
struct PlanReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: Plan
    /// D46 (v1.4): a built-in plan's paragraph — what it is and why — shown above the days.
    var about: String? = nil
    /// nil hides the row entirely (Replace already targets a specific plan; see ImportView).
    var makeActive: Binding<Bool>?
    let save: () -> Void

    /// The first day starts open: the whole point of this screen is seeing what the chatbot
    /// actually wrote, and a review you have to tap to begin isn't one.
    @State private var expanded: Set<Int> = [0]
    @State private var showCleanup = false

    private var split: (material: [Issue], cleanup: [Issue]) { IssueText.split(plan.warnings) }

    var body: some View {
        NavigationStack {
            List {
                if let about {
                    Section {
                        Text(about)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(plan.units.rawValue) · \(plan.schedule.rawValue) · \(plan.days.count) day\(plan.days.count == 1 ? "" : "s")")
                            .font(.footnote).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(RepeatBlock.chips(plan).enumerated()), id: \.offset) { _, name in
                                    Text(name)
                                        .font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                    }
                }
                if !split.material.isEmpty { materialWarnings }
                daysSection
                if let makeActive {
                    Section {
                        Toggle("Set as current plan", isOn: makeActive)
                    }
                }
                if !split.cleanup.isEmpty { cleanupWarnings }
            }
            .navigationTitle(plan.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .bottomAction {
                PrimaryButton(title: "Save plan") { save() }
            }
        }
    }

    /// The exercises the chatbot actually wrote, which the v1 preview never showed.
    private var daysSection: some View {
        Section("Days") {
            ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                DisclosureGroup(isExpanded: Binding(
                    get: { expanded.contains(index) },
                    set: { open in
                        if open { expanded.insert(index) } else { expanded.remove(index) }
                    })) {
                    ForEach(day.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).font(.footnote)
                            Text(TargetText.summary(exercise, units: plan.units))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } label: {
                    HStack {
                        Text(day.name)
                        Spacer()
                        Text(counts(day)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var materialWarnings: some View {
        Section("Worth knowing") {
            ForEach(Array(split.material.enumerated()), id: \.offset) { _, warning in
                VStack(alignment: .leading, spacing: 2) {
                    Text(warning.message)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    if let where_ = IssueText.location(warning.path) {
                        Text(where_).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.yellow.opacity(0.15))
            }
        }
    }

    private var cleanupWarnings: some View {
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
            Text("Tidying the app did on its own. None of it changes the workout.")
        }
    }

    private func counts(_ day: Day) -> String {
        let exercises = day.exercises.count
        let sets = day.exercises.reduce(0) { $0 + $1.sets.count }
        return "\(exercises) exercise\(exercises == 1 ? "" : "s") · \(sets) set\(sets == 1 ? "" : "s")"
    }
}
