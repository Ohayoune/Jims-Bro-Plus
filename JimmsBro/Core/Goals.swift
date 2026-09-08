import Foundation

/// D54 (v1.5): a goal per exercise — a target you name, with an optional date. History shows
/// how close you are, the Summary says when a workout reaches it, and the progression prompt
/// tells the chatbot to plan towards it. Independent of any plan: a goal outlives the plan
/// and the progression it was reached under.
struct Goal: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Matched to sessions by normalised name (§6.9).
    var exerciseName: String
    /// The goal's units; sessions in the other unit never count (D10: the app never converts).
    var units: WeightUnit
    var target: GoalTarget
    /// Optional: "by 1 Dec". Said, never enforced.
    var by: Date?
    var createdAt: Date
    /// The first workout that met it, if any — and which one, so the Summary can say so.
    var reachedAt: Date?
    var reachedSessionId: UUID?
    enum CodingKeys: String, CodingKey {
        case id, exerciseName, units, target, by, createdAt, reachedAt, reachedSessionId
    }
}

enum GoalTarget: Codable, Equatable {
    /// A weight lifted for at least this many reps in one set.
    case weight(Double, reps: Int)
    /// A hold of at least this long.
    case seconds(Int)
    /// A set of at least this many reps — a bodyweight goal.
    case reps(Int)
}

/// How far along a goal is, from the best logged set that counts.
struct GoalProgress: Equatable {
    /// "82.5 kg × 5", "0:50", "8 reps"; nil when nothing counts yet.
    var best: String?
    /// 0…1 of the target.
    var fraction: Double
    var reached: Bool
}

enum Goals {
    /// Whether one logged set meets the goal.
    static func meets(_ goal: Goal, _ result: SetResult) -> Bool {
        switch goal.target {
        case let .weight(weight, reps):
            guard let done = result.reps, let lifted = result.weight else { return false }
            return done >= reps && lifted + 0.001 >= weight
        case let .seconds(seconds):
            return (result.seconds ?? 0) >= seconds
        case let .reps(reps):
            return (result.reps ?? 0) >= reps
        }
    }

    /// The logged results of the goal's exercise, in its units, across completed sessions.
    static func results(_ goal: Goal, sessions: [Session]) -> [SetResult] {
        sessions.filter { $0.endedAt != nil && $0.units == goal.units }
            .flatMap { ExerciseHistory.steps(name: goal.exerciseName, session: $0) }
            .filter { $0.status == .logged }
            .compactMap(\.result)
    }

    /// The best set that counts against the goal, and how far along it is. For a weight goal
    /// only sets at or above its reps count — a heavier set for fewer reps is not the goal.
    static func progress(_ goal: Goal, sessions: [Session]) -> GoalProgress {
        let results = results(goal, sessions: sessions)
        switch goal.target {
        case let .weight(weight, reps):
            let counting = results.filter { ($0.reps ?? 0) >= reps && $0.weight != nil }
            guard let best = counting.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }), let lifted = best.weight else {
                return GoalProgress(best: nil, fraction: 0, reached: false)
            }
            return GoalProgress(best: "\(TargetText.number(lifted)) \(goal.units.rawValue) × \(best.reps ?? reps)",
                                fraction: min(1, weight > 0 ? lifted / weight : 1),
                                reached: lifted + 0.001 >= weight)
        case let .seconds(seconds):
            guard let best = results.compactMap(\.seconds).max() else {
                return GoalProgress(best: nil, fraction: 0, reached: false)
            }
            return GoalProgress(best: TargetText.time(best), fraction: min(1, Double(best) / Double(max(seconds, 1))),
                                reached: best >= seconds)
        case let .reps(reps):
            guard let best = results.compactMap(\.reps).max() else {
                return GoalProgress(best: nil, fraction: 0, reached: false)
            }
            return GoalProgress(best: "\(best) rep\(best == 1 ? "" : "s")", fraction: min(1, Double(best) / Double(max(reps, 1))),
                                reached: best >= reps)
        }
    }

    /// After a workout, every goal it reached for the first time is marked with the workout.
    /// Returns them, so the Summary can say so. A goal already reached stays reached.
    @discardableResult
    static func markReached(_ goals: inout [Goal], after session: Session) -> [Goal] {
        var reached: [Goal] = []
        for index in goals.indices where goals[index].reachedAt == nil && goals[index].units == session.units {
            let goal = goals[index]
            let steps = ExerciseHistory.steps(name: goal.exerciseName, session: session)
            guard steps.contains(where: { $0.status == .logged && $0.result.map { meets(goal, $0) } == true }) else { continue }
            goals[index].reachedAt = session.startedAt
            goals[index].reachedSessionId = session.id
            reached.append(goals[index])
        }
        return reached
    }

    // MARK: - Words

    /// "100 kg × 5", "1:00", "10 reps".
    static func targetText(_ goal: Goal) -> String {
        switch goal.target {
        case let .weight(weight, reps): return "\(TargetText.number(weight)) \(goal.units.rawValue) × \(reps)"
        case let .seconds(seconds): return TargetText.time(seconds)
        case let .reps(reps): return "\(reps) rep\(reps == 1 ? "" : "s")"
        }
    }

    /// "100 kg × 5 · best 82.5 kg × 5 · by 1 Dec", "100 kg × 5 · nothing logged yet",
    /// "100 kg × 5 · reached 3 Sep".
    static func line(_ goal: Goal, progress: GoalProgress) -> String {
        var parts = [targetText(goal)]
        if let reachedAt = goal.reachedAt {
            parts.append("reached \(short(reachedAt))")
        } else {
            parts.append(progress.best.map { "best \($0)" } ?? "nothing logged yet")
            if let by = goal.by { parts.append("by \(short(by))") }
        }
        return parts.joined(separator: " · ")
    }

    /// The Summary's line, in the colour reserved for "this happened" (§4.0).
    static func reachedLine(_ goal: Goal) -> String { "Goal reached: \(goal.exerciseName) \(targetText(goal))" }

    /// The progression prompt's line: "- Barbell Bench Press: 100 kg × 5 by 2026-12-01".
    static func promptLine(_ goal: Goal) -> String {
        var text = "- \(goal.exerciseName): \(targetText(goal))"
        if let by = goal.by { text += " by \(iso(by))" }
        return text
    }

    /// "3 Sep" — stable across locales, so the words are a unit test.
    static func short(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
