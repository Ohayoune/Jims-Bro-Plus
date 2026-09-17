import Foundation

/// SPEC §6.65 (D92, v1.11): a progression as its review draws it — by day, one **ladder** per
/// exercise: its steps as bars, the first lit, and step 1's numbers beside the name. The review
/// shows the result, not the format (D87): what the chatbot planned reads as a climb, not as a
/// line of targets.
struct ProgressionLadder: Equatable {
    /// What a ladder's heights follow.
    enum Measure: Equatable {
        /// The weight of each step, when it changes.
        case weight
        /// The reps' lower bound — or a hold's seconds — when there is no weight, or the weight
        /// holds while the reps climb.
        case reps
        /// Neither changes: every bar the same.
        case level
    }

    var exerciseName: String
    /// One per step, step 1 first, each in 0…1 within this exercise.
    var bars: [Double]
    /// The lit bar: step 1, where a started progression begins.
    var lit = 0
    /// Step 1's numbers: *82.5 kg · 6–8*, or *reps · 8–12* for a bodyweight exercise.
    var first: String
    var measure: Measure
}

/// One day of the review: its name, its colour by its place in the plan (D65), and its
/// exercises' ladders in the day's order.
struct DayLadders: Equatable {
    var dayName: String
    var colour: DayColour
    var exercises: [ProgressionLadder]
}

extension ProgressionLadder {
    /// The lowest bar of a ladder that climbs: short, but still a bar.
    static let floor = 0.25
    /// Every bar of a ladder that nothing moves.
    static let level = 0.5

    /// The review's days: every day of `plan` with an exercise the progression names, and in
    /// each the exercises it names, in the plan's order.
    static func of(_ progression: Progression, _ plan: Plan) -> [DayLadders] {
        plan.days.enumerated().compactMap { index, day in
            let ladders = day.exercises.compactMap { exercise in
                progression.entry(day: day.name, exercise: exercise.name)
                    .map { of($0, exercise: exercise, units: plan.units) }
            }
            return ladders.isEmpty ? nil : DayLadders(dayName: day.name, colour: .of(dayIndex: index), exercises: ladders)
        }
    }

    /// One exercise's ladder. Each step's weight and work carry to the next step that does not
    /// say its own — so a `{}` step repeats the step before it, and step 1 starts from the
    /// plan's own targets. A bodyweight exercise has no weight to climb by.
    static func of(_ entry: ProgressionEntry, exercise: Exercise, units: WeightUnit) -> ProgressionLadder {
        let bodyweight = exercise.bodyweight
        var weight: Double? = bodyweight ? nil : exercise.sets.compactMap(\.weight).max()
        var work: WorkTarget? = exercise.sets.first?.work
        var weights: [Double?] = []
        var lows: [Int?] = []
        for step in entry.weeks {
            if let sets = step.sets, !sets.isEmpty {
                if !bodyweight, let top = sets.compactMap(\.weight).max() { weight = top }
                let works = sets.compactMap(\.work)
                if let easiest = works.min(by: { lowerBound($0) < lowerBound($1) }) { work = easiest }
            } else {
                if !bodyweight, let stepWeight = step.weight { weight = stepWeight }
                if let stepWork = step.work { work = stepWork }
            }
            weights.append(weight)
            lows.append(work.map(lowerBound))
        }

        let measure: Measure
        let values: [Double]
        let known = weights.compactMap { $0 }
        if !bodyweight, known.count == weights.count, Set(known).count > 1 {
            measure = .weight
            values = known
        } else if lows.allSatisfy({ $0 != nil }), Set(lows.compactMap { $0 }).count > 1 {
            measure = .reps
            values = lows.compactMap { $0 }.map(Double.init)
        } else {
            measure = .level
            values = weights.map { _ in 0 }
        }

        return ProgressionLadder(exerciseName: exercise.name, bars: heights(values),
                                 first: first(entry.weeks.first, exercise: exercise, weight: weights.first ?? weight,
                                              units: units),
                                 measure: measure)
    }

    /// `values` within their own span: the least at `floor`, the most at 1, and all at `level`
    /// when they do not differ.
    static func heights(_ values: [Double]) -> [Double] {
        guard let low = values.min(), let high = values.max(), high > low else { return values.map { _ in level } }
        return values.map { floor + (1 - floor) * ($0 - low) / (high - low) }
    }

    /// The number a ladder of reps climbs by: a range's or an AMRAP's minimum, a fixed count, a
    /// hold's seconds.
    static func lowerBound(_ work: WorkTarget) -> Int {
        switch work {
        case let .reps(.fixed(count)): return count
        case let .reps(.range(min, _)): return min
        case let .reps(.amrap(min)): return min ?? 0
        case let .duration(seconds): return seconds
        case let .openDuration(min): return min ?? 0
        }
    }

    /// Step 1's numbers, in the compact grammar the ladder's neighbours use: *82.5 kg · 6–8*,
    /// *reps · 8–12* with no weight, *45 s* for a hold, and a step that varies its sets as
    /// D53's line says it.
    private static func first(_ step: ProgressionWeek?, exercise: Exercise, weight: Double?,
                              units: WeightUnit) -> String {
        if let step, let sets = step.sets, !sets.isEmpty {
            return ProgressionText.change(step, units: units, bodyweight: exercise.bodyweight)
        }
        let own = step?.work == nil
        guard let work = step?.work ?? exercise.sets.first?.work else {
            return weight.map { "\(TargetText.number($0)) \(units.rawValue)" } ?? "–"
        }
        let text = TargetText.workWithRange(work: work, range: own ? exercise.repRange : nil, wording: .compact)
        if let weight { return "\(TargetText.number(weight)) \(units.rawValue) · \(text)" }
        return work.isTimed ? text : "reps · \(text)"
    }
}
