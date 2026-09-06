import Foundation

struct PrefillValues: Equatable {
    var weight: Double?
    var reps: Int?
    var seconds: Int?
    var lastWeight: Double?
    var suggestedWeight: Double?
    var showsWeight: Bool
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
    static func lastSteps(session: Session, step index: Int, history: [Session]) -> (session: Session, steps: [SessionStep])? {
        guard let step = session.steps[safe:index], let e = session.exercises[safe:step.exerciseIndex], let last = ExerciseHistory.last(name:e.name,units:session.units,sessions:history.filter { $0.id != session.id && $0.startedAt < session.startedAt }) else { return nil }
        return (last, ExerciseHistory.steps(name:e.name,session:last))
    }
    static func historicalResult(session: Session, step index: Int, history: [Session]) -> SetResult? {
        guard let step = session.steps[safe:index], let last = lastSteps(session:session,step:index,history:history) else { return nil }
        let matching = last.steps.first { $0.setIndex == step.setIndex && $0.dropIndex == step.dropIndex }
        if let matching, matching.status == .logged { return matching.result }
        if step.dropIndex > 0 { return nil }
        // Missing/skipped main set indices use the last logged main set.
        return last.steps.last { $0.status == .logged && $0.dropIndex == step.dropIndex }?.result
    }
    static func historicalWeight(session: Session, step index: Int, history: [Session]) -> Double? {
        guard let step = session.steps[safe:index], let last = lastSteps(session:session,step:index,history:history) else { return nil }
        let matching = last.steps.first { $0.setIndex == step.setIndex && $0.dropIndex == step.dropIndex && $0.status == .logged }
        if let weight = matching?.result?.weight { return weight }
        guard step.dropIndex == 0 else { return nil }
        return last.steps.last { $0.status == .logged && $0.dropIndex == 0 && $0.result?.weight != nil }?.result?.weight
    }
    static func values(session: Session, step index: Int, history: [Session]) -> PrefillValues {
        guard let step = session.steps[safe:index], let e = session.exercises[safe:step.exerciseIndex], let target = session.target(at:index) else { return PrefillValues(showsWeight:false) }
        let last = historicalResult(session:session,step:index,history:history)
        let lastWeight = historicalWeight(session:session,step:index,history:history)
        let previousSteps = session.steps.prefix(index).filter { $0.status == .logged && $0.exerciseIndex == step.exerciseIndex }
        let weight: Double?
        if e.bodyweight { weight = nil }
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
        let reps = weight == (e.bodyweight ? nil : last?.weight) ? last?.reps ?? targetReps(target.work) : targetReps(target.work)
        let seconds: Int?
        if case let .duration(n) = target.work { seconds = last?.seconds ?? n } else { seconds = nil }
        var suggestion: Double?
        if let lastSession = lastSteps(session:session,step:index,history:history)?.session,
           let advice = lastSession.exercises.first(where: { normalized($0.name) == normalized(e.name) })?.advice {
            switch advice { case let .increase(w), let .decrease(w): suggestion = w; default: break }
        }
        return PrefillValues(weight:weight,reps:reps,seconds:seconds,lastWeight:e.bodyweight ? nil : lastWeight,suggestedWeight:e.bodyweight ? nil : suggestion,showsWeight:!e.bodyweight)
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
