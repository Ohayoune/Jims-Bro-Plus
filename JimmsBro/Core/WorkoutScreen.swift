import Foundation

/// SPEC §4.5's five zones (D22), in the one order they ever appear in. `WorkoutScreen.model`
/// returns all five for every state, so "the zones never move" is a property a test can check
/// rather than a promise the view layer has to keep on its own.
enum WorkoutZone: String, Equatable, Sendable, CaseIterable {
    case header, exercise, inputs, strip, primary
}

/// SPEC §6.15 (D34, v1.2): which stage of the workout you are in, said in words, plus how far
/// through the day you are. The owner's note was "it should be a bit more clear what stage of
/// the workout you're on"; v1.1 said only "Exercise 2 of 5 · Set 2 of 3" in the smallest text
/// on the screen, and said nothing at all about being in a break.
enum WorkoutStage: Equatable {
    case warmUp
    case working(exercise: Int, exercises: Int, set: Int, sets: Int)
    case resting
    case betweenExercises
    case done

    /// "Warm-up", "Exercise 2 of 5 · Set 2 of 3", "Resting", "Between exercises".
    var title: String {
        switch self {
        case .warmUp: return RestKind.warmUp.title
        case let .working(exercise, exercises, set, sets):
            return "Exercise \(exercise) of \(exercises) · Set \(set) of \(sets)"
        case .resting: return "Resting"
        case .betweenExercises: return RestKind.betweenExercises.title
        case .done: return "Done"
        }
    }

    /// Whether this stage is a break of some kind, so the header can say so at a glance.
    var isBreak: Bool {
        switch self {
        case .warmUp, .resting, .betweenExercises: return true
        case .working, .done: return false
        }
    }

    static func current(active: ActiveSession, step index: Int) -> WorkoutStage {
        switch active.phase {
        case .completed:
            return .done
        case let .resting(rest):
            switch rest.kind {
            case .warmUp: return .warmUp
            case .betweenSets: return .resting
            case .betweenExercises: return .betweenExercises
            }
        case .working:
            // A block that just ended without a countdown is still "between exercises": the
            // next card is up, but you are walking, not lifting.
            if active.blockDone != nil { return .betweenExercises }
            let session = active.session
            guard let step = session.steps[safe: index],
                  let exercise = session.exercises[safe: step.exerciseIndex] else { return .done }
            // Counted over the exercises as the day now runs them, so "Do later" (D28) moves an
            // exercise's number with it rather than leaving a gap, and a substitute (D42) keeps
            // the number of the exercise it stood in for.
            let order = SessionBlocks.exerciseOrder(session)
            let position = (order.firstIndex(of: SessionBlocks.canonical(session, step.exerciseIndex)) ?? 0) + 1
            return .working(exercise: position, exercises: max(order.count, position),
                            set: step.setIndex + 1,
                            sets: max(exercise.targets.count, step.setIndex + 1))
        }
    }

    /// How far through the day, 0…1: steps logged or skipped over steps in total. It counts
    /// sets, not exercises, so a long exercise moves the bar rather than sitting still.
    static func progress(_ session: Session) -> Double {
        guard !session.steps.isEmpty else { return 0 }
        let done = session.steps.filter { $0.status != .pending }.count
        return Double(done) / Double(session.steps.count)
    }
}

/// Zone 3 when the work is timed: the countdown or stopwatch that takes the reps row's place.
struct TimerDisplay: Equatable {
    var text: String
    /// Past the warning point of a fixed set, or past an open set's minimum.
    var accented: Bool
    var running: Bool
    /// "30+ s" under a not-yet-started open set that has a minimum.
    var minimumNote: String?
}

/// Zone 4 (SPEC §4.6, §4.7). Always present; every field may be nil, which renders as a blank
/// strip of the same height rather than as a zone that disappeared.
struct StatusStrip: Equatable {
    enum Kind: String, Equatable { case empty, resting, restOver, blockDone, timed }
    var kind: Kind = .empty
    /// "Rest over", the block-done line, or a timed set's threshold note.
    var title: String?
    /// "2:26" while resting, "+0:12" once it has run out.
    var countdown: String?
    /// "Next: Bench Press · set 2 of 3 · 8–12 · 60 kg" during rest.
    var next: String?
    /// Small text only (D19): "set 0:34", "moving on · 0:42".
    var detail: String?
    /// −30 s / +30 s / Skip rest belong to the rest states only.
    var showsRestControls = false
    /// "Set logged · Undo" while D23's undo is still valid.
    var undo: String?
    /// v1.2: which break is running, so the view can say so without inspecting the phase.
    var restKind: RestKind?
    /// "Skip rest", "Skip warm-up", "Skip" — the button names what it ends.
    var skipTitle: String = RestKind.betweenSets.skipTitle
    /// D82 (v1.10): which way `countdown` runs — down for a rest, up for the walk.
    var direction: TimerDirection = .down
    /// D82 (v1.10, §6.55): the walk between exercises' ring; nil in every other state.
    var ring: WalkRing?
    /// What VoiceOver hears for the walk, whose print is a ring, a figure and a name.
    var spoken: String?
}

enum TimerDirection: String, Equatable { case up, down }

/// D82 (v1.10, §6.55): the ring beside the walk's count-up. It fills clockwise over the walk's
/// minimum — the plan's `restBetweenExercises`, then the setting — turning red, amber, green,
/// and when full it is a green disc with a check. A minimum of zero is full from the start.
struct WalkRing: Equatable {
    /// 0…1 of the minimum, never past 1.
    var fraction: Double
    var minimum: Int
    /// Whether the plan declared the minimum, or the setting stood in (§6.3).
    var fromPlan: Bool
    var full: Bool { fraction >= 1 }
    /// Tap the ring: one sentence (`RestText.ringExplanation`).
    var explanation: String { RestText.ringExplanation(minimum: minimum, fromPlan: fromPlan) }
    /// The ring's colour at its fraction — the view draws it, Core decides it.
    var colour: RGB { WalkRing.colour(fraction: fraction) }

    struct RGB: Equatable { var red: Double; var green: Double; var blue: Double }
    static let red = RGB(red: 1, green: 59 / 255, blue: 48 / 255)          // #FF3B30
    static let amber = RGB(red: 1, green: 159 / 255, blue: 10 / 255)       // #FF9F0A
    static let green = RGB(red: 52 / 255, green: 199 / 255, blue: 89 / 255) // #34C759

    /// Red to amber over the first half, amber to green over the second; green when full.
    static func colour(fraction: Double) -> RGB {
        let f = min(1, max(0, fraction))
        func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
            RGB(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t,
                blue: a.blue + (b.blue - a.blue) * t)
        }
        guard f < 1 else { return green }
        return f < 0.5 ? mix(red, amber, f * 2) : mix(amber, green, (f - 0.5) * 2)
    }

    static func of(startedAt: Date, minimum: Int, fromPlan: Bool, now: Date) -> WalkRing {
        let fraction = minimum > 0 ? now.timeIntervalSince(startedAt) / Double(minimum) : 1
        return WalkRing(fraction: min(1, max(0, fraction)), minimum: max(0, minimum), fromPlan: fromPlan)
    }
}

/// The rest's own sentences, in Core so a test can pin them (Y13's rule).
enum RestText {
    /// D82: what a tap on the ring says. It names where the minimum came from, because the
    /// plan's and the setting's are different promises (D55: nothing untrue).
    static func ringExplanation(minimum: Int, fromPlan: Bool) -> String {
        guard minimum > 0 else {
            return "No minimum between exercises. The ring starts full — go when you're ready."
        }
        let whose = fromPlan ? "Your plan's minimum" : "Your minimum in Settings"
        return "At least \(TargetText.time(minimum)) between exercises. \(whose) — when the ring is full, you're ready."
    }
}

/// Zone 5. One control, one slot, whatever the work is (D20, D22).
struct PrimaryAction: Equatable {
    /// `save` (D81, v1.10): a logged set being changed in place, which `.editSet` applies.
    enum Kind: String, Equatable { case log, startTimer, doneTimer, stopTimer, startSet, save }
    var title: String
    var kind: Kind
}

/// What zone 3 starts out holding, so the view neither runs prefill nor formats numbers.
struct InputDefaults: Equatable {
    var reps: String = ""
    var weight: String = ""
    var showsWeight = false
    var unit: String = ""
    /// D36 (v1.2): "Try 8 × 82.5 kg", the reason under it, and the numbers behind both.
    var suggestion: String?
    var suggestionReason: String?
    var suggestedWeight: Double?
    var suggestedReps: Int?
    /// D57 (v1.6): why the weight field is empty, said under it until it is not. A built-in
    /// plan's first set has no weight and no history; the sentence used to live in a note
    /// that truncated after two lines.
    var weightHint: String?
    /// D81 (v1.10): the first field holds seconds, not reps — a logged hold being changed.
    var seconds = false
}

/// D81 (v1.10, §6.54): one dot per step of the exercise's block, in order — a drop and a superset
/// member's set are steps too. Its state is D79's; a skipped step is not yet, with a slash.
struct SetDot: Equatable {
    var step: Int
    var state: MarkState
    var skipped: Bool
    /// What VoiceOver hears: "Set 2 of 3, done".
    var spoken: String
}

/// D81 (v1.10, §6.54): zone 2's one card — the set the dots point at. Its range and weight at the
/// left, its cells at the right in the colour of its state: now for the current set, done for a
/// logged set being changed, not yet for one looked at ahead (P4).
struct SetCard: Equatable {
    /// "8–10", "8" for a range of one, "8+" with no top, "max" with neither.
    var range: String
    /// "sec" under a timed set's range; nil for reps.
    var unit: String?
    /// "26 kg" — what the set asks, not what the field holds. Nil when it names none.
    var weight: String?
    var cells: RepCells
    var colour: MarkState
    /// What the cells are drawn from, so they follow the number in the field.
    var bounds: RepCells.Bounds
    var timed: Bool
    /// Reps, or seconds for a timed set, that this set reached last time.
    var lastTime: Int?

    /// The card with its cells drawn for the number in the field: the caret moves on the current
    /// set, the solid cells on a set being changed. A hold waiting to start has no field, so its
    /// cells stay.
    func showing(field: Int?) -> SetCard {
        var card = self
        switch (colour, timed) {
        case (.now, false): card.cells = .target(bounds, reps: field, lastTime: lastTime)
        case (.todo, false): card.cells = .target(bounds, reps: nil, lastTime: lastTime)
        case (.now, true), (.todo, true): card.cells = .timed(bounds, seconds: nil, lastTime: lastTime)
        case (.done, false): card.cells = .logged(bounds, result: field ?? 0, lastTime: lastTime)
        case (.done, true): card.cells = .timed(bounds, seconds: field ?? 0, logged: true, lastTime: lastTime)
        }
        return card
    }

    static func of(session: Session, step index: Int, history: [Session], colour: MarkState,
                   field: Int?) -> SetCard? {
        guard let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex],
              let target = session.target(at: index) else { return nil }
        let timed = target.work.isTimed
        let bounds = RepCells.Bounds.of(target.work, range: step.dropIndex == 0 ? exercise.repRange : nil)
        let last = Prefill.historicalResult(session: session, step: index, history: history)
        let card = SetCard(range: range(bounds), unit: timed ? "sec" : nil,
                           weight: target.weight.map { "\(TargetText.number($0)) \(session.units.rawValue)" },
                           cells: RepCells(cells: []), colour: colour, bounds: bounds, timed: timed,
                           lastTime: timed ? last?.seconds : last?.reps)
        return card.showing(field: field)
    }

    static func range(_ bounds: RepCells.Bounds) -> String {
        guard let top = bounds.maximum else { return bounds.minimum > 0 ? "\(bounds.minimum)+" : "max" }
        return top == bounds.minimum ? "\(top)" : "\(bounds.minimum)–\(top)"
    }
}

/// The workout's own sentences, in Core so a test can pin them (Y13's rule).
enum WorkoutText {
    static let weightHint = "Type the weight you lift. The app remembers it from then on."
}

/// The whole workout screen as data. Views render it; they compute nothing.
struct WorkoutScreenModel: Equatable {
    var zones: [WorkoutZone]
    var step: Int
    var exerciseIndex: Int
    /// D34 (v1.2): which stage the workout is in, and how far through the day it is. Since
    /// v1.10 (D80, §6.53) the screen prints neither: the stage is spoken (`spokenHeader`) and
    /// the day is the bar. Both stay for the Lock Screen and the tests.
    var stage: WorkoutStage
    var completion: Double
    var elapsed: String
    var progress: String
    /// D80 (v1.10, §6.53): zone 1 — a segment per block, a mark per set, the caret.
    var bar: WorkoutBar
    var exerciseName: String
    /// D81 (v1.10, §6.54): zone 2 in symbols. The exercise's dot in its state; the ?'s text, nil
    /// when there is nothing behind it; a dot per step of the block; and the one card.
    /// *(v1.1–v1.9: a target line and a row per set.)*
    var exerciseMark: MarkState
    var notes: String?
    var dots: [SetDot]
    var card: SetCard
    /// The logged step being changed in place, from a tapped dot — the view's, never stored.
    var editing: Int?
    var inputs: InputDefaults
    var timer: TimerDisplay?
    var strip: StatusStrip
    var primary: PrimaryAction
    /// The one VoiceOver string for the exercise block (SPEC §9).
    var spoken: String

    /// D59 (v1.6): the last logged or skipped step, while D23's undo is still valid. Since v1.10
    /// (D81) the rows that carried Undo are gone and the strip says it, during the rest after.
    var undoStep: Int?

    /// D56 (v1.6): the small line under the stage, or nil when it would only repeat it. While
    /// working, the stage already reads "Exercise 1 of 5 · Set 1 of 4"; the audit found it
    /// printed twice, one above the other. Resting, and a superset member's "A · round 2 of 3",
    /// still have something of their own to say.
    var progressLine: String? { progress == stage.title ? nil : progress }

    /// D80 (v1.10): what VoiceOver hears for the header. The stage in words, exactly as D34
    /// wrote it, and printed nowhere on the screen.
    var spokenHeader: String { stage.title }
}

enum WorkoutScreen {
    /// Nil only when the session is over — the Summary owns the screen then. `editing` is the
    /// dot the view has tapped; a step that is not a logged one of this block is ignored.
    /// `walk` is the engine's (D82): the walk's minimum and whether the plan declared it.
    static func model(active: ActiveSession, history: [Session], now: Date,
                      settings: Settings = Settings(), editing: Int? = nil,
                      walk: (minimum: Int, fromPlan: Bool)? = nil) -> WorkoutScreenModel? {
        let session = active.session
        let index: Int
        switch active.phase {
        case let .working(step): index = step
        case let .resting(rest): index = rest.nextStep
        case .completed: return nil
        }
        guard let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex],
              let target = session.target(at: index) else { return nil }

        let values = Prefill.values(session: session, step: index, history: history,
                                    settings: settings)
        let timed = target.work.isTimed
        let restKind: RestKind?
        if case let .resting(rest) = active.phase { restKind = rest.kind } else { restKind = nil }
        let block = session.steps.indices.filter { session.steps[$0].blockIndex == step.blockIndex }
        let edited = editing.flatMap { e -> (step: Int, result: SetResult)? in
            guard block.contains(e), session.steps[e].status == .logged,
                  let result = session.steps[e].result else { return nil }
            return (e, result)
        }
        var defaults = inputs(values: values, target: target, units: session.units)
        if let edited, let editedExercise = session.exercises[safe: session.steps[edited.step].exerciseIndex] {
            defaults = InputDefaults(reps: (edited.result.reps ?? edited.result.seconds).map(String.init) ?? "",
                                   weight: InputRules.weightText(edited.result.weight),
                                   showsWeight: !editedExercise.bodyweight || edited.result.weight != nil,
                                   unit: session.units.rawValue)
            defaults.seconds = edited.result.seconds != nil
        }
        let shown = edited.flatMap {
            SetCard.of(session: session, step: $0.step, history: history, colour: .done,
                       field: $0.result.reps ?? $0.result.seconds)
        } ?? SetCard.of(session: session, step: index, history: history, colour: .now,
                        field: InputRules.repsValue(defaults.reps))
        guard let card = shown else { return nil }
        return WorkoutScreenModel(
            // Every state returns the same five, in the same order (D22, O50).
            zones: WorkoutZone.allCases,
            step: index,
            exerciseIndex: step.exerciseIndex,
            stage: WorkoutStage.current(active: active, step: index),
            completion: WorkoutStage.progress(session),
            elapsed: TargetText.time(wholeSeconds(SessionStats.duration(session, now: now))),
            progress: StepCard.progress(session: session, step: index,
                                        wording: settings.wording),
            bar: WorkoutBar.of(session: active),
            exerciseName: exercise.name,
            exerciseMark: MarkState.of(exercise: step.exerciseIndex, session: active),
            notes: notes(exercise),
            dots: block.enumerated().map { position, i in
                let state = MarkState.of(step: i, session: active)
                let skipped = session.steps[i].status == .skipped
                return SetDot(step: i, state: state, skipped: skipped,
                              spoken: "Set \(position + 1) of \(block.count), "
                                + (skipped ? "skipped" : state == .done ? "done" : state == .now ? "now" : "not yet"))
            },
            card: card,
            editing: edited?.step,
            inputs: defaults,
            // A hold being changed takes a field for its seconds, so no timer stands in its place.
            timer: timed && edited == nil ? timer(active: active, step: index, work: target.work,
                                                  warning: target.warning, now: now) : nil,
            strip: strip(active: active, step: index, work: target.work, warning: target.warning,
                         wording: settings.wording, history: history, now: now,
                         walk: walk ?? (RestResolution.walk(plan: nil, settings: settings), false)),
            primary: edited != nil ? PrimaryAction(title: "Save", kind: .save)
                : primary(work: target.work, running: active.timerRunning, resting: restKind),
            spoken: StepCard.spoken(session: session, step: index),
            undoStep: active.canUndo ? active.lastCompletedStep : nil)
    }

    /// D81 (v1.10): what the ? opens — "was Barbell Row" first for a changed exercise (D42), then
    /// the notes. Nil when there is neither, so no ? leads nowhere (D56).
    static func notes(_ exercise: SessionExercise) -> String? {
        var lines: [String] = []
        if let was = exercise.substitutedFor { lines.append("was \(was)") }
        if let note = exercise.notes?.trimmed, !note.isEmpty { lines.append(note) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func primary(work: WorkTarget, running: Bool, resting: RestKind? = nil) -> PrimaryAction {
        // D57 (v1.6): during the warm-up nothing has been done yet, so the button starts the
        // set rather than logging one — a stranger tapped "Log set" and logged a set they had
        // not done. Between-set rests keep Log set: a set *has* been done by then, and logging
        // the next one straight out of the rest is the coach's flow (§4.5).
        if resting == .warmUp { return PrimaryAction(title: "Start first set", kind: .startSet) }
        switch work {
        case .reps:
            return PrimaryAction(title: "Log set", kind: .log)
        case .duration:
            return running ? PrimaryAction(title: "Done", kind: .doneTimer)
                           : PrimaryAction(title: "Start timer", kind: .startTimer)
        case .openDuration:
            return running ? PrimaryAction(title: "Stop", kind: .stopTimer)
                           : PrimaryAction(title: "Start timer", kind: .startTimer)
        }
    }

    static func inputs(values: PrefillValues, target: (work: WorkTarget, weight: Double?, warning: Int?, reserve: Int?),
                       units: WeightUnit) -> InputDefaults {
        var defaults = InputDefaults(
            reps: values.reps.map(String.init) ?? "",
            weight: InputRules.weightText(values.weight),
            showsWeight: values.showsWeight,
            unit: units.rawValue)
        defaults.suggestion = StepCard.suggestionChip(values, units: units)
        defaults.suggestionReason = values.suggestion?.reason
        defaults.suggestedWeight = values.suggestion?.weight ?? values.suggestedWeight
        defaults.suggestedReps = values.suggestion?.reps
        if case let .duration(seconds) = target.work, defaults.reps.isEmpty {
            defaults.reps = String(values.seconds ?? seconds)
        }
        if values.showsWeight, values.weight == nil, values.lastWeight == nil {
            defaults.weightHint = WorkoutText.weightHint
        }
        return defaults
    }

    static func timer(active: ActiveSession, step: Int, work: WorkTarget,
                      warning: Int?, now: Date) -> TimerDisplay {
        let running = active.timerRunning
        let started = active.session.steps[safe: step]?.startedAt
        let elapsed = running ? (started.map { wholeSeconds(now.timeIntervalSince($0)) } ?? 0) : 0
        switch work {
        case let .duration(seconds):
            let remaining = running ? max(0, seconds - elapsed) : seconds
            return TimerDisplay(text: TargetText.time(remaining),
                                accented: running && warning.map { remaining <= $0 } == true,
                                running: running, minimumNote: nil)
        case let .openDuration(minimum):
            return TimerDisplay(text: TargetText.time(elapsed),
                                accented: running && minimum.map { elapsed >= $0 } == true,
                                running: running,
                                minimumNote: running ? nil : minimum.map { "\($0)+ s" })
        case .reps:
            return TimerDisplay(text: "", accented: false, running: false, minimumNote: nil)
        }
    }

    /// SPEC §4.6 and §4.7. Rest wins over a block-done line, because only one of them can be
    /// true at a time: a block that just ended never starts a rest (§6.3).
    static func strip(active: ActiveSession, step: Int, work: WorkTarget, warning: Int?,
                      wording: Wording = .plain,
                      history: [Session], now: Date,
                      walk: (minimum: Int, fromPlan: Bool) = (120, false)) -> StatusStrip {
        let session = active.session
        var strip = StatusStrip()
        // D81 (v1.10): Undo is back in the strip, during the rest the set started or the moment
        // its block ended (§4.6's v1.2 place); after that the set's dot is the way to change it.
        let justLogged: Bool
        if case .resting = active.phase { justLogged = true } else { justLogged = active.blockDone != nil }
        strip.undo = active.canUndo && justLogged ? "Set logged · Undo" : nil

        // D82 (v1.10, §6.55): the walk between exercises counts up beside a ring — while its
        // rest runs to the ring's end, and after, until Log set or Start timer ends it. The
        // rest's own span is the minimum while it runs; the plan's or the setting's after.
        if case let .resting(rest) = active.phase, rest.kind == .betweenExercises {
            return walkStrip(strip, session: session, blockDone: active.blockDone,
                             startedAt: rest.startedAt, next: rest.nextStep,
                             minimum: wholeSeconds(rest.endsAt.timeIntervalSince(rest.startedAt)),
                             fromPlan: walk.fromPlan, now: now)
        }
        if case .working = active.phase, let blockDone = active.blockDone,
           StepCard.blockDoneLine(session: session, blockDone: blockDone) != nil {
            return walkStrip(strip, session: session, blockDone: blockDone,
                             startedAt: blockDone.startedAt, next: step,
                             minimum: walk.minimum, fromPlan: walk.fromPlan, now: now)
        }

        if case let .resting(rest) = active.phase {
            let remaining = Int(rest.endsAt.timeIntervalSince(now).rounded(.up))
            strip.kind = remaining > 0 ? .resting : .restOver
            strip.countdown = remaining > 0
                ? TargetText.time(remaining)
                : "+" + TargetText.time(wholeSeconds(now.timeIntervalSince(rest.endsAt)))
            // v1.2: a break always says which of the three it is (§4.6). v1.1 showed a bare
            // countdown, which is the thing the owner said was unclear.
            strip.title = remaining > 0 ? rest.kind.title : rest.kind.overTitle
            strip.restKind = rest.kind
            strip.skipTitle = rest.kind.skipTitle
            strip.next = nextLine(session: session, step: rest.nextStep, wording: wording)
            // A block that ended and then started this walk still says what finished — but on
            // the strip's own line, not squeezed in beside the countdown, where it wrapped and
            // truncated its own advice. "Next:" would be redundant here anyway: the next
            // exercise is already the heading on screen.
            strip.detail = rest.kind == .warmUp ? nil : lastSetLine(session)
            strip.showsRestControls = true
            return strip
        }

        if active.timerRunning, work.isTimed {
            strip.kind = .timed
            let elapsed = session.steps[safe: step]?.startedAt
                .map { wholeSeconds(now.timeIntervalSince($0)) } ?? 0
            switch work {
            case let .duration(seconds):
                if let warning, seconds - elapsed <= warning { strip.title = "Almost there" }
            case let .openDuration(minimum):
                if let minimum, elapsed >= minimum { strip.title = "\(minimum) s reached" }
            case .reps:
                break
            }
            return strip
        }

        // Working with nothing to report: the zone stays, so nothing below it moves — and
        // since v1.6 (D59) it says what the button will start, rather than sitting blank.
        strip.title = idleLine(session: session, step: step)
        strip.detail = lastSetLine(session)
        return strip
    }

    /// D82 (v1.10, §6.55): the walk's strip — the count-up in the large figure, the ring, the
    /// next exercise's name, and no −30 / +30 / Skip. The finished block's line, advice and
    /// all, is what VoiceOver hears; the Summary keeps the advice in print (§4.7).
    private static func walkStrip(_ base: StatusStrip, session: Session, blockDone: BlockDone?,
                                  startedAt: Date, next: Int, minimum: Int, fromPlan: Bool,
                                  now: Date) -> StatusStrip {
        var strip = base
        let start = blockDone?.startedAt ?? startedAt
        let elapsed = TargetText.time(wholeSeconds(max(0, now.timeIntervalSince(start))))
        let ring = WalkRing.of(startedAt: start, minimum: minimum, fromPlan: fromPlan, now: now)
        strip.kind = .blockDone
        strip.restKind = .betweenExercises
        strip.skipTitle = RestKind.betweenExercises.skipTitle
        strip.direction = .up
        strip.countdown = elapsed
        strip.ring = ring
        strip.title = blockDone.flatMap { StepCard.blockDoneLine(session: session, blockDone: $0) }
            ?? RestKind.betweenExercises.title
        let name = session.steps[safe: next].flatMap { session.exercises[safe: $0.exerciseIndex]?.name }
        strip.next = name
        var spoken = ["\(RestKind.betweenExercises.title), \(elapsed)",
                      ring.full ? "ready" : "at least \(TargetText.time(ring.minimum))"]
        if let name { spoken.append("next, \(name)") }
        if let line = strip.title, line != RestKind.betweenExercises.title { spoken.append(line) }
        strip.spoken = spoken.joined(separator: ". ")
        strip.showsRestControls = false
        return strip
    }

    /// D59 (v1.6): what follows the set on the card — "Rest 1:30 starts when you log", or,
    /// on a block's last set, "Then on to Barbell Row". Nil for the last set of the day.
    static func idleLine(session: Session, step index: Int) -> String? {
        guard let step = session.steps[safe: index] else { return nil }
        if !step.isLastInBlock {
            guard step.isLastInRound,
                  let target = session.exercises[safe: step.exerciseIndex]?.targets[safe: step.setIndex],
                  (target.groupRestSeconds ?? target.restSeconds) > 0 else { return nil }
            return "Rest \(TargetText.time(target.groupRestSeconds ?? target.restSeconds)) starts when you log"
        }
        guard let next = session.steps.dropFirst(index + 1).first(where: { $0.blockIndex != step.blockIndex && $0.status == .pending }),
              let exercise = session.exercises[safe: next.exerciseIndex] else { return nil }
        return "Then on to \(exercise.name)"
    }

    /// "Next: Bench Press · set 2 of 3 · Aim 8–12 reps · 60 kg".
    static func nextLine(session: Session, step index: Int,
                         wording: Wording = .plain) -> String? {
        guard let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex],
              let target = session.target(at: index) else { return nil }
        let work = SetTarget(work: target.work, weight: target.weight, restSeconds: 0, inReserve: target.reserve)
        return "Next: \(exercise.name) · set \(step.setIndex + 1) of \(exercise.targets.count) · "
            + TargetText.target(work, range: exercise.repRange, units: session.units,
                                wording: wording)
    }

    /// "set 0:34" — how long the set that was just logged took (D19), small text only.
    static func lastSetLine(_ session: Session) -> String? {
        let logged = session.steps.filter { $0.status == .logged }
        guard let seconds = logged
            .max(by: { ($0.loggedAt ?? .distantPast) < ($1.loggedAt ?? .distantPast) })?.setSeconds
        else { return nil }
        return "set \(TargetText.time(seconds))"
    }
}
