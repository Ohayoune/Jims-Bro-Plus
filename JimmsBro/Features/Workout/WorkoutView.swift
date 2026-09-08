import SwiftUI

/// SPEC §4.5 (D22): one screen, five fixed zones — header, exercise block, inputs, status strip,
/// primary action — in that order in every state. Working, resting, a running timed set and a
/// block having just finished change only what the zones hold. The middle two scroll; the strip
/// and the primary button live in a bottom safe-area inset, so they keep their position under
/// the thumb and stay above the keyboard.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showOverview = false
    @State private var showFinishConfirm = false
    @State private var showDiscardConfirm = false
    @State private var editing: Int?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
                .task(id: Int(context.date.timeIntervalSince1970)) {
                    await model.tick(now: context.date)
                }
        }
        .navigationDestination(for: HistoryRoute.self) { route in
            if case let .exercise(name, units) = route {
                ExerciseHistoryView(name: name, units: units)
            }
        }
        .sheet(isPresented: $showOverview) { OverviewView() }
        .sheet(item: Binding(
            get: { model.session.flatMap { s in editing.map { EditTarget(session: s, step: $0) } } },
            set: { editing = $0?.step })) { target in
            EditResultSheet(target: target) { result in
                Task { await model.apply(.editSet(step: target.step, result: result)) }
            }
        }
        .task {
            #if DEBUG
            // Debug-only: open the overview directly for screenshot runs.
            if ProcessInfo.processInfo.arguments.contains("-uiOverview") {
                try? await Task.sleep(for: .milliseconds(600))
                showOverview = true
            }
            #endif
        }
        .confirmationDialog(finishPrompt, isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish workout", role: .destructive) { Task { await model.finish() } }
            Button("Keep going", role: .cancel) {}
        }
        .confirmationDialog("Nothing was logged. Discard this workout?",
                            isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { Task { await model.discardSession(); dismiss() } }
            Button("Keep going", role: .cancel) {}
        }
        // D24: this cover is presented over RootView, so its copy of the alert cannot be seen
        // from here. A set logged into a store that refuses writes must still say so.
        .saveFailureAlert(model: model, enabled: true)
    }

    private var finishPrompt: String {
        let pending = model.pendingStepCount
        return pending == 0 ? "Finish workout?" : "\(pending) set\(pending == 1 ? "" : "s") not done. Finish anyway?"
    }

    @ViewBuilder private func content(now: Date) -> some View {
        if let active = model.engine?.active, model.phase != .completed,
           let screen = WorkoutScreen.model(active: active, history: model.sessions, now: now,
                                            settings: model.settings) {
            WorkoutScreenView(screen: screen, now: now, showOverview: $showOverview,
                              editing: $editing, minimize: { dismiss() }, finish: requestFinish)
                .toolbar(.hidden, for: .navigationBar)
        } else if let session = model.session, model.phase == .completed {
            SummaryView(session: session) { dismiss() }
        } else if let finished = model.justCompleted {
            // The engine is already gone; the Summary runs off the finished session.
            SummaryView(session: finished) {
                model.dismissSummary()
                dismiss()
            }
        } else {
            // The session ended without anything logged (discarded).
            Color.clear.onAppear { dismiss() }
        }
    }

    /// O12: with nothing logged the only offer is to discard.
    private func requestFinish() {
        if model.loggedStepCount == 0 { showDiscardConfirm = true } else { showFinishConfirm = true }
    }
}

/// The five zones. Everything it draws comes from `WorkoutScreenModel`; it computes nothing.
private struct WorkoutScreenView: View {
    @Environment(AppModel.self) private var model
    let screen: WorkoutScreenModel
    let now: Date
    @Binding var showOverview: Bool
    @Binding var editing: Int?
    let minimize: () -> Void
    let finish: () -> Void

    @State private var repsText = ""
    @State private var weightText = ""
    @State private var loadedStep: Int?
    @FocusState private var focused: Field?
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Field { case reps, weight }

    private var session: Session? { model.session }
    private var isTimed: Bool { screen.timer != nil }

    var body: some View {
        VStack(spacing: 0) {
            header                                          // zone 1
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    exerciseBlock                           // zone 2
                    inputs                                  // zone 3
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground))
        .bottomAction {
            VStack(spacing: 12) {
                StatusStripView(strip: screen.strip)         // zone 4
                PrimaryButton(title: screen.primary.title, enabled: primaryEnabled) { primaryTapped() }
            }
        }
        .toolbar {
            // P6: the keyboard always offers a way out that isn't a guess at where to tap.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .task(id: screen.step) { load() }
        .onChange(of: screen.inputs) { _, _ in load(force: true) }
        .onChange(of: focused) { previous, _ in if previous == .weight { pushWeight() } }
    }

    // MARK: - Zone 1

    /// P6: at accessibility sizes the header reflows onto two rows rather than letting
    /// "Exercises" wrap to four lines and push the exercise off screen (O60).
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // D34 (v1.2): the stage, in words, over a bar of the whole day. v1.1 said only
            // "Exercise 2 of 5 · Set 2 of 3" in the smallest text on screen, and said nothing
            // at all when you were in a break.
            HStack(spacing: 8) {
                Text(screen.stage.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(screen.stage.isBreak ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("\(Int((screen.completion * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: screen.completion)
                .tint(screen.stage.isBreak ? Color.accentColor : Color.done)
                .accessibilityLabel("Workout progress")
                .accessibilityValue("\(Int((screen.completion * 100).rounded())) percent")
                .padding(.bottom, 2)
            HStack(spacing: 14) {
                if !typeSize.isAccessibilitySize {
                    Text(screen.elapsed)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Elapsed \(screen.elapsed)")
                    Text(screen.progress)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                // P2: reachable in every state, rest included — this row never changes.
                Button("Exercises") { showOverview = true }
                    .font(.footnote)
                    .lineLimit(1)
                    .fixedSize()
                Button { minimize() } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Minimize")
                Menu {
                    Button("Skip set") { Task { await model.apply(.skipSet(step: screen.step)) } }
                    Button("Skip exercise") {
                        Task { await model.apply(.skipExercise(exerciseIndex: screen.exerciseIndex)) }
                    }
                    // D28 (v1.1): the machine is taken. Not the same as giving up on it.
                    if model.canDefer(exerciseIndex: screen.exerciseIndex) {
                        Button("Do later") {
                            Task { await model.apply(.deferExercise(exerciseIndex: screen.exerciseIndex)) }
                        }
                    }
                    Button("Finish workout", role: .destructive) { finish() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
            .frame(minHeight: 44)
            if typeSize.isAccessibilitySize {
                Text("\(screen.elapsed) · \(screen.progress)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(screen.stage.title). Elapsed \(screen.elapsed), \(screen.progress)")
            }
        }
        .font(.footnote)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // MARK: - Zone 2

    private var exerciseBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink(value: HistoryRoute.exercise(name: screen.exerciseName,
                                                           units: session?.units ?? .kg)) {
                    Text(screen.exerciseName)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                Text(screen.targetLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(screen.spoken)
            .accessibilityHint("Opens this exercise's history")
            .accessibilityAddTraits(.isButton)

            InsetGroup {
                ForEach(screen.rows, id: \.stepIndex) { row in
                    Button { tapped(row) } label: { SetRowView(row: row) }
                        .buttonStyle(PressableRow())
                        .disabled(row.isCurrent)
                }
            }
        }
    }

    private func tapped(_ row: SetRow) {
        switch row.status {
        case .logged, .skipped: editing = row.stepIndex
        case .pending: Task { await model.apply(.jumpTo(step: row.stepIndex)) }
        }
    }

    // MARK: - Zone 3

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let timer = screen.timer {
                // A timed set takes the reps slot; the weight row below is untouched (§4.5).
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Time")
                    Text(timer.text)
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timer.accented ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Time \(timer.text)")
                    if let note = timer.minimumNote {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Reps")
                    StepperRow(text: $repsText, keyboard: .numberPad, suffix: nil, label: "Reps",
                               focus: $focused, field: .reps,
                               minus: { set(reps: InputRules.stepped(reps: InputRules.repsValue(repsText), up: false)) },
                               plus: { set(reps: InputRules.stepped(reps: InputRules.repsValue(repsText), up: true)) },
                               filter: { InputRules.reps($0, previous: $1) },
                               committed: {})
                }
            }
            if screen.inputs.showsWeight { weightRow }
        }
    }

    private var weightRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(screen.inputs.unit)
            StepperRow(text: $weightText, keyboard: .decimalPad, suffix: nil,
                       label: "Weight in \(StepCard.spokenUnit(session?.units ?? .kg))",
                       focus: $focused, field: .weight,
                       minus: { set(weight: InputRules.stepped(weight: current, by: stepSize,
                                                               up: false, increment: increment)) },
                       plus: { set(weight: InputRules.stepped(weight: current, by: stepSize,
                                                              up: true, increment: increment)) },
                       filter: { InputRules.weight($0, previous: $1) },
                       // Not on every keystroke: typing "62.5" was four engine events and,
                       // before v1.2, four writes of active-session.json. The steppers, the
                       // suggestion chip, losing focus and the primary button all push it.
                       committed: {})
            // D36: the chip says what to aim for and why, and one tap fills in both numbers.
            if let chip = screen.inputs.suggestion {
                VStack(alignment: .leading, spacing: 3) {
                    Button(chip) { applySuggestion() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.mini)
                        .disabled(screen.inputs.suggestedWeight == nil
                                  && screen.inputs.suggestedReps == nil)
                    if let reason = screen.inputs.suggestionReason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var current: Double? { InputRules.weightValue(weightText) }
    private var stepSize: Double { model.settings.weightStep(for: session?.units ?? .kg) }
    /// D35: the smallest change the equipment can make, so − and + land on a loadable weight.
    private var increment: Double { model.settings.weightIncrement(for: session?.units ?? .kg) }

    // MARK: - Zone 5

    private var primaryEnabled: Bool {
        screen.primary.kind == .log ? StepCard.canLog(repsText: repsText, isTimed: false) : true
    }

    private func primaryTapped() {
        focused = nil
        Task {
            // The engine logs a timed set with the weight it is holding, so make sure that is
            // what the field shows before finishing one. Reps sets pass `current` directly.
            if screen.inputs.showsWeight, screen.primary.kind != .log {
                await model.apply(.setWorkWeight(step: screen.step, weight: current))
            }
            switch screen.primary.kind {
            case .log:
                guard let reps = InputRules.repsValue(repsText) else { return }
                await model.apply(.logSet(step: screen.step, result: .reps(count: reps, weight: current)))
            case .startTimer:
                await model.apply(.startTimer(step: screen.step))
            case .doneTimer:
                await model.apply(.timerDone(step: screen.step))
            case .stopTimer:
                await model.apply(.stopTimer(step: screen.step))
            }
        }
    }

    // MARK: - Inputs state

    /// Loads the prefilled values once per step. An undo hands back what the set held, so the
    /// numbers you just logged come straight back rather than being recomputed (D23, O52).
    private func load(force: Bool = false) {
        guard force || loadedStep != screen.step else { return }
        loadedStep = screen.step
        if let restored = model.takeRestoredInputs() {
            repsText = restored.reps.map(String.init) ?? restored.seconds.map(String.init) ?? ""
            weightText = InputRules.weightText(restored.weight)
        } else {
            repsText = screen.inputs.reps
            weightText = screen.inputs.weight
        }
        pushWeight()
    }

    /// One tap takes the whole suggestion — reps and weight — not just the number under the
    /// finger. The suggestion is a set to aim for, so half of it is not much use.
    private func applySuggestion() {
        if let reps = screen.inputs.suggestedReps { set(reps: reps) }
        if let weight = screen.inputs.suggestedWeight { set(weight: weight) }
    }

    private func set(reps: Int) { repsText = String(reps) }
    private func set(weight: Double) { weightText = InputRules.weightText(weight); pushWeight() }

    /// The engine keeps the displayed weight so a timed set logs the same number the card shows.
    private func pushWeight() {
        Task { await model.apply(.setWorkWeight(step: screen.step, weight: current)) }
    }
}

/// Zone 4. Always drawn, at the same height, whatever it has to say (D22).
private struct StatusStripView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let strip: StatusStrip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let countdown = strip.countdown {
                    Text(countdown)
                        // A running countdown is a number you act on, so it may be large (§4.0).
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(strip.kind == .restOver ? Color.accentColor : .primary)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel(strip.kind == .restOver
                                            ? "Rest over, \(countdown) ago"
                                            : "\(countdown) of rest left")
                }
                if let title = strip.title {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if strip.showsRestControls, !typeSize.isAccessibilitySize { restControls }
            }
            // At accessibility sizes three capsules will not share a row with the countdown
            // without breaking their own labels in half (O60), so they take a row of their own.
            if strip.showsRestControls, typeSize.isAccessibilitySize { restControls }
            HStack(spacing: 12) {
                if let next = strip.next {
                    // Two lines: between exercises this row carries the finished block's
                    // sentence, advice and all, which does not fit in one.
                    Text(next)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = strip.detail {
                    // D19: a set's duration is small text, never the hero of the screen.
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if strip.undo != nil {
                    Button("Undo") { Task { await model.undoLast() } }
                        .font(.footnote.weight(.medium))
                        .accessibilityLabel("Undo the last set")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .animation(nil, value: strip.kind)
        .onChange(of: strip.kind) { _, kind in
            // VoiceOver users get no benefit from the haptic alone (O19).
            guard kind == .restOver else { return }
            AccessibilityNotification.Announcement("Rest over").post()
        }
    }

    private var restControls: some View {
        HStack(spacing: 8) {
            Button("−30") { Task { await model.apply(.adjustRest(seconds: -30)) } }
                .accessibilityLabel("Thirty seconds less rest")
            Button("+30") { Task { await model.apply(.adjustRest(seconds: 30)) } }
                .accessibilityLabel("Thirty seconds more rest")
            // The capsule stays "Skip" — three of them share a row — but VoiceOver says which
            // of the three breaks it ends, and the strip's title says it in print (§4.6).
            Button("Skip") { Task { await model.apply(.skipRest) } }
                .accessibilityLabel(strip.skipTitle)
        }
        .lineLimit(1)
        .fixedSize()
        .font(.footnote)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }
}

/// One row of the current exercise's sets (zone 2).
private struct SetRowView: View {
    let row: SetRow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(row.status == .logged ? Color.done : .secondary)
                .frame(width: 18)
            Text(row.label)
                .font(.footnote)
                .foregroundStyle(row.isCurrent ? .primary : .secondary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(row.value)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(row.isCurrent ? .primary : .secondary)
                if row.isCurrent, let last = row.lastTime {
                    Text("last \(last)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .contentShape(Rectangle())
        .background(alignment: .leading) {
            if row.isCurrent {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.10))
                    .padding(.horizontal, -8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isCurrent ? [.isSelected] : [])
    }

    private var icon: String {
        switch row.status {
        case .logged: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .pending: return row.isCurrent ? "circle.dotted" : "circle"
        }
    }
}

/// P5: the small-caps label that says what the number underneath it is.
private struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

/// − [ value ] + with the number itself as the field, so tapping it opens the right keyboard.
private struct StepperRow<Field: Hashable>: View {
    @Binding var text: String
    let keyboard: UIKeyboardType
    let suffix: String?
    let label: String
    @FocusState.Binding var focus: Field?
    let field: Field
    let minus: () -> Void
    let plus: () -> Void
    let filter: (String, String) -> String
    let committed: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            StepButton(system: "minus", action: minus)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("", text: Binding(get: { text },
                                            set: { text = filter($0, text); committed() }))
                    .keyboardType(keyboard)
                    .focused($focus, equals: field)
                    .multilineTextAlignment(.center)
                    // P6: the number keeps one size across Dynamic Type; the layout reflows
                    // around it instead of shrinking the value you are reading.
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let suffix {
                    Text(suffix).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
            .accessibilityValue(text.isEmpty ? "empty" : text)
            StepButton(system: "plus", action: plus)
        }
        .accessibilityElement(children: .contain)
    }
}

/// 44 pt targets that repeat on a long press, and never open a keyboard.
private struct StepButton: View {
    let system: String
    let action: () -> Void
    @State private var repeater: Task<Void, Never>?
    @State private var pressed = false

    var body: some View {
        Image(systemName: system)
            .font(.title3.weight(.medium))
            .frame(width: 44, height: 44)
            // O78: it responds to the finger. A control that looks identical pressed and
            // unpressed leaves you unsure whether the tap landed.
            .background(Color.secondary.opacity(pressed ? 0.30 : 0.15), in: Circle())
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .contentShape(Circle())
            .onTapGesture(perform: action)
            // `.infinity` so the gesture never "recognises": `pressing(false)` then means only
            // "the finger came off", instead of firing at 0.4 s and cancelling the repeater at
            // the very moment its own 400 ms delay ended (v1.2).
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                pressed = pressing
                repeater?.cancel()
                guard pressing else { return }
                repeater = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    while !Task.isCancelled {
                        action()
                        try? await Task.sleep(for: .milliseconds(80))
                    }
                }
            }, perform: {})
            .accessibilityLabel(system == "minus" ? "Decrease" : "Increase")
            .accessibilityAddTraits(.isButton)
    }
}
