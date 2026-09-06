import Foundation

/// SPEC §4.5's five zones (D22), in the one order they ever appear in. `WorkoutScreen.model`
/// returns all five for every state, so "the zones never move" is a property a test can check
/// rather than a promise the view layer has to keep on its own.
enum WorkoutZone: String, Equatable, Sendable, CaseIterable {
    case header, exercise, inputs, strip, primary
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
    /// "82.5 kg suggested" and the number behind it, when §6.11 produced one.
    var suggestion: String?
    var suggestedWeight: Double?
}

/// The whole workout screen as data. Views render it; they compute nothing.
struct WorkoutScreenModel: Equatable {
    var zones: [WorkoutZone]
    var step: Int
    var exerciseIndex: Int
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
    static func model(active: ActiveSession, history: [Session], now: Date) -> WorkoutScreenModel? {
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

        let values = Prefill.values(session: session, step: index, history: history)
        let timed = target.work.isTimed
        return WorkoutScreenModel(
            // Every state returns the same five, in the same order (D22, O50).
            zones: WorkoutZone.allCases,
            step: index,
            exerciseIndex: step.exerciseIndex,
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
        defaults.suggestedWeight = values.suggestedWeight
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
            strip.title = remaining > 0 ? nil : "Rest over"
            strip.next = nextLine(session: session, step: rest.nextStep)
            strip.detail = lastSetLine(session)
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
