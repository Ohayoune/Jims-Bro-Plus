import Foundation

enum Event {
    case logSet(step: Int, result: SetResult), editSet(step: Int, result: SetResult)
    case skipSet(step: Int), skipExercise(exerciseIndex: Int), jumpTo(step: Int)
    case adjustRest(seconds: Int), skipRest, restElapsed
    case startTimer(step: Int), stopTimer(step: Int), timerDone(step: Int), timerElapsed(step: Int)
    /// D23 v1.1: undoes the most recently logged-or-skipped step, if nothing was logged after it.
    case undoLog(step: Int)
    /// D14 v1.1: clears the status strip's block-just-finished state; replaces `continueTransition`,
    /// since the next step's card is already showing by the time this fires.
    case dismissBlockDone
    /// D28 v1.1 (R5): moves an exercise's remaining sets to the end of the day — the machine is
    /// taken, so do it later rather than skipping it.
    case deferExercise(exerciseIndex: Int)
    /// D42 v1.3: the machine is taken and you want to do *something* now — the exercise's
    /// remaining sets become sets of another exercise, which keeps its own history identity.
    case substituteExercise(exerciseIndex: Int, name: String, weight: Double?)
    case renameExercise(exerciseIndex: Int, name: String), finish
    case setWorkWeight(step: Int, weight: Double?)
}
enum Effect: Equatable {
    case scheduleNotification(id: AlertIdentifier, at: Date, body: String)
    case cancelNotification(id: AlertIdentifier)
    case playAlert(TimerBeep)
    /// v1.1 (D22/P6): the confirmation a logged set gets. An effect rather than a view-side
    /// call so "exactly once per logged set" is assertable in Core (O59).
    case playFeedback(Feedback)
    case persist, sessionCompleted
}
struct SessionEngine {
    private(set) var active: ActiveSession
    var settings: Settings
    var history: [Session]
    /// D82 (v1.10): the plan's walk between exercises, set by `PlanLibrary` from the plan the
    /// session belongs to. Not stored: the plan is on disk, and nil hands the walk to the setting.
    var restBetweenExercises: Int?
    /// The walk's minimum as the ring draws it, and whether the plan declared it.
    var walk: (minimum: Int, fromPlan: Bool) {
        (RestResolution.walk(plan: restBetweenExercises, settings: settings), restBetweenExercises != nil)
    }
    var session: Session { active.session }
    var phase: Phase { active.phase }
    /// What a freshly started session needs run: the warm-up's notification, if it has one,
    /// and the save. `PlanLibrary.startDay` returns these, so nothing else has to know.
    var initialEffects: [Effect] { startEffects + [.persist] }
    var adviceForBlockJustFinished: [Advice] {
        guard let blockDone = active.blockDone else { return [] }
        let indices = Set(session.steps.filter { $0.blockIndex == blockDone.finishedBlock }.map(\.exerciseIndex))
        return indices.sorted().compactMap { session.exercises[safe: $0]?.advice }
    }
    /// Whether `undoLog` would currently succeed, so the UI can show or hide the affordance.
    var canUndo: Bool { active.canUndo }
    /// The effects a new session's warm-up needs scheduling, if it has one. `initialEffects`
    /// stays what it was — a `.persist` — so nothing that only wants to save has to change.
    private(set) var startEffects: [Effect] = []

    init(session: Session, settings: Settings = Settings(), history: [Session] = [], now: Date) {
        self.settings = settings
        self.history = history
        active = ActiveSession(session: session, phase: session.steps.isEmpty ? .completed : .working(step: 0))
        guard let index = session.steps.indices.first else { return }
        enterWorking(index, now: now)
        // D32 (v1.2, §6.14): a session begins with a warm-up, not on set 1. It is a rest in
        // every mechanical sense, so it is one — the countdown, the controls, the notification
        // and the right to log straight out of it are all already written.
        guard settings.warmUpSeconds > 0 else { return }
        let endsAt = now.addingTimeInterval(Double(settings.warmUpSeconds))
        active.phase = .resting(RestState(startedAt: now, endsAt: endsAt, nextStep: index,
                                          kind: .warmUp))
        startEffects = [.cancelNotification(id: .rest),
                        .scheduleNotification(id: .rest, at: endsAt, body: nextBody(index))]
    }
    init(active: ActiveSession, settings: Settings = Settings(), history: [Session] = []) { self.active = active; self.settings = settings; self.history = history }
    func nextStep(after index: Int) -> Int? {
        session.steps.indices.first { $0 > index && session.steps[$0].status == .pending }
        ?? session.steps.indices.first { session.steps[$0].status == .pending }
    }
    private var currentStep: Int? { active.currentStep }
    private mutating func enterWorking(_ index: Int, now: Date) {
        active.phase = .working(step: index)
        active.timerRunning = false; active.deliveredBeeps = []
        guard active.session.steps.indices.contains(index) else { return }
        active.workWeight = Prefill.values(session: session, step: index, history: history,
                                           settings: settings).weight
        active.session.steps[index].startedAt = session.target(at: index)?.work.isTimed == true ? nil : now
    }
    private mutating func cancelWork() -> [Effect] {
        active.timerRunning = false; active.deliveredBeeps = []
        return AlertIdentifier.work.map { .cancelNotification(id: $0) }
    }
    private mutating func reevaluateAdvice(_ e: Int) {
        guard session.exercises.indices.contains(e) else { return }
        // D42: an exercise whose remaining sets went to a substitute did not finish the job the
        // advice would be judging, so it earns none — the substitute earns its own.
        guard !session.exercises.contains(where: { $0.replaces == e }) else {
            active.session.exercises[e].advice = nil; return
        }
        let steps = session.steps.filter { $0.exerciseIndex == e }
        guard !steps.contains(where: { $0.status == .pending }) else { return }
        active.session.exercises[e].advice = ProgressionAdvice.evaluate(
            exercise: session.exercises[e], steps: steps,
            weightStep: settings.weightStep(for: session.units),
            increment: settings.weightIncrement(for: session.units))
    }
    private mutating func complete(now: Date) -> [Effect] {
        active.session.endedAt = now; active.phase = .completed; active.blockDone = nil
        for e in session.exercises.indices { reevaluateAdvice(e) }
        return [.sessionCompleted]
    }
    /// SPEC §6.3 (v1.1): a finished block advances straight into `working(next)` — there is no
    /// separate phase for it — with `BlockDone` recording what the status strip shows.
    private mutating func advance(after index: Int, now: Date, skipped: Bool) -> [Effect] {
        active.blockDone = nil
        let next = nextStep(after: index)
        guard let next else { return complete(now: now) }
        let advance = RestResolution.after(index, next: next, steps: session.steps,
                                          exercises: session.exercises, settings: settings,
                                          restBetweenExercises: restBetweenExercises)
        switch advance {
        case .completed: return complete(now: now)
        case let .blockDone(seconds):
            let finishedBlock = session.steps[index].blockIndex
            enterWorking(next, now: now)
            active.blockDone = BlockDone(finishedBlock: finishedBlock, startedAt: now)
            // D33 (v1.2): a real rest for the walk to the next machine. Unlike a rest between
            // sets, a *skipped* set still gets it — the walk happens either way — and the next
            // exercise's card is already on screen throughout, so it gates nothing. D82 (v1.10):
            // the strip counts it up and fills a ring to `endsAt`; the alert is where it was.
            guard seconds > 0 else { return [] }
            return startRest(seconds: seconds, next: next, kind: .betweenExercises, now: now)
        case let .rest(seconds):
            if skipped || seconds == 0 { enterWorking(next, now: now); return [] }
            return startRest(seconds: seconds, next: next, kind: .betweenSets, now: now)
        }
    }

    private mutating func startRest(seconds: Int, next: Int, kind: RestKind, now: Date) -> [Effect] {
        let endsAt = now.addingTimeInterval(Double(seconds))
        active.phase = .resting(RestState(startedAt: now, endsAt: endsAt, nextStep: next, kind: kind))
        return [.cancelNotification(id: .rest),
                .scheduleNotification(id: .rest, at: endsAt, body: nextBody(next))]
    }
    /// §6.4's body, "Next: Bench Press · set 2 of 3 · Aim 8–12 reps · 60 kg" — the step as the
    /// strip says it (`StepCard.stepLine`). D58 (v1.6): the notification is read by a person on
    /// a Lock Screen, so it uses whichever grammar the app is set to, like every other sentence.
    private func nextBody(_ index: Int) -> String {
        StepCard.stepLine(session: session, step: index, wording: settings.wording).map { "Next: " + $0 } ?? "Next set"
    }
    private func valid(_ result: SetResult) -> Bool {
        let count = result.reps ?? result.seconds ?? -1
        return count >= 0 && count <= 99_999 && (result.weight.map(TargetGrammar.isWeight) ?? true)
    }
    private func cleaned(_ result: SetResult, step: Int) -> SetResult {
        guard let s = session.steps[safe: step], session.exercises[safe: s.exerciseIndex]?.bodyweight == true else { return result }
        switch result { case let .reps(n,_): return .reps(count:n,weight:nil); case let .duration(n,_): return .duration(seconds:n,weight:nil) }
    }
    /// Events that are not worth a disk write of their own. `setWorkWeight` is the displayed
    /// weight while it is still being typed — one keystroke is not a fact about the workout —
    /// and it is carried to disk by the next event that is (a log, a skip, a tick).
    private static let unpersisted: (Event) -> Bool = { event in
        if case .setWorkWeight = event { return true }
        return false
    }

    @discardableResult mutating func apply(_ event: Event, now: Date) -> [Effect] {
        var effects: [Effect] = []
        let oldPhase = phase
        switch event {
        case let .logSet(i, result), let .editSet(i, result):
            guard session.steps.indices.contains(i), valid(result) else { return [] }
            let isEdit: Bool
            if case .editSet = event { isEdit = true } else { isEdit = false }
            let previousStatus = session.steps[i].status
            // D27 v1.1: editSet now also recovers a skipped step, not only a logged one.
            if isEdit && previousStatus == .pending { return [] }
            if !isEdit && phase == .completed { return [] }
            active.session.steps[i].result = cleaned(result, step: i)
            active.session.steps[i].status = .logged
            if !isEdit {
                active.session.steps[i].loggedAt = now
            } else if previousStatus == .skipped {
                // Recovering a skip: the old skip timestamp no longer describes anything real.
                active.session.steps[i].loggedAt = now
            }
            reevaluateAdvice(session.steps[i].exerciseIndex)
            if !isEdit {
                active.lastCompletedStep = i
                effects.append(.playFeedback(.logged))
                effects += cancelWork(); effects += advance(after: i, now: now, skipped: false)
            }
        case let .skipSet(i):
            guard session.steps.indices.contains(i), phase != .completed else { return [] }
            effects += cancelWork()
            active.session.steps[i].status = .skipped; active.session.steps[i].result = nil; active.session.steps[i].loggedAt = now
            active.lastCompletedStep = i
            reevaluateAdvice(session.steps[i].exerciseIndex)
            effects += advance(after: i, now: now, skipped: true)
        case let .skipExercise(e):
            guard session.exercises.indices.contains(e), let current = currentStep else { return [] }
            let pending = session.steps.indices.filter { session.steps[$0].exerciseIndex == e && session.steps[$0].status == .pending }
            guard !pending.isEmpty else { return [] }
            effects += cancelWork()
            active.blockDone = nil
            for i in pending { active.session.steps[i].status = .skipped; active.session.steps[i].result = nil; active.session.steps[i].loggedAt = now }
            reevaluateAdvice(e)
            // A block this ended advances from its last step, so the walk starts as it does after
            // any block's last set — logged or skipped, the next machine is no closer (§6.3,
            // §6.55). Until v1.12 it drew the walk's strip with no rest under it, so its ring
            // filled with no alert.
            let block = session.steps[pending[0]].blockIndex
            let ended = !session.steps.contains { $0.blockIndex == block && $0.status == .pending }
            let from = ended ? session.steps.indices.last { session.steps[$0].blockIndex == block } ?? current : current
            effects += advance(after: from, now: now, skipped: true)
        case let .jumpTo(i):
            guard session.steps.indices.contains(i), phase != .completed else { return [] }
            effects += cancelWork()
            if case .resting = phase { active.lastRestEndedAt = now }
            active.blockDone = nil
            enterWorking(i, now: now)
        case let .undoLog(i):
            // Valid only for the single most recently logged-or-skipped step, and only until
            // something else has been logged or skipped after it (D23 v1.1).
            guard phase != .completed, active.lastCompletedStep == i,
                  let status = session.steps[safe: i]?.status, status != .pending
            else { return [] }
            effects += cancelWork()
            let e = session.steps[i].exerciseIndex
            active.blockDone = nil
            active.lastCompletedStep = nil
            active.session.steps[i].status = .pending
            active.session.steps[i].result = nil
            active.session.steps[i].loggedAt = nil
            if session.exercises.indices.contains(e) { active.session.exercises[e].advice = nil }
            enterWorking(i, now: now)
        case let .adjustRest(seconds):
            // The warm-up is as adjustable as a rest between sets, and for the same reason. D82
            // (v1.10): the walk is not — its end is the plan's minimum, and it counts up past it.
            guard case var .resting(rest) = phase, rest.kind != .betweenExercises else { return [] }
            rest.endsAt = rest.endsAt.addingTimeInterval(Double(seconds))
            effects.append(.cancelNotification(id: .rest))
            if rest.endsAt <= now { active.lastRestEndedAt = rest.endsAt; enterWorking(rest.nextStep, now: now) }
            else { active.phase = .resting(rest); effects.append(.scheduleNotification(id: .rest, at: rest.endsAt, body: nextBody(rest.nextStep))) }
        case .skipRest, .restElapsed:
            guard case let .resting(rest) = phase else { return [] }
            // D82: a count-up has nothing to skip; Log set or Start timer ends the walk.
            if case .skipRest = event, rest.kind == .betweenExercises { return [] }
            if case .restElapsed = event {
                guard now >= rest.endsAt else { return [] }
                if now.timeIntervalSince(rest.endsAt) < 1 { effects.append(.playAlert(.end)) }
                active.lastRestEndedAt = rest.endsAt
            } else { active.lastRestEndedAt = now }
            enterWorking(rest.nextStep, now: now)
        case let .startTimer(i):
            // v1.1 (D22): a timed set can be started straight out of rest, exactly as a reps set
            // can be logged out of it. Without this the one primary button would do nothing
            // whenever the step waiting on the other side of a rest happens to be timed.
            if case let .resting(rest) = phase, rest.nextStep == i, !active.timerRunning,
               session.target(at: i)?.work.isTimed == true {
                active.lastRestEndedAt = now
                enterWorking(i, now: now)
            }
            guard case let .working(current) = phase, current == i, !active.timerRunning, let target = session.target(at: i), target.work.isTimed else { return [] }
            active.session.steps[i].startedAt = now; active.timerRunning = true; active.deliveredBeeps = []
            // D82 (v1.10): starting the set ends the walk, as logging one does (§4.6).
            active.blockDone = nil
            effects += AlertIdentifier.work.map { .cancelNotification(id: $0) }
            switch target.work {
            case let .duration(n):
                let end = now.addingTimeInterval(Double(n))
                let line = StepCard.stepLine(session: session, step: i, wording: settings.wording)
                effects.append(.scheduleNotification(id: .setEnd, at: end, body: "Time!" + (line.map { " " + $0 } ?? "")))
                if let w = target.warning { effects.append(.scheduleNotification(id: .setWarning, at: end.addingTimeInterval(-Double(w)), body: "\(w) s left")) }
            case let .openDuration(minimum): if let minimum { effects.append(.scheduleNotification(id: .setMinimum, at: now.addingTimeInterval(Double(minimum)), body: "\(minimum) s reached")) }
            case .reps: break
            }
        case let .stopTimer(i), let .timerDone(i), let .timerElapsed(i):
            guard case let .working(current) = phase, current == i, active.timerRunning, let start = session.steps[safe: i]?.startedAt, let target = session.target(at: i) else { return [] }
            let seconds: Int
            switch (event, target.work) {
            case (.stopTimer, .openDuration), (.timerDone, .duration): seconds = wholeSeconds(now.timeIntervalSince(start))
            case let (.timerElapsed, .duration(n)):
                guard now >= start.addingTimeInterval(Double(n)) else { return [] }; seconds = n
            default: return []
            }
            // Timed work logs the same prefilled/edited weight displayed by the card.
            effects += apply(.logSet(step: i, result: .duration(seconds: seconds, weight: active.workWeight)), now: now).filter { $0 != .persist }
        case .dismissBlockDone:
            guard active.blockDone != nil else { return [] }
            active.blockDone = nil
        case let .deferExercise(e):
            guard let moved = self.defer(exercise: e, now: now) else { return [] }
            effects += moved
        case let .substituteExercise(e, name, weight):
            guard let moved = substitute(exercise: e, name: name, weight: weight, now: now) else { return [] }
            effects += moved
        case let .renameExercise(e, name):
            guard session.exercises.indices.contains(e), let name = TargetGrammar.cleanName(name) else { return [] }
            active.session.exercises[e].name = name
        case let .setWorkWeight(i, weight):
            guard case let .working(current) = phase, current == i, let step = session.steps[safe: i],
                  weight.map(TargetGrammar.isWeight) ?? true else { return [] }
            active.workWeight = session.exercises[safe: step.exerciseIndex]?.bodyweight == true ? nil : weight
        case .finish:
            guard phase != .completed else { return [] }
            effects += cancelWork()
            for i in session.steps.indices where session.steps[i].status == .pending { active.session.steps[i].status = .skipped; active.session.steps[i].loggedAt = now }
            effects += complete(now: now)
        }
        if case .resting = oldPhase, phase != oldPhase, !effects.contains(.cancelNotification(id: .rest)) { effects.insert(.cancelNotification(id: .rest), at: 0) }
        if !Self.unpersisted(event) { effects.append(.persist) }
        return effects
    }
    /// D28 (v1.1): moves the whole block containing `e` — a superset moves together, since its
    /// members are one thing you do at one station — to after the day's last pending step, and
    /// carries on with whatever is now next. Returns nil when there is nothing to do: no pending
    /// steps in that block, or nothing pending outside it to move behind.
    ///
    /// The step array is reordered in place, so every index that points into it (the phase,
    /// `lastCompletedStep`) is remapped through the permutation. `blockIndex` is deliberately
    /// left alone — it identifies the block, and rewriting it would break `blockDone`, the
    /// block durations and the rest resolution; views order blocks by where their steps now sit.
    private mutating func `defer`(exercise e: Int, now: Date) -> [Effect]? {
        guard phase != .completed, session.exercises.indices.contains(e) else { return nil }
        let steps = session.steps
        guard let any = steps.firstIndex(where: { $0.exerciseIndex == e }) else { return nil }
        let block = steps[any].blockIndex
        let moving = steps.indices.filter { steps[$0].blockIndex == block }
        guard moving.contains(where: { steps[$0].status == .pending }) else { return nil }
        guard let lastPendingElsewhere = steps.indices.last(where: {
            steps[$0].blockIndex != block && steps[$0].status == .pending
        }) else { return nil }

        // The new order: everything else, with the moved block reinserted after the last
        // pending step that is staying put.
        var order = steps.indices.filter { steps[$0].blockIndex != block }
        guard let seam = order.firstIndex(of: lastPendingElsewhere) else { return nil }
        order.insert(contentsOf: moving, at: seam + 1)

        var remap: [Int: Int] = [:]
        for (new, old) in order.enumerated() { remap[old] = new }
        active.session.steps = order.map { steps[$0] }

        let current = currentStep.flatMap { remap[$0] }
        active.blockDone = nil
        let effects = cancelWork()
        if let last = active.lastCompletedStep { active.lastCompletedStep = remap[last] }
        // Whatever we were on has moved; carry on with the first pending step from the top.
        // The caller's tail adds `.persist` and cancels a rest this interrupted.
        let next = active.session.steps.indices.first { active.session.steps[$0].status == .pending }
            ?? current
        if let next { enterWorking(next, now: now) }
        return effects
    }

    /// D42 (v1.3): the exercise's remaining sets become sets of `name`. Logged and skipped
    /// sets stay what they were; step order and `blockIndex` do not change, so a rest that is
    /// running keeps running and the position in the day is the same.
    ///
    /// With nothing done yet the exercise is renamed in place. With something done, a second
    /// `SessionExercise` is appended (`replaces` pointing back) and the pending steps are
    /// re-pointed to it, so history says "Bench Press 1 set, Dumbbell Press 2 sets" rather than
    /// crediting one exercise with the other's work. The same name with a weight is just a
    /// weight change for the remaining sets. Returns nil when there is nothing to do.
    private mutating func substitute(exercise e: Int, name: String, weight: Double?, now: Date) -> [Effect]? {
        guard phase != .completed, session.exercises.indices.contains(e),
              weight.map(TargetGrammar.isWeight) ?? true, let newName = TargetGrammar.cleanName(name) else { return nil }
        let pending = session.steps.indices.filter {
            session.steps[$0].exerciseIndex == e && session.steps[$0].status == .pending
        }
        guard !pending.isEmpty else { return nil }
        let original = session.exercises[e]
        let sameName = normalized(newName) == normalized(original.name)
        guard !sameName || weight != nil else { return nil }

        var replacement = original
        replacement.name = newName
        replacement.advice = nil
        if !sameName { replacement.substitutedFor = original.substitutedFor ?? original.name }
        if let weight {
            for i in replacement.targets.indices { replacement.targets[i].weight = weight }
            replacement.bodyweight = false
        } else if !sameName,
                  let last = ExerciseHistory.last(name: newName, units: session.units, sessions: history),
                  let known = last.exercises.first(where: { normalized($0.name) == normalized(newName) }) {
            // The substitute keeps its own identity (D8), which includes whether it is loaded.
            replacement.bodyweight = known.bodyweight
        }

        let somethingDone = session.steps.contains { $0.exerciseIndex == e && $0.status != .pending }
        if somethingDone && !sameName {
            replacement.id = UUID()
            replacement.replaces = e
            active.session.exercises.append(replacement)
            let index = active.session.exercises.count - 1
            for i in pending { active.session.steps[i].exerciseIndex = index }
            active.session.exercises[e].advice = nil
        } else {
            active.session.exercises[e] = replacement
        }

        // The card that is up re-reads its prefill from the substitute's own history. Its
        // timing is untouched: the set began when the card appeared, whatever it is now called.
        var effects: [Effect] = []
        if case let .working(current) = phase, pending.contains(current) {
            if active.timerRunning { effects += cancelWork() }
            active.workWeight = Prefill.values(session: session, step: current, history: history,
                                               settings: settings).weight
        }
        return effects
    }

    /// Call on foreground entry with replayMissed=false before ticking; missed notifications are not replayed.
    mutating func beepDue(now: Date, replayMissed: Bool = true) -> [TimerBeep] {
        guard case let .working(i) = phase, active.timerRunning, let start = session.steps[safe: i]?.startedAt, let target = session.target(at: i) else { return [] }
        var moments: [(TimerBeep,Date)] = []
        switch target.work {
        case let .duration(n):
            if let w = target.warning { moments.append((.warning, start.addingTimeInterval(Double(n-w)))) }
            moments.append((.end, start.addingTimeInterval(Double(n))))
        case let .openDuration(n): if let n { moments.append((.minimum, start.addingTimeInterval(Double(n)))) }
        case .reps: break
        }
        var due: [TimerBeep] = []
        for (beep, date) in moments where date <= now && !active.deliveredBeeps.contains(beep) {
            active.deliveredBeeps.insert(beep)
            if replayMissed { due.append(beep) }
        }
        return due
    }
}
