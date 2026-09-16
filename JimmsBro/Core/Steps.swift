import Foundation

enum StepBuilder {
    static func flatten(_ day: Day) -> [Step] {
        var result: [Step] = []
        var start = 0, block = 0
        while start < day.exercises.count {
            var end = start + 1
            if let group = day.exercises[start].group {
                while end < day.exercises.count && day.exercises[end].group == group { end += 1 }
            }
            let rounds = day.exercises[start..<end].map { $0.sets.count }.max() ?? 0
            for round in 0..<rounds {
                let members = (start..<end).filter { round < day.exercises[$0].sets.count }
                for e in members {
                    let dropCount = day.exercises[e].sets[round].drops.count
                    for drop in 0...dropCount {
                        result.append(Step(exerciseIndex: e, setIndex: round, dropIndex: drop, blockIndex: block,
                                           isLastInRound: e == members.last && drop == dropCount,
                                           isLastInBlock: round == rounds - 1 && e == members.last && drop == dropCount))
                    }
                }
            }
            start = end; block += 1
        }
        return result
    }
}
func flatten(day: Day) -> [Step] { StepBuilder.flatten(day) }

/// `.blockDone` (v1.1; was `.transition`) means the block containing `index` has finished and
/// `next` starts a different block — SPEC §6.3, §4.7. In v1.2 it carries a rest of its own:
/// walking to the next machine takes as long as a rest does, and v1.1 allowed it none.
enum Advance: Equatable { case completed, blockDone(rest: Int), rest(Int) }
enum RestResolution {
    /// D82 (v1.10, §6.3): the walk between exercises — the plan's `restBetweenExercises`, then
    /// the setting. Zero from either means straight through.
    static func walk(plan: Int?, settings: Settings) -> Int {
        max(0, plan ?? settings.transitionRestSeconds)
    }
    static func after(_ index: Int, next: Int?, steps: [SessionStep], exercises: [SessionExercise],
                      settings: Settings = Settings(), restBetweenExercises: Int? = nil) -> Advance {
        guard let next else { return .completed }
        guard let step = steps[safe: index], let nextStep = steps[safe: next] else { return .completed }
        if nextStep.blockIndex < step.blockIndex || (step.isLastInBlock && step.blockIndex != nextStep.blockIndex) {
            // D33: the gap between two exercises is about the room, not about the set that
            // just ended, so it comes from the plan or the setting rather than the set's rest.
            return .blockDone(rest: walk(plan: restBetweenExercises, settings: settings))
        }
        guard step.isLastInRound else { return .rest(0) }
        guard let exercise = exercises[safe: step.exerciseIndex], let target = exercise.targets[safe: step.setIndex] else { return .rest(0) }
        return .rest(max(0, exercise.group == nil ? target.restSeconds : target.groupRestSeconds ?? target.restSeconds))
    }
}
extension Session {
    /// The day as the session will do it. D44 (v1.3): when the plan carries a progression and
    /// today falls in one of its weeks, that week's targets are written into the snapshot —
    /// D7 holds, the session records what it was asked to do — and the exercises it touched
    /// carry the week, so the chip can say so.
    static func start(plan: Plan, dayIndex: Int, now: Date, calendar: Calendar = .current) -> Session? {
        guard var day = plan.days[safe: dayIndex] else { return nil }
        // D53 (v1.5): each entry's own step, which in calendar mode is the same week for all.
        var steps: [Int: Int] = [:]
        if let progression = plan.progression {
            let applied = progression.apply(to: day, on: now, calendar: calendar)
            day = applied.day
            steps = applied.steps
        }
        var session = Session(planId: plan.id, planName: plan.name, dayName: day.name, units: plan.units, startedAt: now,
                       exercises: day.exercises.map { SessionExercise(name: $0.name, group: $0.group, notes: $0.notes, repRange: $0.repRange, bodyweight: $0.bodyweight, targets: $0.sets) },
                       steps: flatten(day: day).map { SessionStep(exerciseIndex: $0.exerciseIndex, setIndex: $0.setIndex, dropIndex: $0.dropIndex, blockIndex: $0.blockIndex, isLastInRound: $0.isLastInRound, isLastInBlock: $0.isLastInBlock) })
        guard !steps.isEmpty, let lowest = steps.values.min() else { return session }
        for (index, step) in steps { session.exercises[index].progressionWeek = step }
        // The session's own number is the lowest of its exercises', which is what Home says.
        session.progressionWeek = lowest
        session.progressionWeeks = plan.progression?.weeks
        session.progressionMode = plan.progression?.mode
        return session
    }
    /// `reserve` is D51's effort target (v1.5); a drop has none.
    func target(at index: Int) -> (work: WorkTarget, weight: Double?, warning: Int?, reserve: Int?)? {
        guard let step = steps[safe: index], let exercise = exercises[safe: step.exerciseIndex], let target = exercise.targets[safe: step.setIndex] else { return nil }
        if step.dropIndex == 0 { return (target.work, exercise.bodyweight ? nil : target.weight, target.warningBeepSeconds, target.inReserve) }
        guard let drop = target.drops[safe: step.dropIndex - 1] else { return nil }
        return (drop.work, exercise.bodyweight ? nil : drop.weight, nil, nil)
    }
}
