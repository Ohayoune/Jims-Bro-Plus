import Foundation

struct PrefillValues: Equatable {
    var weight: Double?
    var reps: Int?
    var seconds: Int?
    var lastWeight: Double?
    var suggestedWeight: Double?
    var showsWeight: Bool
    /// D36 (v1.2): what to aim for on *this* set, and why. v1.1 had only a bare
    /// "82.5 kg suggested" chip, and only when the whole exercise had earned advice.
    var suggestion: SetSuggestion?
}

/// SPEC §6.11 (D36, v1.2): the suggestion for one set — the numbers, said as a target, with the
/// reason underneath. "The steps need a bit of work and suggestions for the sets" was the
/// owner's note; a chip reading "82.5 kg suggested", with nothing to say where it came from and
/// nothing about the reps, is not a suggestion so much as a number.
struct SetSuggestion: Equatable {
    var reps: Int?
    var weight: Double?
    /// "8 × 82.5 kg", "12 reps", "45 s" — what to aim for, in the shape the set is measured in.
    var text: String
    /// "All sets hit the top of 8–12 last time", "Last time 8 × 80 kg", "The plan's target".
    var reason: String
    /// True when it came from progression advice rather than from repeating last time.
    var isProgression: Bool

    /// The chip's label. Short, because it sits under the weight field.
    var chip: String { "Try \(text)" }
}
struct LastTimeEntry: Equatable { var text: String; var isCurrent: Bool; var setIndex: Int; var dropIndex: Int }
struct LastTimeLine: Equatable {
    var entries: [LastTimeEntry]
    var suffix: String
    var text: String {
        var result = ""
        for (i, e) in entries.enumerated() { if i > 0 { result += e.dropIndex == 0 ? ", " : "↓" }; result += e.text }
        return result + suffix
    }
}
enum Prefill {
    static func targetReps(_ work: WorkTarget) -> Int? {
        switch work { case let .reps(.fixed(n)): return n; case let .reps(.range(min:n,max:_)): return n; default: return nil }
    }
    /// The one scan of history for a step (§6.5): the last session before this one that did
    /// the step's exercise, and that exercise's steps in it.
    static func lastSteps(session: Session, step index: Int, history: [Session]) -> (session: Session, steps: [SessionStep])? {
        guard let step = session.steps[safe:index], let e = session.exercises[safe:step.exerciseIndex], let last = ExerciseHistory.last(name:e.name,units:session.units,sessions:history.filter { $0.id != session.id && $0.startedAt < session.startedAt }) else { return nil }
        return (last, ExerciseHistory.steps(name:e.name,session:last))
    }
    /// Last time's result for `step`, among `last` — the same set and drop, else, for a main set,
    /// the last main set logged. `keep` is what the caller needs of it: a weight, for the
    /// weight's own lookup, which passes over a set logged without one.
    static func lastResult(for step: SessionStep, in last: [SessionStep],
                           keep: (SetResult) -> Bool = { _ in true }) -> SetResult? {
        let logged = last.filter { $0.status == .logged && $0.result.map(keep) == true }
        if let same = logged.first(where: { $0.setIndex == step.setIndex && $0.dropIndex == step.dropIndex }) { return same.result }
        // Missing/skipped main set indices use the last logged main set.
        guard step.dropIndex == 0 else { return nil }
        return logged.last { $0.dropIndex == 0 }?.result
    }
    static func historicalResult(session: Session, step index: Int, history: [Session]) -> SetResult? {
        guard let step = session.steps[safe:index], let last = lastSteps(session:session,step:index,history:history) else { return nil }
        return lastResult(for: step, in: last.steps)
    }
    static func values(session: Session, step index: Int, history: [Session],
                       settings: Settings = Settings()) -> PrefillValues {
        guard let step = session.steps[safe:index], let e = session.exercises[safe:step.exerciseIndex], let target = session.target(at:index) else { return PrefillValues(showsWeight:false) }
        let lastTime = lastSteps(session:session,step:index,history:history)
        let last = lastTime.flatMap { lastResult(for: step, in: $0.steps) }
        let lastWeight = lastTime.flatMap { lastResult(for: step, in: $0.steps, keep: { $0.weight != nil }) }?.weight
        let previousSteps = session.steps.prefix(index).filter { $0.status == .logged && $0.exerciseIndex == step.exerciseIndex }
        let weight: Double?
        if e.bodyweight { weight = nil }
        else if e.progressionWeek != nil, step.dropIndex == 0, let planned = target.weight {
            // D44 (v1.3), rule 0: this week's progression target beats last time — you asked
            // a chatbot to plan it, and the plan is what the card should show.
            weight = planned
        }
        else if step.dropIndex > 0 {
            weight = last?.weight ?? target.weight ?? session.steps[safe:index-1]?.result?.weight
        } else if e.hasVariedTargets {
            // D11 (v1.1): a deliberately varied exercise (e.g. a 50→60→70 kg pyramid) never
            // carries a weight forward from an earlier set logged this session — each set keeps
            // the identity the plan gave it.
            weight = lastWeight ?? target.weight
        } else {
            // Straight sets: most recently logged weight this session, not the largest set index.
            weight = previousSteps.filter { $0.result?.weight != nil }.max { ($0.loggedAt ?? .distantPast) < ($1.loggedAt ?? .distantPast) }?.result?.weight ?? lastWeight ?? target.weight
        }
        // D44: in a progression week the week's reps are the target, whatever last time was.
        let reps = e.progressionWeek != nil && step.dropIndex == 0
            ? targetReps(target.work) ?? last?.reps
            : (weight == (e.bodyweight ? nil : last?.weight) ? last?.reps ?? targetReps(target.work) : targetReps(target.work))
        let seconds: Int?
        if case let .duration(n) = target.work { seconds = last?.seconds ?? n } else { seconds = nil }
        var suggestion: Double?
        var adviceReason: String?
        if let lastSession = lastTime?.session,
           let advice = lastSession.exercises.first(where: { normalized($0.name) == normalized(e.name) })?.advice {
            switch advice {
            case let .increase(w):
                suggestion = w
                adviceReason = e.repRange.map { "You hit the top of \($0.min)–\($0.max) last time" }
                    ?? "You finished the range last time"
            case let .decrease(w):
                suggestion = w
                adviceReason = e.repRange.map { "You were below \($0.min)–\($0.max) last time" }
                    ?? "You were below the range last time"
            default: break
            }
        }
        // D35: whatever it suggests must be loadable.
        let increment = settings.weightIncrement(for: session.units)
        suggestion = suggestion.map { WeightRounding.snap($0, increment: increment) }
        var values = PrefillValues(weight:weight,reps:reps,seconds:seconds,
                                   lastWeight:e.bodyweight ? nil : lastWeight,
                                   suggestedWeight:e.bodyweight ? nil : suggestion,
                                   showsWeight:!e.bodyweight)
        values.suggestion = setSuggestion(session: session, step: index, exercise: e, target: target,
                                          last: last, lastWeight: lastWeight,
                                          advice: e.bodyweight ? nil : suggestion,
                                          adviceReason: adviceReason, units: session.units,
                                          progression: step.dropIndex == 0
                                              ? e.progressionWeek.map { (week: $0, weeks: session.progressionWeeks,
                                                                         mode: session.progressionMode ?? .calendar) } : nil)
        // D55 (v1.6): a chip that says exactly what the fields already show is not a
        // suggestion — "Try 4 reps · The plan's target" under a reps field reading 4. A
        // progression's chip stays: its reason, which step this is, is the point of it. A
        // timed chip has neither reps nor weight and is judged by its seconds, not here.
        // A chip with no opinion on one axis (the plan's "8 reps" on a plan without weights)
        // is judged on the axis it has.
        if let chip = values.suggestion, !chip.isProgression,
           chip.reps != nil || chip.weight != nil,
           chip.reps == nil || chip.reps == values.reps,
           chip.weight == nil || chip.weight == values.weight {
            values.suggestion = nil
        }
        return values
    }
    /// D36 (v1.2): the suggestion for one set, in order of how much it knows.
    ///
    /// 1. Progression advice from the last time this exercise was done — it read every set.
    /// 2. What was done for *this set index* last time — the honest "do that again".
    /// 3. The plan's own target, which is what the plan asked for in the first place.
    ///
    /// Nil for a set with nothing to say beyond its target — an unloaded bodyweight set whose
    /// target the card is already showing.
    static func setSuggestion(session: Session, step index: Int, exercise: SessionExercise,
                              target: StepTarget,
                              last: SetResult?, lastWeight: Double?, advice: Double?,
                              adviceReason: String?, units: WeightUnit,
                              progression: (week: Int, weeks: Int?, mode: ProgressionMode)? = nil) -> SetSuggestion? {
        let unit = units.rawValue
        func line(_ reps: Int?, _ weight: Double?) -> String {
            switch (reps, weight) {
            case let (reps?, weight?): return "\(reps) × \(TargetText.number(weight)) \(unit)"
            case let (reps?, nil): return "\(reps) rep\(reps == 1 ? "" : "s")"
            case let (nil, weight?): return "\(TargetText.number(weight)) \(unit)"
            case (nil, nil): return ""
            }
        }
        // D44 (v1.3): in a progression week the set's target *is* the suggestion, and the
        // reason says which week — it outranks advice from last time, which the chatbot has
        // already read.
        if let progression {
            let reason = ProgressionText.reason(week: progression.week, of: progression.weeks, mode: progression.mode)
            if case let .duration(planned) = target.work {
                return SetSuggestion(reps: nil, weight: nil, text: "\(planned) s", reason: reason, isProgression: true)
            }
            guard !target.work.isTimed else { return nil }
            let reps = targetReps(target.work)
            let weight = exercise.bodyweight ? nil : target.weight
            guard reps != nil || weight != nil else { return nil }
            return SetSuggestion(reps: reps, weight: weight, text: line(reps, weight), reason: reason,
                                 isProgression: true)
        }
        // Timed work is measured in seconds; suggesting reps for it would be nonsense.
        if target.work.isTimed {
            guard let seconds = last?.seconds, case let .duration(planned) = target.work,
                  seconds != planned else { return nil }
            return SetSuggestion(reps: nil, weight: nil, text: "\(seconds) s",
                                 reason: "Last time you held \(TargetText.time(seconds))",
                                 isProgression: false)
        }
        let reps = targetReps(target.work)
        if let advice, let adviceReason {
            return SetSuggestion(reps: reps, weight: advice, text: line(reps, advice),
                                 reason: adviceReason, isProgression: true)
        }
        // D55 (v1.6): "do that again" is what was done — last time's reps at last time's weight
        // — never the plan's reps at last time's weight, which read "Try 5 × 100 kg" under
        // "Last time 10 × 100 kg". The plan's reps stand in only when last time has none for
        // this set.
        if let lastWeight, !exercise.bodyweight {
            let lastReps = last?.reps
            return SetSuggestion(reps: lastReps ?? reps, weight: lastWeight,
                                 text: line(lastReps ?? reps, lastWeight),
                                 reason: "Last time \(line(lastReps, lastWeight))",
                                 isProgression: false)
        }
        if let lastReps = last?.reps, exercise.bodyweight {
            return SetSuggestion(reps: lastReps, weight: nil, text: line(lastReps, nil),
                                 reason: "Last time \(lastReps) rep\(lastReps == 1 ? "" : "s")",
                                 isProgression: false)
        }
        guard let reps else { return nil }
        return SetSuggestion(reps: reps, weight: exercise.bodyweight ? nil : target.weight,
                             text: line(reps, exercise.bodyweight ? nil : target.weight),
                             reason: "The plan's target", isProgression: false)
    }

    static func lastTime(session: Session, step index: Int, history: [Session]) -> LastTimeLine? {
        guard let step = session.steps[safe:index], let last = lastSteps(session:session,step:index,history:history) else { return nil }
        let steps = last.steps.sorted { ($0.setIndex,$0.dropIndex) < ($1.setIndex,$1.dropIndex) }
        let weights = steps.filter { $0.status == .logged }.map { $0.result?.weight }
        let firstWeight = weights.first ?? nil
        let sameWeight = weights.allSatisfy { $0 == firstWeight }
        let common = sameWeight ? weights.first.flatMap { $0 } : nil
        let entries = steps.map { s -> LastTimeEntry in
            let result = s.status == .logged ? s.result : nil
            var text = result?.reps.map(String.init) ?? result?.seconds.map(TargetText.time) ?? "–"
            if !sameWeight, let w = result?.weight { text += "@\(TargetText.number(w))" }
            return LastTimeEntry(text:text,isCurrent:s.setIndex == step.setIndex && s.dropIndex == step.dropIndex,setIndex:s.setIndex,dropIndex:s.dropIndex)
        }
        let suffix = common.map { " @ \(TargetText.number($0)) \(session.units.rawValue)" } ?? (weights.contains { $0 != nil } ? " \(session.units.rawValue)" : "")
        return LastTimeLine(entries:entries,suffix:suffix)
    }
}
