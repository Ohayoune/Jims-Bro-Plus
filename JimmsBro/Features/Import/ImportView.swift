import SwiftUI
import UniformTypeIdentifiers

/// SPEC §4.4 (D87–D91, v1.11): **Add plan**, the round trip. One screen in three states — Ask,
/// Paste, Review — and a fourth for a refusal, each with one control: the strip large and centred
/// with **Send the prompt** and **Copy the prompt**; the system's Paste; the plan as its page draws
/// it with **Use Push Pull Legs**; the sentence in a red band with a way to send the trouble back.
/// The built-in plans are a row of squares under Ask and Paste (D90), a reply cut short can be
/// fetched day by day (D91), and the text itself is the ···'s last item (D95). What the screen
/// is and says is Core's (`ImportTrip`, `DraftTrip`); this view draws it.
///
/// Plan detail's **Edit the text** opens this view on a plan's id, which is the text sheet (D77)
/// on the whole plan, saved in place (D25, D43).
struct ImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var replacingPlanId: UUID? = nil
    var prefillText: String = ""
    private let opening: AddPlanRequest

    init(replacingPlanId: UUID? = nil, prefillText: String = "", opening: AddPlanRequest = .plan) {
        self.replacingPlanId = replacingPlanId
        self.prefillText = prefillText
        self.opening = opening
    }

    @State private var trip = ImportTrip()
    /// D91: a plan built day by day, while there is one; nil is the ordinary trip.
    @State private var draftTrip: DraftTrip?
    @State private var started = false
    /// D57: the unit the review asks for, when the plan named none.
    @State private var units: WeightUnit = .kg
    @State private var conflicting: Plan?
    /// Use makes the plan current; the ···'s Keep without using does not.
    @State private var makeActive = true
    @State private var showFileImporter = false
    @State private var editingText = false
    @State private var confirmDiscard = false
    @State private var showDetails = false
    /// The review's open rows, by place; the first starts open (the owner's 30, §6.51).
    @State private var expanded: Set<Int> = [0]
    @State private var showCleanup = false
    @State private var problem: String?

    var body: some View {
        if let replacingPlanId {
            JSONFragmentSheet(point: ImportTrip.replacing(model.plans.first { $0.id == replacingPlanId }?.name ?? "the plan",
                                                          text: prefillText)) { text in
                await replace(replacingPlanId, with: text)
            }
        } else {
            tripScreen
        }
    }

    // MARK: - The screen

    private var tripScreen: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { leading }
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
                .bottomAction { bottom.animation(.default, value: stageKey) }
        }
        .onAppear(perform: start)
        .sheet(isPresented: $editingText) {
            JSONFragmentSheet(point: textPoint) { text in await commitText(text) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let contents = try? String(contentsOf: url, encoding: .utf8) { paste(contents) }
        }
        // An alert rather than a confirmationDialog: the dialog presentation drops the cancel row
        // when it comes up over a sheet, and O6 needs all three choices.
        .alert("A plan named \"\(conflicting?.name ?? "")\" already exists",
               isPresented: Binding(get: { conflicting != nil }, set: { if !$0 { conflicting = nil } })) {
            Button("Replace") { resolve(.replace) }
            Button("Keep both") { resolve(.keepBoth) }
            Button("Cancel", role: .cancel) { conflicting = nil }
        }
        // D56 (v1.6): an alert — from a menu, a dialog's Cancel is not drawn on iOS 26.
        .alert("Discard this draft?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { discardDraft() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The outline and every day you pasted go. Nothing you saved changes.")
        }
        .alert("That plan couldn't be saved", isPresented: Binding(
            get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) { problem = nil }
        } message: {
            Text(problem ?? "")
        }
        .task {
            // A sheet can come up before the store has loaded; the draft is only known after.
            await model.waitUntilLoaded()
            start()
            await screenshotHook()
        }
    }

    /// What the animation follows: the stage, and the day a draft is on.
    private var stageKey: String {
        if let draftTrip { return "draft.\(draftTrip.stage).\(draftTrip.next ?? -1).\(draftTrip.draft == nil)" }
        return "trip.\(trip.stage)"
    }

    private var title: String {
        if let draftTrip { return draftTrip.draft?.outline.name ?? "Add plan" }
        return trip.stage == .review ? (trip.review?.name ?? "Add plan") : "Add plan"
    }

    @ViewBuilder private var content: some View {
        if let draftTrip {
            if draftTrip.draft != nil, let plan = draftTrip.preview(settings: model.settings) {
                review(plan, about: nil, asksUnits: false, hollow: draftTrip.hollow, next: draftTrip.next)
            } else {
                strip(draftTrip.strip, refusal: draftTrip.refusal, builtIns: false)
            }
        } else if trip.stage == .review, let plan = trip.review {
            review(plan, about: trip.about, asksUnits: trip.asksUnits, hollow: [], next: nil)
        } else {
            strip(trip.strip, refusal: trip.refusal, builtIns: trip.stage != .refused)
        }
    }

    /// Ask, Paste and Refused (D89): the strip large and centred, the refusal's sentence under it,
    /// and the built-ins row under a hairline at the foot on Ask and Paste (D90).
    private func strip(_ strip: TripStrip, refusal: ImportTrip.Refusal?, builtIns: Bool) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 24)
                    TripStripView(strip: strip)
                        .frame(maxWidth: 240)
                    if let refusal { refused(refusal) }
                    Spacer(minLength: 24)
                    if builtIns {
                        BuiltInPlansView { entry, plan in
                            units = plan.units
                            expanded = [0]
                            withAnimation { trip.builtIn(plan, about: entry.about) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    /// D26's rule: the sentence first, in the band; the path and the code behind Details.
    private func refused(_ refusal: ImportTrip.Refusal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let first = refusal.sentences.first { RefusedBand(sentence: first) }
            if !refusal.errors.isEmpty {
                Button(showDetails ? "Hide details" : "Details (\(refusal.errors.count))") { showDetails.toggle() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
            if showDetails {
                // The band holds the first sentence; the rest are here, each over its path.
                ForEach(Array(refusal.errors.enumerated()), id: \.offset) { index, issue in
                    VStack(alignment: .leading, spacing: 1) {
                        if index > 0 {
                            Text(IssueText.friendly(issue))
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Group {
                            if !issue.path.isEmpty { Text(issue.path).font(.caption.monospaced()) }
                            Text("\(issue.code) · \(issue.message)")
                                .font(.caption2.monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - The bottom slot

    @ViewBuilder private var bottom: some View {
        if let draftTrip {
            draftBottom(draftTrip)
        } else {
            switch trip.stage {
            case .ask:
                PromptButtons(text: Prompts.render(settings: model.settings), subject: "A workout plan",
                              buttons: trip.buttons) { withAnimation { trip.sent() } }
            case .paste:
                pasteButton(day: nil)
            case .review:
                PrimaryButton(title: trip.buttons.primary) { use(makeActive: true) }
            case .refused:
                VStack(spacing: 10) {
                    if let buttons = trip.sendButtons {
                        PromptButtons(text: trip.outgoing == .wholePlan ? Prompts.render(errors: trip.refusal?.errors ?? [])
                                                                        : Prompts.render(settings: model.settings),
                                      subject: "A workout plan", buttons: buttons) {
                            showDetails = false
                            withAnimation { trip.fix() }
                        }
                    }
                    if trip.refusal?.offersDayByDay == true, let dayByDay = trip.buttons.secondary {
                        Button {
                            showDetails = false
                            withAnimation { draftTrip = DraftTrip(draft: model.draft) }
                        } label: {
                            Label(dayByDay, systemImage: "square.split.2x1")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.large)
                    }
                }
            }
        }
    }

    /// D91: once the outline is in, the strip sits small above the buttons, with a refused day's
    /// sentence under it; the buttons are for the first hollow day.
    @ViewBuilder private func draftBottom(_ draftTrip: DraftTrip) -> some View {
        let text = draftTrip.next.flatMap { model.dayPrompt($0) } ?? model.outlinePrompt()
        VStack(spacing: 12) {
            if draftTrip.draft != nil, draftTrip.stage != .review {
                TripStripView(strip: draftTrip.strip, side: 40)
                    .frame(maxWidth: 150)
                if let sentence = draftTrip.refusal?.sentences.first { RefusedBand(sentence: sentence) }
            }
            switch draftTrip.stage {
            case .ask, .refused:
                PromptButtons(text: text, subject: draftTrip.nextName.map { "\($0), one day" } ?? "A plan's outline",
                              buttons: draftTrip.buttons) {
                    withAnimation { self.draftTrip?.sent() }
                }
            case .paste:
                pasteButton(day: draftTrip.next)
            case .review:
                PrimaryButton(title: draftTrip.buttons.primary) { useDraft(makeActive: true) }
            }
        }
    }

    /// Paste (§6.60): the system's button, large and alone — no permission alert, and nothing
    /// when the clipboard holds no text. For a draft's day, the day's square and name above it.
    private func pasteButton(day: Int?) -> some View {
        VStack(spacing: 10) {
            if let day, let name = draftTrip?.nextName {
                HStack(spacing: 8) {
                    DaySquare(colour: DayColour.of(dayIndex: day), size: 14, outlined: true)
                    Text(name).font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in paste(text) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The toolbar

    @ViewBuilder private var leading: some View {
        if let draftTrip, draftTrip.draft == nil {
            // Before the outline, back to the refusal's screen, which is Ask again.
            Button {
                withAnimation { self.draftTrip = nil; trip.restart() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Back")
        } else if draftTrip == nil, trip.stage != .ask {
            Button {
                showDetails = false
                withAnimation { trip.restart() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Back")
        } else {
            Button("Cancel") { dismiss() }
        }
    }

    /// D95 (§6.68): the ···, its items Core's, Edit the text last.
    private var menu: some View {
        Menu {
            ForEach(Array((draftTrip?.menu ?? trip.menu).enumerated()), id: \.offset) { _, item in
                Button(role: item == .discardDraft ? .destructive : nil) { choose(item) } label: {
                    Label(item.title, systemImage: symbol(item))
                }
            }
        } label: {
            // In a toolbar the system draws the quiet circle (D69) itself, as on Plan detail.
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private func symbol(_ item: ImportTrip.MenuItem) -> String {
        switch item {
        case .sendAgain: return "square.and.arrow.up"
        case .openFile: return "folder"
        case .keepWithoutUsing: return "tray.and.arrow.down"
        case .discardDraft: return "trash"
        case .editText: return "curlybraces"
        }
    }

    private func choose(_ item: ImportTrip.MenuItem) {
        switch item {
        // Back to Ask, where the prompt goes out again through the same two buttons.
        case .sendAgain: withAnimation { trip.restart() }
        case .openFile: showFileImporter = true
        case .keepWithoutUsing: draftTrip == nil ? use(makeActive: false) : useDraft(makeActive: false)
        case .discardDraft: confirmDiscard = true
        case .editText: editingText = true
        }
    }

    // MARK: - The review

    /// Review (§4.4): the plan as its page draws it — the unit asked when it named none, the
    /// cycle as joined squares with how often, the days closed until tapped with the first open,
    /// Worth knowing only when there is something worth knowing, the tidying behind Details. A
    /// draft's unfilled days are hollow, the first of them marked next (D91).
    private func review(_ plan: Plan, about: String?, asksUnits: Bool, hollow: Set<Int>, next: Int?) -> some View {
        let shownUnits = asksUnits ? units : plan.units
        let split = IssueText.split(plan.warnings)
        return List {
            if let about {
                Section {
                    Text(about)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if asksUnits {
                Section {
                    Picker("Weights in", selection: $units) {
                        ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Weights in", systemImage: "scalemass")
                }
            }
            Section { cycle(plan, units: shownUnits, hollow: hollow) }
            if !split.material.isEmpty {
                Section("Worth knowing") {
                    ForEach(Array(split.material.enumerated()), id: \.offset) { _, warning in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(warning.message)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                            if let place = IssueText.location(warning.path) {
                                Text(place).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(Color.yellow.opacity(0.15))
                    }
                }
            }
            Section {
                let rows = PlanPage.rows(plan)
                let nextRow = next.flatMap { index in rows.first { $0.dayIndex == index }?.id }
                ForEach(rows) { row in
                    dayRow(row, in: plan, units: shownUnits, hollow: row.dayIndex.map(hollow.contains) ?? false,
                           isNext: row.id == nextRow)
                }
            }
            if !split.cleanup.isEmpty {
                Section {
                    DisclosureGroup("Details (\(split.cleanup.count))", isExpanded: $showCleanup) {
                        Text("Tidying the app did on its own. None of it changes the workout.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                }
            }
        }
    }

    /// The cycle as the plan's page draws it (D86), where the chips were, with the unit and how
    /// often above it; a draft's unfilled days outlined.
    private func cycle(_ plan: Plan, units: WeightUnit, hollow: Set<Int>) -> some View {
        let squares = ImportTrip.squares(plan, hollow: hollow)
        return VStack(alignment: .leading, spacing: 10) {
            Text([units.rawValue, PlanText.howOften(plan)].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            CycleStrip(count: squares.count, side: 40, spacing: 2, lineSpacing: 10) { index in
                let square = squares[index]
                VStack(spacing: 4) {
                    if let weekday = square.weekday {
                        Text(WeekdayText.short(weekday)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    StripSquare(colour: square.colour, outlined: square.hollow, index: index, count: squares.count)
                    Text(square.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dayRow(_ row: CycleSquare, in plan: Plan, units: WeightUnit, hollow: Bool, isNext: Bool) -> some View {
        if let index = row.dayIndex, !hollow, let day = plan.days[safe: index] {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(row.id) },
                set: { open in if open { expanded.insert(row.id) } else { expanded.remove(row.id) } })) {
                ForEach(day.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).font(.footnote)
                        Text(TargetText.summary(exercise, units: units, wording: model.settings.wording))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } label: {
                rowLabel(row, hollow: false, isNext: false, trailing: counts(day))
            }
        } else {
            rowLabel(row, hollow: hollow, isNext: isNext, trailing: nil)
        }
    }

    private func rowLabel(_ row: CycleSquare, hollow: Bool, isNext: Bool, trailing: String?) -> some View {
        HStack(spacing: 12) {
            DaySquare(colour: row.colour, size: 14, outlined: hollow)
            Text(row.name)
                .foregroundStyle(hollow || row.dayIndex == nil ? Color.secondary : Color.primary)
            if let weekday = row.weekday {
                Text(WeekdayText.full(weekday)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isNext {
                Label("next", systemImage: "arrow.right")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else if let trailing {
                Text(trailing).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func counts(_ day: Day) -> String {
        let exercises = day.exercises.count
        let sets = day.exercises.reduce(0) { $0 + $1.sets.count }
        return "\(exercises) exercise\(exercises == 1 ? "" : "s") · \(sets) set\(sets == 1 ? "" : "s")"
    }

    // MARK: - Pasting

    /// Add plan opens on Ask; a draft in progress reopens on its review (§6.64). Once, and only
    /// with the store loaded.
    private func start() {
        guard !started, model.loaded else { return }
        started = true
        if model.draft != nil || opening == .draft { draftTrip = DraftTrip(draft: model.draft) }
    }

    /// Whatever was pasted, or read from a file, goes through the pipeline for the stage it is at.
    private func paste(_ text: String) {
        showDetails = false
        if let current = draftTrip {
            Task {
                var moved = current
                if let index = current.next {
                    let issues = await model.pasteDraftDay(text, into: index)
                    moved.pasted(index: index, read: (Self.hasErrors(issues) ? nil : model.draft, issues))
                } else {
                    let issues = await model.startDraft(text)
                    moved.pastedOutline((Self.hasErrors(issues) ? nil : model.draft, issues))
                }
                withAnimation { draftTrip = moved }
            }
            return
        }
        let result = model.runImport(text)
        units = result.plan?.units ?? model.settings.units
        expanded = [0]
        withAnimation { trip.pasted(result: result, text: text) }
    }

    private static func hasErrors(_ issues: [Issue]) -> Bool { issues.contains { $0.severity == .error } }

    // MARK: - The text behind the ··· (D95)

    private var textPoint: JSONPoint {
        guard let draftTrip else { return trip.textPoint }
        let assembled = draftTrip.stage == .review ? model.assembleDraft().plan?.sourceText : nil
        return draftTrip.textPoint(assembled: assembled)
    }

    /// The sheet's Save is the paste it stands for: an error stays in the sheet at its line, and
    /// a text that reads moves this screen on.
    private func commitText(_ text: String) async -> [Issue] {
        if var draftTrip {
            switch draftTrip.textTarget {
            case let .day(index):
                let issues = await model.pasteDraftDay(text, into: index)
                if Self.hasErrors(issues) { return issues.filter { $0.severity == .error } }
                draftTrip.pasted(index: index, read: (model.draft, issues))
            case .outline:
                let issues = await model.startDraft(text)
                if Self.hasErrors(issues) { return issues.filter { $0.severity == .error } }
                draftTrip.pastedOutline((model.draft, issues))
            }
            withAnimation { self.draftTrip = draftTrip }
            return []
        }
        let result = model.runImport(text)
        guard result.plan != nil, result.errors.isEmpty else { return result.errors }
        units = result.plan?.units ?? model.settings.units
        expanded = [0]
        withAnimation { trip.pasted(result: result, text: text) }
        return []
    }

    // MARK: - Saving

    /// Use, or Keep without using: the plan as reviewed, through the ordinary save — a name
    /// conflict asks (O6), a built-in plan is kept beside a copy of itself (§6.8).
    private func use(makeActive: Bool) {
        guard let plan = trip.planToSave(units: units) else { return }
        self.makeActive = makeActive
        if trip.fromBuiltIn {
            Task { await model.save(plan, conflict: .keepBoth, makeActive: makeActive); dismiss() }
        } else if model.conflict(for: plan) != nil {
            conflicting = plan
        } else {
            Task { await model.save(plan, makeActive: makeActive); dismiss() }
        }
    }

    /// A draft with every day in: assembled and saved like any plan, and the draft let go only
    /// when the save went through (§6.28).
    private func useDraft(makeActive: Bool) {
        let result = model.assembleDraft()
        guard let plan = result.plan else {
            problem = result.errors.first.map(IssueText.friendly) ?? "The plan couldn't be put together."
            return
        }
        self.makeActive = makeActive
        if model.conflict(for: plan) != nil {
            conflicting = plan
        } else {
            Task { if await model.saveDraftPlan(plan, makeActive: makeActive) != nil { dismiss() } }
        }
    }

    private func resolve(_ choice: ConflictChoice) {
        guard let plan = conflicting else { return }
        conflicting = nil
        Task {
            if draftTrip != nil {
                if await model.saveDraftPlan(plan, conflict: choice, makeActive: makeActive) != nil { dismiss() }
            } else {
                await model.save(plan, conflict: choice, makeActive: makeActive)
                dismiss()
            }
        }
    }

    private func discardDraft() {
        Task { await model.discardDraft() }
        withAnimation {
            draftTrip = nil
            trip.restart()
        }
    }

    /// Plan detail's Edit the text: the whole plan through the pipeline, saved in place. A text
    /// that no longer names its unit keeps the plan's (D57 asks only on a new plan's review).
    private func replace(_ id: UUID, with text: String) async -> [Issue] {
        let result = model.runImport(text)
        guard var plan = result.plan, result.errors.isEmpty else { return result.errors }
        if !result.unitsStated, let old = model.plans.first(where: { $0.id == id }) {
            plan.units = old.units
            plan.sourceText = PlanJSON.render(plan)
        }
        _ = await model.replacePlan(id, with: plan)
        return []
    }

    #if DEBUG
    /// Debug-only: paste a text and, with `-uiImportSave`, Use it, for screenshot runs.
    private func screenshotHook() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiImportText"), let payload = arguments[safe: index + 1] else { return }
        paste(payload)
        if arguments.contains("-uiImportSave") {
            try? await Task.sleep(for: .milliseconds(900))
            use(makeActive: true)
        }
    }
    #else
    private func screenshotHook() async {}
    #endif
}
