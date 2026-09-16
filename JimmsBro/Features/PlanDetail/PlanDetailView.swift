import SwiftUI

/// SPEC §4.3: the repeat block, the days, and the secondary actions behind "···". Since D78
/// (v1.9, §6.51) the repeat block is the cycle as squares, and the days are the whole cycle again
/// as rows, each closed until tapped.
struct PlanDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let planId: UUID
    @Binding var showWorkout: Bool

    @State private var renaming = false
    @State private var draftName = ""
    @State private var copied = false
    @State private var switching: Int?
    /// D78 (v1.9): the rows open, by their place on the page — the screen's, never stored.
    @State private var open: Set<Int> = []
    /// D25/D26 (v1.1): Replace opens Import pre-filled with this plan's JSON, targeting its id.
    @State private var replacing = false
    /// D25 (v1.1): Delete now confirms here too, matching every other delete path.
    @State private var confirmDelete = false
    /// D29 (v1.1): basic plan editing, so a one-word change doesn't mean a round trip to a chatbot.
    @State private var editing: ExerciseAddress?
    @State private var renamingDay: Int?
    @State private var draftDayName = ""
    @State private var editError: String?
    /// D43 (v1.3): the JSON sheet that is open, and the one to open once the exercise sheet
    /// has finished dismissing (presenting the next in the same turn leaves it half-built).
    @State private var fragment: FragmentTarget?
    @State private var pendingFragment: FragmentTarget?
    private var plan: Plan? { model.plans.first { $0.id == planId } }

    var body: some View {
        Group {
            if let plan {
                List {
                    // D67 (v1.7): no Progression row here since the owner's review — it is
                    // History's, beside the numbers a progression is planned from (§6.42).
                    Section { repeatBlock(plan) }
                    // D78 (v1.9): the whole cycle again as rows, repeats included, each day closed
                    // until tapped. An open day is v1.8's section — its exercises and their sheet,
                    // Edit mode's reorder and delete (D29), Add exercise, Start — with the day's
                    // menu on its row. A rest is a row with nothing to open.
                    ForEach(PlanPage.rows(plan)) { row in
                        Section {
                            if let index = row.dayIndex, let day = plan.days[safe: index] {
                                let isOpen = open.contains(row.id)
                                HStack(spacing: 4) {
                                    Button { toggle(row.id) } label: { rowLabel(row, isOpen: isOpen) }
                                        .buttonStyle(PressableRow())
                                        .accessibilityValue(isOpen ? "Open" : "Closed")
                                    if isOpen { dayMenu(day, index) }
                                }
                                if isOpen { dayContent(plan, day, index) }
                            } else {
                                rowLabel(row, isOpen: nil)
                            }
                        }
                    }
                }
                .listSectionSpacing(.compact)
                .navigationTitle(plan.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    menu(plan)
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
                .sheet(item: $editing, onDismiss: {
                    if let next = pendingFragment { pendingFragment = nil; fragment = next }
                }) { address in
                    if let exercise = plan.days[safe: address.day]?.exercises[safe: address.exercise] {
                        ExerciseEditSheet(exercise: exercise, units: plan.units, editAsJSON: {
                            pendingFragment = .exercise(day: address.day, exercise: address.exercise)
                            editing = nil
                        }) { operation in
                            edit(operation(address))
                        }
                    }
                }
                // D43 (v1.3): one sheet for every JSON edit; Save is a `PlanEdit.Operation`
                // through the import pipeline, and a refusal stays in the sheet with the text.
                // D77 (v1.9): the point says what the JSON is, where it lands and what Save does.
                .sheet(item: $fragment) { target in
                    if let point = target.point(plan) {
                        JSONFragmentSheet(point: point) { text in
                            guard let operation = point.operation(text) else { return [] }
                            return await model.editPlan(planId, operation)
                        }
                    }
                }
                .alert("Rename day", isPresented: Binding(get: { renamingDay != nil },
                                                          set: { if !$0 { renamingDay = nil } })) {
                    TextField("Name", text: $draftDayName)
                    Button("Cancel", role: .cancel) { renamingDay = nil }
                    Button("Rename") {
                        if let day = renamingDay { edit(.renameDay(day: day, name: draftDayName)) }
                        renamingDay = nil
                    }
                }
                // D29: an edit that the import pipeline refuses says why, rather than
                // appearing to work and changing nothing.
                .alert("That change wasn't saved", isPresented: Binding(
                    get: { editError != nil }, set: { if !$0 { editError = nil } })) {
                    Button("OK", role: .cancel) { editError = nil }
                } message: {
                    Text(editError ?? "")
                }
                .alert(switchPrompt, isPresented: Binding(get: { switching != nil },
                                                          set: { if !$0 { switching = nil } })) {
                    Button("Keep going", role: .cancel) { switchDay(nil) }
                    Button("Finish and start") { switchDay(.finish) }
                    Button("Discard and start", role: .destructive) { switchDay(.discard) }
                }
                .alert("Rename plan", isPresented: $renaming) {
                    TextField("Name", text: $draftName)
                    Button("Cancel", role: .cancel) {}
                    Button("Rename") { Task { await model.renamePlan(planId, to: draftName) } }
                }
                // D56 (v1.6): an alert, because a dialog presented from the ··· menu draws as a
                // popover on iOS 26 and drops its Cancel.
                .alert("Delete \(plan.name)?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) { Task { await model.deletePlan(planId); dismiss() } }
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(isPresented: $replacing) {
                    ImportView(replacingPlanId: planId, prefillText: plan.sourceText).environment(model)
                }
            } else {
                ContentUnavailableView("Plan deleted", systemImage: "trash")
            }
        }
    }

    private func edit(_ operation: PlanEdit.Operation) {
        Task {
            let errors = await model.editPlan(planId, operation)
            if let first = errors.first { editError = IssueText.friendly(first) }
        }
    }

    private var switchPrompt: String {
        guard let session = model.session else { return "Switch workout?" }
        let logged = SessionStats.loggedCount(session)
        return "You're in the middle of \(session.dayName) (\(logged) of \(session.steps.count) sets). "
            + "Switching workouts mid-session isn't recommended."
    }

    private func repeatBlock(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // D59 (v1.6): "kg · repeats every 7 days" — "rotation" was the format's word, not
            // the person's.
            Text([plan.units.rawValue, RepeatBlock.caption(plan)?.lowercased()].compactMap { $0 }
                .joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            // D78 (v1.9): the cycle as squares where D59's chips were — each its day's colour
            // with its name beneath, the entry Next up would start named in ink, and a weekday
            // plan's weekday above each. D86 (v1.10, §6.59): seven to a row and touching, today's
            // square outlined in ink.
            let squares = RepeatBlock.squares(plan)
            CycleStrip(count: squares.count, side: 40, spacing: 2, lineSpacing: 10) { index in
                let square = squares[index]
                VStack(spacing: 4) {
                    if let weekday = square.weekday {
                        Text(weekday)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    StripSquare(colour: square.colour, ringed: square.isToday, index: index, count: squares.count)
                    Text(square.name)
                        .font(.caption2.weight(square.isNow ? .semibold : .regular))
                        .foregroundStyle(square.isNow ? .primary : .secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 4)
    }

    /// A row of the cycle: the day's square and name, a weekday plan's weekday beside it, and on
    /// a day a chevron that turns down while it is open. A day opens in place rather than onto a
    /// screen, so its chevron is grey, not the accent of a row that opens one.
    private func rowLabel(_ row: PlanPage.Row, isOpen: Bool?) -> some View {
        HStack(spacing: 12) {
            DaySquare(colour: row.colour, size: 14)
            Text(row.name)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let weekday = row.weekday {
                Text(weekday).foregroundStyle(.secondary)
            }
            if let isOpen {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ id: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            if open.contains(id) { open.remove(id) } else { open.insert(id) }
        }
    }

    /// The day's menu, on its row while the day is open — v1.8's header menu, the same four items.
    private func dayMenu(_ day: Day, _ index: Int) -> some View {
        Menu {
            Button("Rename day") {
                draftDayName = day.name
                renamingDay = index
            }
            Button("Duplicate day") { edit(.duplicateDay(day: index)) }
            // D43 (v1.3): the day as text, and a new exercise typed in.
            Button("Add exercise") { fragment = .addExercise(day: index) }
            Button("Edit day as JSON") { fragment = .day(index) }
        } label: {
            Image(systemName: "ellipsis")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Edit \(day.name)")
    }

    /// An open day: v1.8's section, unchanged — its exercises and their sheet, Edit mode's
    /// reorder and delete (D29), Add exercise and Start.
    @ViewBuilder private func dayContent(_ plan: Plan, _ day: Day, _ index: Int) -> some View {
        ForEach(Array(day.exercises.enumerated()), id: \.element.id) { position, exercise in
            Button {
                editing = ExerciseAddress(day: index, exercise: position)
            } label: {
                ExerciseRow(exercise: exercise, units: plan.units)
            }
            .buttonStyle(PressableRow())
        }
        .onMove { offsets, destination in
            guard let from = offsets.first else { return }
            // SwiftUI's destination is the gap; an index is what we move to.
            let to = destination > from ? destination - 1 : destination
            edit(.moveExercise(day: index, from: from, to: to))
        }
        .onDelete { offsets in
            guard let position = offsets.first else { return }
            edit(.deleteExercise(day: index, exercise: position))
        }
        // D59 (v1.6): Add exercise as a row, not only behind the day's ···;
        // Start as a button, not a text link at the end of a list.
        Button { fragment = .addExercise(day: index) } label: {
            Label("Add exercise", systemImage: "plus")
        }
        Button("Start \(day.name)") { start(plan, index) }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Color.accentColor)
    }

    @ToolbarContentBuilder private func menu(_ plan: Plan) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // D78 (v1.9): the plan is changed from the Plans list's circle, the one way.
                Button("Rename") { draftName = plan.name; renaming = true }
                Button(copied ? "Copied" : "Copy JSON") { Clipboard.write(plan.sourceText); copied = true }
                // D43 (v1.3): the plan's text, editable; and a day pasted in whole — the way
                // to finish a week the chatbot cut short.
                Button("Edit JSON") { replacing = true }
                Button("Add day from JSON") { fragment = .addDay }
                Button("Delete", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }

    /// D17: starting a day mid-session raises the popup rather than switching silently.
    /// D48 (v1.4): the cover opens on `startedWorkouts`, not after the await — the refusal is
    /// thrown before anything changes, so the popup still comes from here.
    private func start(_ plan: Plan, _ dayIndex: Int) {
        Task {
            do {
                try await model.startDay(planId: planId, dayIndex: dayIndex)
            } catch LibraryError.sessionInProgress {
                switching = dayIndex
            } catch {
                switching = nil
            }
        }
    }

    private func switchDay(_ choice: SessionSwitch?) {
        guard let dayIndex = switching else { return }
        switching = nil
        guard let choice else { return }
        Task { try? await model.startDay(planId: planId, dayIndex: dayIndex, switching: choice) }
    }
}

private struct ExerciseRow: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let units: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let group = exercise.group {
                    Text(group)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
                Text(exercise.name)
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let notes = exercise.notes {
                Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// "3 × 8–12 · 24 / 26 / 28 kg · rest 90 s". v1.1 (R3): `TargetText.summary` shows what
    /// varies across the sets instead of repeating the first set's target as if it were all of them.
    private var detail: String {
        guard let first = exercise.sets.first else { return "No sets" }
        var parts = [TargetText.summary(exercise, units: units, wording: model.settings.wording)]
        parts.append("rest \(first.restSeconds) s")
        if exercise.bodyweight { parts.append("bodyweight") }
        return parts.joined(separator: " · ")
    }
}

/// Which exercise the edit sheet is for.
struct ExerciseAddress: Identifiable, Equatable {
    let day: Int
    let exercise: Int
    var id: String { "\(day).\(exercise)" }
}

/// SPEC §4.3 (D29, v1.1): the fields a plan edit can change. Each row commits one
/// `PlanEdit.Operation`, so every change goes through the import pipeline on its own and a
/// refusal never leaves the sheet in a state the plan does not have.
struct ExerciseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let units: WeightUnit
    /// D43 (v1.3): hands over to the JSON sheet for what the fields cannot say — one set
    /// unlike the others, drops, a warning beep.
    var editAsJSON: (() -> Void)? = nil
    /// Called with a builder, so the sheet doesn't need to know its own address.
    let commit: (@escaping (ExerciseAddress) -> PlanEdit.Operation) -> Void

    @State private var name = ""
    @State private var reps = ""
    @State private var range = ""
    @State private var weight = ""
    @State private var rest = ""
    /// D51 (v1.5): the effort target, empty when the plan did not say.
    @State private var reserve = ""
    @State private var sets = 1
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    Text("The name is how the app finds this exercise in your history, so keep it the same as last time.")
                }

                Section("Sets") {
                    Stepper("\(sets) set\(sets == 1 ? "" : "s")", value: $sets, in: 1...50)
                }

                Section {
                    LabeledContent("Reps") {
                        TextField("8-12", text: $reps)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Rep range") {
                        TextField("optional", text: $range)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(units.rawValue) {
                        TextField("none", text: Binding(
                            get: { weight },
                            set: { weight = InputRules.weight($0, previous: weight) }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Rest") {
                        HStack(spacing: 4) {
                            TextField("90", text: Binding(
                                get: { rest },
                                set: { rest = InputRules.seconds($0, previous: rest) }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("s").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("In reserve") {
                        TextField("none", text: Binding(
                            get: { reserve },
                            set: { reserve = String($0.filter(\.isNumber).prefix(2)) }))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Reps takes a number, a range like 8-12, AMRAP or 5+, or a time: 45s, 30s+ for a minimum hold, or open. "
                         + "In reserve is how many reps (or seconds, on a hold) short of failure to stop, 0 to 20.")
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
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                name = exercise.name
                sets = exercise.sets.count
                reps = exercise.sets.first.map { PlanEdit.text(for: $0.work) } ?? ""
                range = exercise.repRange.map { "\($0.min)-\($0.max)" } ?? ""
                weight = InputRules.weightText(exercise.sets.first?.weight)
                rest = exercise.sets.first.map { String($0.restSeconds) } ?? ""
                reserve = exercise.sets.first?.inReserve.map(String.init) ?? ""
            }
        }
    }

    private var canSave: Bool {
        !name.trimmed.isEmpty
            && PlanEdit.parseWork(reps) != nil
            && (range.trimmed.isEmpty || PlanEdit.parseRange(range) != nil)
            && (rest.isEmpty || InputRules.secondsValue(rest).map { (0...3600).contains($0) } == true)
            && (reserve.isEmpty || Int(reserve).map { (0...20).contains($0) } == true)
    }

    /// Only the fields that actually changed are sent, so an untouched exercise is untouched.
    private func save() {
        if name.trimmed != exercise.name {
            commit { .renameExercise(day: $0.day, exercise: $0.exercise, name: name) }
        }
        if sets != exercise.sets.count {
            commit { .setSetCount(day: $0.day, exercise: $0.exercise, count: sets) }
        }
        if let work = PlanEdit.parseWork(reps), work != exercise.sets.first?.work {
            commit { .setReps(day: $0.day, exercise: $0.exercise, text: reps) }
        }
        let newRange = range.trimmed.isEmpty ? nil : PlanEdit.parseRange(range)
        if newRange != exercise.repRange {
            commit { .setRepRange(day: $0.day, exercise: $0.exercise,
                                  text: range.trimmed.isEmpty ? nil : range) }
        }
        let newWeight = InputRules.weightValue(weight)
        if newWeight != exercise.sets.first?.weight {
            commit { .setWeight(day: $0.day, exercise: $0.exercise, weight: newWeight) }
        }
        if let seconds = InputRules.secondsValue(rest), seconds != exercise.sets.first?.restSeconds {
            commit { .setRest(day: $0.day, exercise: $0.exercise, seconds: seconds) }
        }
        let newReserve = reserve.isEmpty ? nil : Int(reserve)
        if newReserve != exercise.sets.first?.inReserve {
            commit { .setInReserve(day: $0.day, exercise: $0.exercise, value: newReserve) }
        }
        dismiss()
    }
}
