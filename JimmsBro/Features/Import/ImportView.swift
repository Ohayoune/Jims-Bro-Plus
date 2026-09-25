import SwiftUI
import UniformTypeIdentifiers

/// SPEC §4.4 (D87–D91, v1.11): **Add plan**, the round trip. One screen in three states — Ask,
/// Paste, Review — and a fourth for a refusal, each with one control: the strip large and centred
/// with **Send the prompt** and **Copy the prompt**; the system's Paste; the plan as its page draws
/// it with **Use Push Pull Legs**; the sentence in a red band with a way to send the trouble back.
/// The built-in plans are a row of squares under Ask and Paste (D90), a reply cut short can be
/// fetched day by day (D91), and the text itself is the ···'s last item (D95). What the screen
/// is and says is Core's (`ImportTrip`, `DraftTrip`); this view draws it.
struct ImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var opening: AddPlanRequest = .plan

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
    /// The review's open rows, by place; the first starts open (the owner's 30, §6.51).
    @State private var expanded: Set<Int> = [0]
    @State private var problem: String?

    // MARK: - The screen

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { leading }
                    ToolbarItem(placement: .topBarTrailing) {
                        // D95 (§6.68): the ···, its items Core's, Edit the text last.
                        TripMenu(items: draftTrip?.menu ?? trip.menu, choose: choose)
                    }
                    .quietBackground()
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
            if let plan = draftTrip.preview {
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
    private func strip(_ strip: TripStrip, refusal: TripRefusal?, builtIns: Bool) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 24)
                    TripStripView(strip: strip)
                        .frame(maxWidth: 240)
                    if let refusal { RefusalDetails(refusal: refusal) }
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

    // MARK: - The bottom slot

    @ViewBuilder private var bottom: some View {
        if let draftTrip {
            draftBottom(draftTrip)
        } else {
            switch trip.stage {
            case .ask, .refused:
                VStack(spacing: 10) {
                    PromptButtons(text: trip.prompt(settings: model.settings), subject: trip.subject,
                                  buttons: trip.buttons) { withAnimation { trip.sent() } }
                    if trip.refusal?.offersDayByDay == true {
                        Button {
                            withAnimation { draftTrip = DraftTrip(draft: model.draft, settings: model.settings) }
                        } label: {
                            Label(TripRefusal.dayByDay, systemImage: "square.split.2x1")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.large)
                    }
                }
            case .paste:
                pasteButton(day: nil)
            case .review:
                PrimaryButton(title: trip.buttons.primary) { use(makeActive: true) }
            }
        }
    }

    /// D91: once the outline is in, the strip sits small above the buttons, with a refused day's
    /// sentence under it; the buttons are for the first hollow day.
    @ViewBuilder private func draftBottom(_ draftTrip: DraftTrip) -> some View {
        VStack(spacing: 12) {
            if draftTrip.draft != nil, draftTrip.stage != .review {
                TripStripView(strip: draftTrip.strip, side: 40)
                    .frame(maxWidth: 150)
                if let refusal = draftTrip.refusal { RefusalDetails(refusal: refusal) }
            }
            switch draftTrip.stage {
            case .ask, .refused:
                PromptButtons(text: draftTrip.prompt(settings: model.settings), subject: draftTrip.subject,
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
            TripPasteButton(size: .extraLarge, paste: paste)
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
                withAnimation { trip.restart() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Back")
        } else {
            Button("Cancel") { dismiss() }
        }
    }

    private func choose(_ item: TripMenuItem) {
        switch item {
        // Back to Ask, where the prompt goes out again through the same two buttons.
        case .sendAgain: withAnimation { trip.restart() }
        case .openFile: showFileImporter = true
        case .keepWithoutUsing: draftTrip == nil ? use(makeActive: false) : useDraft(makeActive: false)
        case .discardDraft: confirmDiscard = true
        case .editText: editingText = true
        case .keepCurrent, .removeProgression: break
        }
    }

    // MARK: - The review

    /// Review (§4.4): the plan as its page draws it — the unit asked when it named none, the
    /// cycle as joined squares with how often, the days closed until tapped with the first open,
    /// Worth knowing only when there is something worth knowing, the tidying behind Details. A
    /// draft's unfilled days are hollow, the first of them marked next (D91).
    private func review(_ plan: Plan, about: String?, asksUnits: Bool, hollow: Set<Int>, next: Int?) -> some View {
        let shownUnits = asksUnits ? units : plan.units
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
            WorthKnowing(warnings: plan.warnings)
            Section {
                let rows = PlanPage.rows(plan)
                let nextRow = next.flatMap { index in rows.first { $0.dayIndex == index }?.id }
                ForEach(rows) { row in
                    dayRow(row, in: plan, units: shownUnits, hollow: row.dayIndex.map(hollow.contains) ?? false,
                           isNext: row.id == nextRow)
                }
            }
            Tidying(warnings: plan.warnings)
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
        if model.draft != nil || opening == .draft { draftTrip = DraftTrip(draft: model.draft, settings: model.settings) }
    }

    /// Whatever was pasted, or read from a file, goes through the pipeline for the stage it is at.
    private func paste(_ text: String) {
        if let current = draftTrip {
            Task {
                var moved = current
                let issues = await pasteIntoDraft(text, at: current.textTarget)
                moved.pasted((Self.hasErrors(issues) ? nil : model.draft, issues), settings: model.settings)
                withAnimation { draftTrip = moved }
            }
            return
        }
        let result = model.runImport(text)
        units = result.plan?.units ?? model.settings.units
        expanded = [0]
        withAnimation { trip.pasted(result: result, text: text) }
    }

    /// A draft's paste goes to the next hollow day's slot, or — before the outline — is the outline.
    private func pasteIntoDraft(_ text: String, at target: DraftTrip.TextTarget) async -> [Issue] {
        switch target {
        case let .day(index): return await model.pasteDraftDay(text, into: index)
        case .outline: return await model.startDraft(text)
        }
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
            let issues = await pasteIntoDraft(text, at: draftTrip.textTarget)
            if Self.hasErrors(issues) { return issues.filter { $0.severity == .error } }
            draftTrip.pasted((model.draft, issues), settings: model.settings)
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
