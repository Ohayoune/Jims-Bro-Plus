import Foundation

/// D46 (v1.4): a routine the app ships, written to its own plan format (`JimmsBro/Resources/
/// <id>.json`) and imported through the ordinary pipeline like anything pasted. What the
/// catalogue says about a plan is the only thing the JSON cannot: who it is for and why it is
/// built the way it is. Everything countable — days, sets, minutes — is read off the plan.
struct BuiltInPlan: Identifiable, Equatable {
    /// Also the resource name.
    let id: String
    let name: String
    /// One line under the name: "Three workouts a week; every muscle, every time."
    let tagline: String
    /// The paragraph on top of the review: what the routine is and why it is built this way.
    let about: String
    /// "New to lifting, or back after a break."
    let forWhom: String
    let daysPerWeek: Int
    /// Lower-case, for the summary line: "barbell, rack and bench".
    let equipment: String
}

enum BuiltInPlans {
    /// The four, in the order the picker shows them: by how much of a week and a gym they ask
    /// for, least first.
    static let all: [BuiltInPlan] = [
        BuiltInPlan(
            id: "FullBody",
            name: "Full Body",
            tagline: "Three workouts a week; every muscle, every time.",
            about: "Two workouts, A and B, taken in turns three times a week: A B A one week, "
                + "B A B the next. Each is built around a squat or a deadlift, a press and a "
                + "pull, then two smaller movements — three hard sets of each, with rests long "
                + "enough to make the next set count. This is where lifting starts, and where "
                + "a lot of people could happily stay.",
            forWhom: "New to lifting, or back after a break.",
            daysPerWeek: 3,
            equipment: "barbell, rack, bench, and a lat pulldown or pull-up bar"),
        BuiltInPlan(
            id: "UpperLower",
            name: "Upper Lower",
            tagline: "Four days: two for the upper body, two for the lower.",
            about: "Upper A, Lower A, a rest day, Upper B, Lower B, and the weekend off. Each "
                + "half of the body is trained twice a week from two angles: a heavy day led by "
                + "the bench and the squat, and a second led by the overhead press and the "
                + "deadlift. The isolation work is paired into supersets, so a day still fits "
                + "in an hour.",
            forWhom: "A few months of lifting behind you, and wanting more from each week.",
            daysPerWeek: 4,
            equipment: "a gym with barbells, dumbbells, cables and machines"),
        BuiltInPlan(
            id: "PushPullLegs",
            name: "Push Pull Legs",
            tagline: "Six days a week: push, pull, legs, and again.",
            about: "The classic split for people who want to lift most days. Push is the "
                + "chest, shoulders and triceps; Pull is the back and biceps, led by the "
                + "deadlift; Legs is the squat and everything below the hips. Each runs twice "
                + "in a seven-day block with one rest day. It is the most volume of the four, "
                + "and the most time.",
            forWhom: "Enthusiasts who can be in the gym most days.",
            daysPerWeek: 6,
            equipment: "a gym with barbells, dumbbells, cables and machines"),
        BuiltInPlan(
            id: "AtHome",
            name: "At Home",
            tagline: "Three days a week with no equipment at all.",
            about: "Two bodyweight workouts, A and B, taken in turns three times a week. A "
                + "floor, a wall, a chair and a sturdy table stand in for the machines: "
                + "push-ups for the bench, rows under a table for the pulldown, split squats "
                + "for the rack. Every exercise says how to make it harder, because that is "
                + "how a bodyweight plan progresses.",
            forWhom: "No gym, travelling, or training in a living room.",
            daysPerWeek: 3,
            equipment: "a chair and a sturdy table"),
    ]

    /// The one sentence the picker ends on. These are offered next to writing your own, never
    /// instead of it: the chatbot round-trip is still the app's premise.
    static let buildYourOwn = "These are starting points, not prescriptions. The best plan is "
        + "the one written for you: go back to Add plan, tap Copy prompt under Create with a "
        + "chatbot, describe your goals, your equipment and your week, and paste back what it "
        + "writes."

    /// D57 (v1.6): the one the picker recommends to a stranger with no history yet. Full Body
    /// is where the catalogue itself says lifting starts.
    static let recommendedId = "FullBody"

    static func entry(_ id: String) -> BuiltInPlan? { all.first { $0.id == id } }

    /// "3 days a week · about 45 min · barbell, rack and bench". The minutes are the plan's
    /// own numbers (below), so the line is never a claim the plan does not back.
    static func summary(_ entry: BuiltInPlan, minutes: Int?) -> String {
        var parts = ["\(entry.daysPerWeek) days a week"]
        if let minutes { parts.append("about \(minutes) min") }
        parts.append(entry.equipment)
        return parts.joined(separator: " · ")
    }

    /// About how long one day takes: the warm-up, the walk between exercises, forty seconds a
    /// set of reps or the set's own seconds, and the plan's rest after every set that is
    /// followed by another in its block. Uses the real flattening, so a superset rests once
    /// a round. Nil for a day that does not exist.
    static func estimatedMinutes(_ plan: Plan, dayIndex: Int, settings: Settings) -> Int? {
        guard let session = Session.start(plan: plan, dayIndex: dayIndex, now: Date(timeIntervalSince1970: 0)) else {
            return nil
        }
        var seconds = Double(settings.warmUpSeconds)
        let blocks = Set(session.steps.map(\.blockIndex)).count
        seconds += Double(max(0, blocks - 1) * settings.transitionRestSeconds)
        for (index, step) in session.steps.enumerated() {
            guard let target = session.target(at: index) else { continue }
            switch target.work {
            case .reps: seconds += 40
            case let .duration(held): seconds += Double(held)
            case let .openDuration(minimum): seconds += Double(minimum ?? 45)
            }
            guard step.isLastInRound, !step.isLastInBlock,
                  let set = session.exercises[safe: step.exerciseIndex]?.targets[safe: step.setIndex]
            else { continue }
            seconds += Double(set.groupRestSeconds ?? set.restSeconds)
        }
        return Int((seconds / 60).rounded())
    }

    /// The plan's typical day, to the nearest five minutes, for the picker's line.
    static func estimatedMinutes(_ plan: Plan, settings: Settings) -> Int? {
        let days = plan.days.indices.compactMap { estimatedMinutes(plan, dayIndex: $0, settings: settings) }
        guard !days.isEmpty else { return nil }
        let mean = Double(days.reduce(0, +)) / Double(days.count)
        return Int((mean / 5).rounded() * 5)
    }
}
