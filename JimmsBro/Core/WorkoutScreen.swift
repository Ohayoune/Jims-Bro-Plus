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
}

/// Zone 5. One control, one slot, whatever the work is (D20, D22).
struct PrimaryAction: Equatable {
    enum Kind: String, Equatable { case log, startTimer, doneTimer, stopTimer }
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
}

/// The whole workout screen as data. Views render it; they compute nothing.
struct WorkoutScreenModel: Equatable {
    var zones: [WorkoutZone]
    var step: Int
    var exerciseIndex: Int
    /// D34 (v1.2): which stage the workout is in, and how far through the day it is.
    var stage: WorkoutStage
    var completion: Double
    var elapsed: String
    var progress: String
    var exerciseName: String
    var targetLine: String
    var rows: [SetRow]
    var inputs: InputDefaults
    var timer: TimerDisplay?
    var strip: StatusStrip
    var primary: PrimaryAction
    /// The one VoiceOver string for the exercise block (SPEC §9).
    var spoken: String
}

enum WorkoutScreen {
    /// Nil only when the session is over — the Summary owns the screen then.
    static func model(active: ActiveSession, history: [Session], now: Date,
                      settings: Settings = Settings()) -> WorkoutScreenModel? {
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
        return WorkoutScreenModel(
            // Every state returns the same five, in the same order (D22, O50).
            zones: WorkoutZone.allCases,
            step: index,
            exerciseIndex: step.exerciseIndex,
            stage: WorkoutStage.current(active: active, step: index),
            completion: WorkoutStage.progress(session),
            elapsed: TargetText.time(wholeSeconds(SessionStats.duration(session, now: now))),
            progress: StepCard.progress(session: session, step: index),
            exerciseName: exercise.name,
            targetLine: StepCard.targetLine(session: session, step: index),
            rows: StepCard.setRows(session: session, step: index, history: history),
            inputs: inputs(values: values, target: target, units: session.units),
            timer: timed ? timer(active: active, step: index, work: target.work,
                                 warning: target.warning, now: now) : nil,
            strip: strip(active: active, step: index, work: target.work, warning: target.warning,
                         history: history, now: now),
            primary: primary(work: target.work, running: active.timerRunning),
            spoken: StepCard.spoken(session: session, step: index))
    }

    static func primary(work: WorkTarget, running: Bool) -> PrimaryAction {
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

    static func inputs(values: PrefillValues, target: (work: WorkTarget, weight: Double?, warning: Int?),
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
                      history: [Session], now: Date) -> StatusStrip {
        let session = active.session
        var strip = StatusStrip()
        strip.undo = active.canUndo ? "Set logged · Undo" : nil

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
            strip.next = nextLine(session: session, step: rest.nextStep)
            // A block that ended and then started this walk still says what finished — but on
            // the strip's own line, not squeezed in beside the countdown, where it wrapped and
            // truncated its own advice. "Next:" would be redundant here anyway: the next
            // exercise is already the heading on screen.
            strip.detail = rest.kind == .warmUp ? nil : lastSetLine(session)
            if rest.kind == .betweenExercises, let blockDone = active.blockDone,
               let line = StepCard.blockDoneLine(session: session, blockDone: blockDone) {
                strip.next = line
                // The block's line is a sentence with the advice in it; "set 0:34" is not worth
                // truncating it for, and the Overview keeps the set durations anyway (D19).
                strip.detail = nil
            }
            strip.showsRestControls = true
            return strip
        }

        if let blockDone = active.blockDone,
           let line = StepCard.blockDoneLine(session: session, blockDone: blockDone) {
            strip.kind = .blockDone
            strip.title = line
            strip.detail = "moving on · " + TargetText.time(wholeSeconds(now.timeIntervalSince(blockDone.startedAt)))
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

        // Working with nothing to report: the zone stays, empty, so nothing below it moves.
        strip.detail = lastSetLine(session)
        return strip
    }

    /// "Next: Bench Press · set 2 of 3 · 8–12 · 60 kg".
    static func nextLine(session: Session, step index: Int) -> String? {
        guard let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex],
              let target = session.target(at: index) else { return nil }
        let work = SetTarget(work: target.work, weight: target.weight, restSeconds: 0)
        return "Next: \(exercise.name) · set \(step.setIndex + 1) of \(exercise.targets.count) · "
            + TargetText.target(work, range: exercise.repRange, units: session.units)
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
