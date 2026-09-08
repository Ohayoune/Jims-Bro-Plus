import Foundation

enum ProgressionAdvice {
    /// `increment` is D35's smallest loadable change (v1.2). It defaults to `weightStep` so the
    /// old two-argument shape keeps its old meaning, and passing it is what stops the app from
    /// suggesting 134 lb on a bar that can only make 135.
    static func evaluate(exercise: SessionExercise, steps: [SessionStep], weightStep: Double,
                         increment: Double? = nil) -> Advice? {
        guard let range = exercise.repRange, range.min > 0, range.max >= range.min, weightStep.isFinite, weightStep > 0 else { return nil }
        let logged = steps.filter { $0.status == .logged && $0.dropIndex == 0 }
        guard !logged.isEmpty else { return nil }
        let results = logged.compactMap(\.result)
        guard results.count == logged.count, results.allSatisfy({ $0.reps != nil }) else { return nil }
        let weights = results.map { exercise.bodyweight ? nil : $0.weight }
        guard let first = weights.first, weights.allSatisfy({ $0 == first }) else { return nil }
        let achieved = results.reduce(0.0) { $0 + Double($1.reps ?? 0) }
        let grid = increment ?? weightStep
        if achieved >= Double(results.count) * Double(range.max) - 1 {
            return first.map {
                .increase(to: WeightRounding.heavier(than: $0, target: $0 + weightStep, increment: grid))
            } ?? .increaseLoad
        }
        if achieved < Double(results.count) * Double(range.min) {
            return first.map {
                .decrease(to: WeightRounding.lighter(than: $0, target: $0 - weightStep, increment: grid))
            } ?? .decreaseLoad
        }
        return nil
    }
    static func message(_ advice: Advice, range: RepRange, loggedSets: Int, currentWeight: Double?, units: WeightUnit) -> String {
        let r = "\(range.min)–\(range.max)"
        switch advice {
        case let .increase(w): return "All sets hit the top of \(r). Try \(TargetText.number(w)) \(units.rawValue) next time."
        case .increaseLoad: return "You've completed the range. Add load or a harder variation."
        case let .decrease(w): return "Below \(r) across \(loggedSets) sets. Try \(TargetText.number(w)) \(units.rawValue) next time, or keep \(TargetText.number(currentWeight ?? 0)) \(units.rawValue) and build up."
        case .decreaseLoad: return "Below the range. Try an easier variation or fewer sets."
        }
    }
}
enum SessionStats {
    static func duration(_ session: Session, now: Date = Date()) -> TimeInterval { max(0, (session.endedAt ?? now).timeIntervalSince(session.startedAt)) }
    static func volume(_ steps: [SessionStep]) -> Double {
        steps.reduce(0) { total, step in
            guard step.status == .logged, case let .reps(n,w)? = step.result, let w, w.isFinite else { return total }
            return total + Double(n) * w
        }
    }
    static func loggedCount(_ session: Session) -> Int { session.steps.filter { $0.status == .logged }.count }
    static func averageSetSeconds(_ session: Session) -> Double? {
        let values = session.steps.compactMap(\.setSeconds).map(Double.init)
        return mean(values)
    }
    static func blockDuration(_ block: Int, session: Session) -> Int? {
        let steps = session.steps.filter { $0.blockIndex == block }
        guard !steps.isEmpty, !steps.contains(where: { $0.status == .pending }), steps.contains(where: { $0.status == .logged }), let end = steps.compactMap(\.loggedAt).max() else { return nil }
        let start = session.steps.filter { $0.blockIndex < block }.compactMap(\.loggedAt).max() ?? session.startedAt
        return wholeSeconds(end.timeIntervalSince(start))
    }
    static func best(_ steps: [SessionStep]) -> SetResult? {
        let reps = steps.filter { $0.status == .logged }.compactMap(\.result).filter { $0.reps != nil }
        let weighted = reps.filter { $0.weight != nil }
        return (weighted.isEmpty ? reps : weighted).max { a,b in
            if (a.weight ?? 0) != (b.weight ?? 0) { return (a.weight ?? 0) < (b.weight ?? 0) }
            return (a.reps ?? 0) < (b.reps ?? 0)
        }
    }
    /// D30 (v1.1): the steps of `session` that beat everything logged for that exercise before
    /// it — a personal record. Compared the way `best` compares: heaviest first, ties broken by
    /// reps; a weightless exercise compares reps alone, and a timed one seconds held. Only
    /// earlier sessions in the same units count, since the app never converts (D10).
    ///
    /// Walked in log order with a running best, so a session that sets a record twice marks both,
    /// and a set that merely equals the old best marks neither.
    static func personalRecords(session: Session, history: [Session]) -> Set<Int> {
        var records: Set<Int> = []
        let earlier = history.filter { $0.id != session.id && $0.startedAt < session.startedAt
                                       && $0.units == session.units }
        for exercise in Set(session.steps.map(\.exerciseIndex)) {
            guard let name = session.exercises[safe: exercise]?.name else { continue }
            var best = ExerciseHistory.bestScore(name: name, sessions: earlier)
            let steps = session.steps.indices
                .filter { session.steps[$0].exerciseIndex == exercise && session.steps[$0].status == .logged }
                .sorted { (session.steps[$0].loggedAt ?? .distantPast)
                          < (session.steps[$1].loggedAt ?? .distantPast) }
            for index in steps {
                guard let score = score(session.steps[index].result) else { continue }
                // Nothing to beat is not a record: the first time you do an exercise, every
                // set would otherwise be a PR, which tells you nothing.
                guard let current = best else { best = score; continue }
                if current.lexicographicallyPrecedes(score) {
                    records.insert(index)
                    best = score
                }
            }
        }
        return records
    }

    /// A result as one comparable value: weight then reps, or seconds for timed work. `nil`
    /// when the result is not comparable to the others (a rep set against a hold, say).
    static func score(_ result: SetResult?) -> [Double]? {
        guard let result else { return nil }
        if let seconds = result.seconds { return [0, Double(seconds)] }
        guard let reps = result.reps else { return nil }
        return [result.weight ?? 0, Double(reps)]
    }

    static func previousSession(for name: String, units: WeightUnit, before: Date, sessions: [Session]) -> Session? {
        ExerciseHistory.last(name: name, units: units, sessions: sessions.filter { $0.startedAt < before })
    }
    /// SPEC §4.9 (v1.1): one comparison per exercise, in words. v1 printed both sessions'
    /// raw sets — "10, 8@60 · last 10, 9@60 · kg" — and left the reader to do the subtraction.
    /// The set-by-set table only appears when no single sentence is true of the whole exercise.
    static func comparison(for name: String, session: Session, history: [Session]) -> ExerciseComparison {
        let current = ExerciseHistory.steps(name: name, session: session).filter { $0.status == .logged }
        guard let last = previousSession(for: name, units: session.units, before: session.startedAt,
                                         sessions: history) else {
            return ExerciseComparison(headline: "First time", rows: [])
        }
        let previous = ExerciseHistory.steps(name: name, session: last).filter { $0.status == .logged }
        guard !current.isEmpty, !previous.isEmpty else {
            return ExerciseComparison(headline: "Nothing logged", rows: [])
        }

        let unit = session.units.rawValue
        let nowResults = current.compactMap(\.result)
        let thenResults = previous.compactMap(\.result)

        // Timed work compares held seconds, not reps.
        if nowResults.allSatisfy({ $0.seconds != nil }), thenResults.allSatisfy({ $0.seconds != nil }) {
            let now = nowResults.compactMap(\.seconds).reduce(0, +)
            let then = thenResults.compactMap(\.seconds).reduce(0, +)
            return ExerciseComparison(headline: change(now - then, unit: "s", noun: "held"), rows: [])
        }

        let nowWeight = single(nowResults.map(\.weight))
        let thenWeight = single(thenResults.map(\.weight))
        let nowReps = nowResults.compactMap(\.reps).reduce(0, +)
        let thenReps = thenResults.compactMap(\.reps).reduce(0, +)

        // One weight this time, one weight last time: a sentence covers the whole exercise.
        if let nowWeight, let thenWeight {
            let moved = nowWeight - thenWeight
            if abs(moved) < 0.05 {
                return ExerciseComparison(headline: reps(nowReps - thenReps, suffix: " at the same weight"),
                                          rows: [])
            }
            var headline = (moved > 0 ? "+" : "−") + TargetText.number(abs(moved)) + " \(unit)"
            if nowReps != thenReps { headline += ", " + reps(nowReps - thenReps, suffix: "").lowercasedFirst }
            return ExerciseComparison(headline: headline, rows: [])
        }
        // Bodyweight, both times: reps are the whole story.
        if nowWeight == nil, thenWeight == nil,
           nowResults.allSatisfy({ $0.weight == nil }), thenResults.allSatisfy({ $0.weight == nil }) {
            return ExerciseComparison(headline: reps(nowReps - thenReps, suffix: ""), rows: [])
        }

        // The weights varied within a session, so no one sentence is true: show the sets.
        let rows = zip(nowResults, thenResults).map { now, then in
            "\(short(then)) → \(short(now))"
        }
        let extra = nowResults.dropFirst(thenResults.count).map { short($0) }
        let volumeNow = volume(current), volumeThen = volume(previous)
        var headline = "Sets varied"
        if volumeNow > 0, volumeThen > 0 {
            let moved = volumeNow - volumeThen
            headline = abs(moved) < 0.5
                ? "Same volume as last time"
                : "Volume \(moved > 0 ? "up" : "down") \(TargetText.grouped(abs(moved))) \(unit)"
        }
        return ExerciseComparison(headline: headline, rows: rows + extra)
    }

    /// The one weight every set shared, or nil when they differed (or there was none).
    private static func single(_ weights: [Double?]) -> Double? {
        let values = weights.compactMap { $0 }
        guard values.count == weights.count, let first = values.first,
              values.allSatisfy({ abs($0 - first) < 0.05 }) else { return nil }
        return first
    }

    private static func short(_ result: SetResult) -> String {
        let value = result.reps.map(String.init) ?? result.seconds.map(TargetText.time) ?? "–"
        return value + (result.weight.map { " @ " + TargetText.number($0) } ?? "")
    }

    private static func reps(_ delta: Int, suffix: String) -> String {
        guard delta != 0 else { return "Same as last time" }
        let noun = abs(delta) == 1 ? "rep" : "reps"
        return "\(abs(delta)) \(delta > 0 ? "more" : "fewer") \(noun)\(suffix)"
    }

    private static func change(_ delta: Int, unit: String, noun: String) -> String {
        guard delta != 0 else { return "Same as last time" }
        return "\(abs(delta)) \(unit) \(delta > 0 ? "longer" : "shorter") \(noun)"
    }
}

/// SPEC §4.9 (v1.1): the Summary's per-exercise comparison, resolved as data.
struct ExerciseComparison: Equatable {
    /// The sentence: "2 more reps at the same weight", "+2.5 kg", "First time".
    var headline: String
    /// "10 @ 60 → 10 @ 62.5", one per set, only when the headline cannot cover the exercise.
    var rows: [String]
}

extension String {
    /// "2 more reps" after a comma in "+2.5 kg, 2 more reps".
    var lowercasedFirst: String { isEmpty ? self : prefix(1).lowercased() + dropFirst() }
}
func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0,+) / Double(values.count) }
struct ExerciseHistory {
    var sessions: [Session]

    /// The best score logged for an exercise across `sessions`, for D30's PR comparison.
    static func bestScore(name: String, sessions: [Session]) -> [Double]? {
        sessions.flatMap { steps(name: name, session: $0) }
            .filter { $0.status == .logged }
            .compactMap { SessionStats.score($0.result) }
            .max { $0.lexicographicallyPrecedes($1) }
    }
    func series(name: String, units: WeightUnit) -> [ExercisePoint] {
        sessions.filter { $0.endedAt != nil && $0.units == units }.sorted { $0.startedAt < $1.startedAt }.compactMap { session in
            let steps = Self.steps(name: name, session: session)
            guard steps.contains(where: { $0.status == .logged }) else { return nil }
            let results = steps.filter { $0.status == .logged }.compactMap(\.result)
            let best = SessionStats.best(steps)
            return ExercisePoint(date: session.startedAt, sets: results, setSeconds: steps.map(\.setSeconds), topWeight: best?.weight, topSetReps: best?.reps,
                                 topSeconds: steps.filter { $0.status == .logged }.compactMap { $0.result?.seconds }.max(), volume: SessionStats.volume(steps), units: units)
        }
    }
    static func steps(name: String, session: Session) -> [SessionStep] {
        let key = normalized(name)
        let indices = Set(session.exercises.indices.filter { normalized(session.exercises[$0].name) == key })
        return session.steps.filter { indices.contains($0.exerciseIndex) }
    }
    static func last(name: String, units: WeightUnit, sessions: [Session]) -> Session? {
        sessions.filter { session in session.endedAt != nil && session.units == units && steps(name: name, session: session).contains { $0.status == .logged } }.max { $0.startedAt < $1.startedAt }
    }
}
enum TargetText {
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return String(format: "%.1f", locale: Locale(identifier:"en_US_POSIX"), value).replacingOccurrences(of: ".0", with: "")
    }
    static func time(_ seconds: Int) -> String { "\(max(0, seconds) / 60):" + String(format:"%02d",max(0, seconds) % 60) }

    /// A volume total, grouped: "12,400". Weights and reps stay ungrouped — they are never
    /// four digits — but a session's volume routinely is, and "12400 kg" is hard to read.
    static func grouped(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? number(value)
    }
    static func work(_ target: WorkTarget) -> String {
        switch target {
        case let .duration(n): return "\(n) s"
        case let .openDuration(n): return n.map { "\($0)+ s" } ?? "As long as possible"
        case let .reps(r):
            switch r { case let .fixed(n): return "\(n)"; case let .range(a,b): return "\(a)–\(b)"; case let .amrap(n): return n.map { "\($0)+" } ?? "AMRAP" }
        }
    }
    static func target(_ target: SetTarget, range: RepRange?, units: WeightUnit) -> String {
        var text = work(target.work)
        if case let .reps(.fixed(n)) = target.work, let range, range.min != n || range.max != n { text += " (\(range.min)–\(range.max))" }
        if let w = target.weight { text += " · \(number(w)) \(units.rawValue)" }
        return text
    }

    /// An exercise in one line, showing what actually varies across its sets (v1.1, R3/R4):
    /// "3 × 8–12 · 60 kg" when every set matches, "3 × 8–12 · 24 / 26 / 28 kg" when the weight
    /// climbs, and "12 · 24 kg / 10 · 26 kg / 8 · 28 kg" when the work varies too. v1 repeated
    /// the first set's target and called it the exercise, which hid every pyramid and drop-down.
    static func summary(_ exercise: Exercise, units: WeightUnit) -> String {
        guard let first = exercise.sets.first else { return "No sets" }
        let count = exercise.sets.count
        let works = exercise.sets.map { work($0.work) }
        let weights = exercise.sets.map(\.weight)
        let sameWork = works.allSatisfy { $0 == works[0] }
        let sameWeight = weights.allSatisfy { $0 == weights[0] }

        var text: String
        if sameWork && sameWeight {
            text = "\(count) × \(target(first, range: exercise.repRange, units: units))"
        } else if sameWork {
            // Only the load moves: say the work once and list the weights.
            var work = "\(count) × " + works[0]
            if case let .reps(.fixed(n)) = first.work, let range = exercise.repRange,
               range.min != n || range.max != n { work += " (\(range.min)–\(range.max))" }
            let list = weights.map { $0.map(number) ?? "–" }.joined(separator: " / ")
            text = weights.contains(where: { $0 != nil })
                ? "\(work) · \(list) \(units.rawValue)" : work
        } else {
            text = zip(works, weights)
                .map { work, weight in weight.map { "\(work) · \(number($0))" } ?? work }
                .joined(separator: " / ")
            if weights.contains(where: { $0 != nil }) { text += " \(units.rawValue)" }
        }
        let drops = exercise.sets.reduce(0) { $0 + $1.drops.count }
        if drops > 0 { text += " · \(drops) drop\(drops == 1 ? "" : "s")" }
        return text
    }
}
