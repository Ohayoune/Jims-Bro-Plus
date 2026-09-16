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
    /// D81 (v1.10): the logged set a tapped dot is changing, in place. Never stored.
    @State private var editing: Int?
    /// D42 (v1.3): the exercise Change exercise was opened for.
    @State private var changing: ChangeTarget?

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
        .sheet(item: $changing) { target in
            ChangeExerciseSheet(exerciseIndex: target.exerciseIndex, currentName: target.name,
                                units: model.session?.units ?? model.displayUnits)
                .environment(model)
        }
        .task {
            #if DEBUG
            // Debug-only: open the overview directly for screenshot runs.
            if ProcessInfo.processInfo.arguments.contains("-uiOverview") {
                try? await Task.sleep(for: .milliseconds(600))
                showOverview = true
            }
            // Debug-only (v1.3): open Change exercise on the current exercise.
            if ProcessInfo.processInfo.arguments.contains("-uiChangeExercise") {
                try? await Task.sleep(for: .milliseconds(600))
                let step: Int?
                switch model.phase {
                case let .working(index)?: step = index
                case let .resting(rest)?: step = rest.nextStep
                default: step = nil
                }
                if let session = model.session, let step,
                   let exercise = session.exercises[safe: session.steps[step].exerciseIndex] {
                    changing = ChangeTarget(exerciseIndex: session.steps[step].exerciseIndex, name: exercise.name)
                }
            }
            // Debug-only (v1.10, D81): change the last logged set in place, as a tapped dot does.
            if ProcessInfo.processInfo.arguments.contains("-uiEditSet") {
                try? await Task.sleep(for: .milliseconds(600))
                editing = model.engine?.active.lastCompletedStep
            }
            #endif
        }
        // D56 (v1.6): alerts, not confirmation dialogs. Presented from the ··· menu, a dialog
        // draws as a popover on iOS 26 and drops its cancel-role button, so "14 sets not done.
        // Finish anyway?" showed one red button and no visible way to say no. An alert always
        // shows both — and Finish is not destructive: it saves. Only Discard is.
        .alert(finishPrompt, isPresented: $showFinishConfirm) {
            Button("Finish workout") { Task { await model.finish() } }
            Button("Keep going", role: .cancel) {}
        }
        .alert("Nothing was logged. Discard this workout?", isPresented: $showDiscardConfirm) {
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
                                            settings: model.settings, editing: editing,
                                            walk: model.engine?.walk) {
            WorkoutScreenView(screen: screen,
                              dayColour: DayColour.of(session: active.session, plans: model.plans),
                              now: now, showOverview: $showOverview,
                              editing: $editing, minimize: { dismiss() }, finish: requestFinish,
                              changeExercise: { changing = ChangeTarget(exerciseIndex: $0, name: $1) })
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

/// D42: which exercise the Change exercise sheet is about, captured when the menu is tapped
/// so the sheet is not chasing a step that moved while it was open.
private struct ChangeTarget: Identifiable {
    var exerciseIndex: Int
    var name: String
    var id: Int { exerciseIndex }
}

/// The five zones. Everything it draws comes from `WorkoutScreenModel`; it computes nothing.
private struct WorkoutScreenView: View {
    @Environment(AppModel.self) private var model
    let screen: WorkoutScreenModel
    /// D65 (v1.7): the day's colour, for the square that leads the header. Nil when the day is
    /// in no plan.
    let dayColour: DayColour?
    let now: Date
    @Binding var showOverview: Bool
    @Binding var editing: Int?
    let minimize: () -> Void
    let finish: () -> Void
    /// D42 (v1.3): opens Change exercise for (exercise index, its current name).
    let changeExercise: (Int, String) -> Void

    @State private var repsText = ""
    @State private var weightText = ""
    @State private var loadedStep: Int?
    @FocusState private var focused: Field?

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
                // D56 (v1.6): while a field is focused the strip's trailing slot holds Done. The
                // system keyboard toolbar drew it as a floating pill over the lower half of
                // Log set on iOS 26, and a tap there did nothing.
                StatusStripView(strip: screen.strip,          // zone 4
                                done: focused != nil ? { focused = nil } : nil)
                PrimaryButton(title: screen.primary.title, enabled: primaryEnabled, ink: true) { primaryTapped() }
            }
        }
        // D79 (v1.10, §6.52): blue is reserved on this screen — it says *now* and nothing else —
        // so every control that would take the accent takes ink. The marks that are the current
        // set name the accent themselves.
        .tint(.primary)
        .task(id: screen.step) { load() }
        .onChange(of: screen.inputs) { _, _ in load(force: true) }
        .onChange(of: focused) { previous, _ in if previous == .weight { pushWeight() } }
        // A set that stops being one to change — undone, say — ends the change with it.
        .onChange(of: screen.editing) { _, now in if now == nil { editing = nil } }
    }

    // MARK: - Zone 1

    /// D80 (v1.10, §6.53): the header is the bar. The day's square, the bar with its caret and
    /// the elapsed time under its right end make one 44 pt target that opens the Overview — the
    /// Exercises button's job — then ⌄ and ···. No words on it: VoiceOver hears the stage.
    /// *(v1.2–v1.9: the stage in words, a percentage, the bar, elapsed · progress and
    /// Exercises, D34.)*
    private var header: some View {
        HStack(alignment: .barMiddle, spacing: 4) {
            Button { showOverview = true } label: {
                HStack(alignment: .top, spacing: 10) {
                    // D65 (v1.7): the header's one mark of which day it is, level with the bar.
                    if let dayColour { DaySquare(colour: dayColour).frame(height: BarView.center * 2) }
                    VStack(alignment: .trailing, spacing: 0) {
                        BarView(bar: screen.bar, day: dayColour)
                            .frame(height: BarView.height)
                        Text(screen.elapsed)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, BarView.inset)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // ⌄ and ··· centre on the bar's track, not on the bar and the time beneath it.
            .alignmentGuide(.barMiddle) { _ in BarView.inset + BarView.center }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(screen.spokenHeader)
            .accessibilityValue("\(Int((screen.completion * 100).rounded())) percent, elapsed \(screen.elapsed)")
            .accessibilityHint("Opens the overview")
            .accessibilityAddTraits(.isButton)
            Button { minimize() } label: {
                Image(systemName: "chevron.down").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .foregroundStyle(.secondary)
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
                // D42 (v1.3): the machine is taken and you want to do something now.
                if model.canSubstitute(exerciseIndex: screen.exerciseIndex) {
                    Button("Change exercise") {
                        changeExercise(screen.exerciseIndex, screen.exerciseName)
                    }
                }
                // D56 (v1.6): not destructive — it saves the workout. Red read as "delete".
                Button("Finish workout") { finish() }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("More")
        }
        .font(.body)
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.top, 2)
    }

    // MARK: - Zone 2

    /// D81 (v1.10, §6.54): the exercise in symbols. The name with its dot, the ? when there is
    /// something behind it, a dot per set, and the one card. No sentence: the target line went
    /// into the card and behind the ?, the rows into the dots. *(v1.1–v1.9: the name, a target
    /// line and a row per set.)*
    private var exerciseBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                NavigationLink(value: HistoryRoute.exercise(name: screen.exerciseName,
                                                           units: session?.units ?? .kg)) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(screen.exerciseMark == .todo ? DotView.grey : screen.exerciseMark.color(day: dayColour))
                            .frame(width: 12, height: 12)
                        Text(screen.exerciseName)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(screen.spoken)
                .accessibilityHint("Opens this exercise's history")
                .accessibilityAddTraits(.isButton)
                Spacer(minLength: 0)
                if let notes = screen.notes { NotesButton(notes: notes) }
            }
            .frame(minHeight: 44)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { dots }
                WrapLayout(spacing: 0, lineSpacing: 0) { dots }
            }
            .frame(maxWidth: .infinity)

            SetCardView(card: screen.card.showing(field: InputRules.repsValue(repsText)), day: dayColour)
        }
    }

    /// 18 pt dots 10 pt apart, each in a 28 × 44 pt target.
    private var dots: some View {
        ForEach(screen.dots, id: \.step) { dot in
            Button { tapped(dot) } label: {
                DotView(dot: dot, day: dayColour, selected: dot.step == screen.editing)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dot.spoken)
            .accessibilityHint(dot.state == .done ? "Change this set" : dot.state == .todo ? "Do this set now" : "")
            .accessibilityAddTraits(dot.step == screen.editing || (screen.editing == nil && dot.state == .now) ? [.isSelected] : [])
        }
    }

    /// A filled dot changes that set in place; a grey one, slashed or not, is done now (`jumpTo`);
    /// the blue one is the set already on — while changing another, it comes back to it.
    private func tapped(_ dot: SetDot) {
        switch dot.state {
        case .done: editing = dot.step
        case .now: editing = nil
        case .todo:
            editing = nil
            Task { await model.apply(.jumpTo(step: dot.step)) }
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
            } else if screen.inputs.seconds {
                // D81: a logged hold being changed takes its seconds in a field, five at a tap —
                // a cell's worth.
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Seconds")
                    StepperRow(text: $repsText, keyboard: .numberPad, suffix: nil, label: "Seconds",
                               focus: $focused, field: .reps,
                               minus: { set(reps: InputRules.stepped(seconds: InputRules.secondsValue(repsText),
                                                                     by: RepCells.secondsPerCell, up: false)) },
                               plus: { set(reps: InputRules.stepped(seconds: InputRules.secondsValue(repsText),
                                                                    by: RepCells.secondsPerCell, up: true)) },
                               filter: { InputRules.seconds($0, previous: $1) },
                               committed: {})
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
                       placeholder: "tap to type",
                       // Not on every keystroke: typing "62.5" was four engine events and,
                       // before v1.2, four writes of active-session.json. The steppers, the
                       // suggestion chip, losing focus and the primary button all push it.
                       committed: {})
            // D57 (v1.6): the first empty weight says why it is empty, until it is not.
            if let hint = screen.inputs.weightHint, weightText.isEmpty {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        switch screen.primary.kind {
        case .log, .save: return StepCard.canLog(repsText: repsText, isTimed: false)
        case .startTimer, .doneTimer, .stopTimer, .startSet: return true
        }
    }

    private func primaryTapped() {
        focused = nil
        Task {
            // The engine logs a timed set with the weight it is holding, so make sure that is
            // what the field shows before finishing one. Reps sets pass `current` directly.
            if screen.inputs.showsWeight, screen.primary.kind != .log, screen.primary.kind != .save {
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
            case .startSet:
                // D57 (v1.6): the warm-up ends and the first set's card is live.
                await model.apply(.skipRest)
            case .save:
                // D81 (v1.10): the Overview's edit sheet, made inline; then back to the set that is on.
                guard let step = screen.editing, let value = InputRules.repsValue(repsText) else { return }
                let result: SetResult = screen.inputs.seconds ? .duration(seconds: value, weight: current)
                                                              : .reps(count: value, weight: current)
                await model.apply(.editSet(step: step, result: result))
                editing = nil
            }
        }
    }

    // MARK: - Inputs state

    /// Loads the prefilled values once per step. An undo hands back what the set held, so the
    /// numbers you just logged come straight back rather than being recomputed (D23, O52).
    private func load(force: Bool = false) {
        guard force || loadedStep != screen.step else { return }
        loadedStep = screen.step
        if screen.editing == nil, let restored = model.takeRestoredInputs() {
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
        // A set being changed holds its own weight; the set that is on keeps the one it had.
        guard screen.editing == nil else { return }
        Task { await model.apply(.setWorkWeight(step: screen.step, weight: current)) }
    }
}

/// Zone 4. Always drawn, at the same height, whatever it has to say (D22).
private struct StatusStripView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let strip: StatusStrip
    /// D56 (v1.6): set while a field is focused; the trailing slot then holds Done.
    var done: (() -> Void)? = nil
    /// D82 (v1.10): the ring's one sentence, open.
    @State private var explaining = false

    var body: some View {
        if let ring = strip.ring { walk(ring) } else { rest }
    }

    /// D82 (v1.10, §6.55): between exercises the strip changes shape, and only then — the ring at
    /// its left, the count-up large beside it, and under the figure the walk to the next
    /// exercise, whose dot is blue because it is the one on. No −30 / +30 / Skip.
    private func walk(_ ring: WalkRing) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button { explaining = true } label: { WalkRingView(ring: ring) }
                .buttonStyle(.plain)
                .popover(isPresented: $explaining, arrowEdge: .bottom) {
                    Text(ring.explanation)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 260, alignment: .leading)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
                .accessibilityLabel(ring.full ? "Ready" : "The minimum between exercises")
                .accessibilityHint(ring.explanation)
            VStack(alignment: .leading, spacing: 5) {
                if let countdown = strip.countdown {
                    Text(countdown)
                        // Full, the count-up steps back: it only says how long you have stood there.
                        .font(.system(size: ring.full ? 28 : 36, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ring.full ? Color.secondary : Color.primary)
                        .contentTransition(.numericText(countsDown: false))
                }
                if let next = strip.next, !typeSize.isAccessibilitySize {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                        Circle().fill(MarkState.now.color(day: nil)).frame(width: 10, height: 10)
                        Text(next).lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strip.spoken ?? "")
            Spacer(minLength: 0)
            if let done {
                doneButton(done)
            } else if strip.undo != nil {
                undoButton
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .onChange(of: ring.full) { _, full in
            guard full else { return }
            AccessibilityNotification.Announcement("Ready for the next exercise").post()
        }
    }

    private func doneButton(_ action: @escaping () -> Void) -> some View {
        Button("Done", action: action)
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityHint("Closes the keyboard")
    }

    private var undoButton: some View {
        Button { Task { await model.undoLast() } } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .font(.footnote.weight(.medium))
        .accessibilityLabel("Undo the last set")
    }

    private var rest: some View {
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
                if let done {
                    doneButton(done)
                } else if strip.showsRestControls, !typeSize.isAccessibilitySize { restControls }
            }
            // At accessibility sizes three capsules will not share a row with the countdown
            // without breaking their own labels in half (O60), so they take a row of their own.
            if strip.showsRestControls, typeSize.isAccessibilitySize, done == nil { restControls }
            HStack(spacing: 12) {
                // D56 (v1.6): at accessibility sizes the next-set line goes, so the inputs stay
                // on screen with the button; the card above already names the exercise.
                if let next = strip.next, !typeSize.isAccessibilitySize {
                    // Two lines: between exercises this row carries the finished block's
                    // sentence, advice and all, which does not fit in one.
                    Text(next)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = strip.detail, !typeSize.isAccessibilitySize {
                    // D19: a set's duration is small text, never the hero of the screen.
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                // D81 (v1.10): Undo is the strip's again, at every size, while the rest the set
                // started runs — the rows that carried it since D59 are dots now.
                if strip.undo != nil { undoButton }
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

/// D82 (v1.10, §6.55): the walk's ring, 58 pt — a track in the system's fill, the arc from the
/// top clockwise over the minimum in Core's red → amber → green, and full, a green disc with a
/// white check. The colour is `WalkRing.colour`; this only draws it.
private struct WalkRingView: View {
    let ring: WalkRing

    var body: some View {
        let rgb = ring.colour
        let colour = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 5.5)
            Circle()
                .trim(from: 0, to: ring.fraction)
                .stroke(colour, style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if ring.full {
                Circle().fill(colour)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(2.75)
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .animation(.linear(duration: 1), value: ring.fraction)
    }
}

/// D81 (v1.10, §6.54): one set as a dot, 18 pt — filled in the day's colour when done, a blue
/// ring round a blue centre for now, a grey ring ahead, slashed when skipped. A ring in ink
/// around it while its set is being changed.
private struct DotView: View {
    let dot: SetDot
    let day: DayColour?
    let selected: Bool

    /// Not yet's grey as a stroke. `secondarySystemFill` all but vanishes as a 2 pt ring, as it
    /// did as the rows' icon; the mock's grey is the system's third.
    static let grey = Color(.systemGray3)

    var body: some View {
        ZStack {
            switch dot.state {
            case .done:
                Circle().fill(dot.state.color(day: day))
            case .now:
                Circle().strokeBorder(Color.accentColor, lineWidth: 2.5)
                Circle().fill(Color.accentColor).padding(5)
            case .todo:
                Circle().strokeBorder(Self.grey, lineWidth: 2)
                if dot.skipped {
                    Path { path in
                        path.move(to: CGPoint(x: 4, y: 14))
                        path.addLine(to: CGPoint(x: 14, y: 4))
                    }
                    .stroke(Self.grey, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            if selected {
                Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-5)
            }
        }
        .frame(width: 18, height: 18)
    }
}

/// D81 (v1.10, §6.54): the one card — the range and the weight at the left, the cells at the
/// right in the card's state. White on the ground, the one shadow on the page.
private struct SetCardView: View {
    let card: SetCard
    let day: DayColour?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.range)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                if let unit = card.unit {
                    Text(unit).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                if let weight = card.weight {
                    Text(weight).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
            WrapLayout(spacing: 3.5, lineSpacing: 2) {
                ForEach(Array(card.cells.cells.enumerated()), id: \.offset) { i, cell in
                    CellView(cell: cell, colour: colour)
                        // A gap after every fifth, so 12–15 counts at a glance.
                        .padding(.trailing, card.cells.cells.indices.contains(i + 1)
                                 && card.cells.cells[i + 1].group != cell.group ? 3 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.10), radius: 11, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([card.range, card.unit, card.weight].compactMap { $0 }.joined(separator: " "))
    }

    private var colour: Color {
        card.colour == .todo ? DotView.grey : card.colour.color(day: day)
    }
}

/// One rep: 8 × 22 pt, the line above it last time's, the caret beneath it the field's.
private struct CellView: View {
    let cell: RepCells.Cell
    let colour: Color

    var body: some View {
        VStack(spacing: 3.5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(cell.last ? Color.primary : .clear)
                .frame(height: 2.5)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(fill)
                .frame(height: 22)
            Path { path in
                path.move(to: CGPoint(x: 4, y: 0))
                path.addLine(to: CGPoint(x: 8, y: 5))
                path.addLine(to: CGPoint(x: 0, y: 5))
                path.closeSubpath()
            }
            .fill(cell.caret ? Color.primary : .clear)
            .frame(height: 5)
        }
        .frame(width: 8)
    }

    /// Solid, or the colour at 24 % — yellow past the top of the range, at 30 % when faint.
    private var fill: Color {
        switch (cell.fill, cell.over) {
        case (.solid, false): return colour
        case (.faint, false): return colour.opacity(0.24)
        case (.solid, true): return .yellow
        case (.faint, true): return Color.yellow.opacity(0.30)
        }
    }
}

/// D81 (v1.10): the ?, a 24 pt circle in the secondary colour, and what is behind it.
private struct NotesButton: View {
    let notes: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 24, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Notes")
        .popover(isPresented: $open) {
            Text(notes)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
                .padding(16)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private extension VerticalAlignment {
    /// The middle of the bar's track, so the header's glyphs line up with the bar.
    enum BarMiddle: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    static let barMiddle = VerticalAlignment(BarMiddle.self)
}

/// D80 (v1.10, §6.53): the whole day as one shape — a segment per block with a 3 pt gap between,
/// a mark per set inside each in its state's colour (D79) cut apart by a tick, and a caret under
/// the segment being looked at. One `Canvas`, no view per set: a sixteen-set day is one draw.
private struct BarView: View {
    let bar: WorkoutBar
    let day: DayColour?

    /// The track's middle, from the top — the day's square is centred on it.
    static let center: CGFloat = 5
    /// The space above the bar inside the header's target.
    static let inset: CGFloat = 4
    static let height: CGFloat = 16
    private static let track: CGFloat = 6
    private static let gap: CGFloat = 3
    private static let tick: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let total = bar.segments.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return }
            let usable = size.width - Self.gap * CGFloat(max(bar.segments.count - 1, 0))
            let top = Self.center - Self.track / 2
            var x: CGFloat = 0
            for segment in bar.segments {
                let width = max(0, usable * segment.weight / total)
                let rect = CGRect(x: x, y: top, width: width, height: Self.track)
                context.drawLayer { layer in
                    layer.clip(to: Path(roundedRect: rect, cornerRadius: Self.track / 2))
                    let each = width / CGFloat(max(segment.sets.count, 1))
                    for (i, state) in segment.sets.enumerated() {
                        let mark = CGRect(x: x + each * CGFloat(i), y: top, width: each, height: Self.track)
                        layer.fill(Path(mark), with: .color(state.color(day: day)))
                    }
                    // The ticks are cuts, so they read on a done set, the blue one and the track.
                    layer.blendMode = .destinationOut
                    for i in stride(from: 1, to: segment.sets.count, by: 1) {
                        let cut = CGRect(x: x + each * CGFloat(i) - Self.tick / 2, y: top,
                                         width: Self.tick, height: Self.track)
                        layer.fill(Path(cut), with: .color(.black))
                    }
                }
                if segment.caret {
                    var caret = Path()
                    let mid = x + width / 2
                    caret.move(to: CGPoint(x: mid, y: top + Self.track + 3))
                    caret.addLine(to: CGPoint(x: mid + 4, y: size.height))
                    caret.addLine(to: CGPoint(x: mid - 4, y: size.height))
                    caret.closeSubpath()
                    context.fill(caret, with: .color(.primary))
                }
                x += width + Self.gap
            }
        }
        .accessibilityHidden(true)
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
    /// D56 (v1.6): what an empty field says about itself. A built-in plan's first set has no
    /// weight, and a blank gap between − and + said nothing about being a field.
    var placeholder: String? = nil
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
            .overlay {
                // Not while typing: the caret would sit in the middle of the words.
                if text.isEmpty, let placeholder, focus != field {
                    Text(placeholder)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .padding(.vertical, 4)
            .background {
                if text.isEmpty, placeholder != nil {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                }
            }
            .accessibilityLabel(label)
            .accessibilityValue(text.isEmpty ? "empty" : text)
            .accessibilityHint(text.isEmpty && placeholder != nil ? "Double tap to type a weight" : "")
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
