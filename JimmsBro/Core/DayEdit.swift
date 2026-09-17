import Foundation

/// SPEC §6.66 (D93, v1.11): a change to a day's exercises where it stands — the day's editor,
/// opened from the Change *day* picker's card. Every change is one of four, applied to a `Day`
/// value the screen holds and never stores: the handle's move, the swipe's remove, Add
/// exercise's add, and the exercise sheet's replace. Nothing is checked here and nothing is
/// written; **Use for Wednesday** checks the whole day through the importer
/// (`DayChoices.Exercises.checked`) and writes it as the date's own day (§6.50).
enum DayEdit: Equatable {
    /// The exercise at `from` ends at `to` — an index, not SwiftUI's gap (Plan detail's rule).
    case move(from: Int, to: Int)
    case remove(Int)
    /// Appended at the end, where the dashed row is.
    case add(Exercise)
    case replace(Int, Exercise)

    /// The day after this edit. An index outside the day changes nothing: the screen only asks
    /// with the indices it drew.
    func applied(to day: Day) -> Day {
        var edited = day
        let indices = day.exercises.indices
        switch self {
        case let .move(from, to):
            guard indices.contains(from), indices.contains(to) else { return day }
            edited.exercises.insert(edited.exercises.remove(at: from), at: to)
        case let .remove(index):
            guard indices.contains(index) else { return day }
            edited.exercises.remove(at: index)
        case let .add(exercise):
            edited.exercises.append(exercise)
        case let .replace(index, exercise):
            guard indices.contains(index) else { return day }
            edited.exercises[index] = exercise
        }
        return edited
    }

    /// Add exercise's new exercise: the plan's default sets — three, the day's most common reps,
    /// no weight — at the day's most common rest, else the setting's, so its sheet is the next tap.
    static func exercise(named name: String, in day: Day, settings: Settings) -> Exercise {
        let rest = mostCommon(day.exercises.compactMap { $0.sets.first?.restSeconds }) ?? settings.defaultRestSeconds
        let set = SetTarget(work: .reps(commonReps(day)), weight: nil, restSeconds: rest)
        return Exercise(name: name.trimmed, sets: Array(repeating: set, count: defaultSets))
    }

    static let defaultSets = 3
    /// A day with nothing counted in reps — holds only — takes the exercise sheet's placeholder.
    static let fallbackReps = RepTarget.range(min: 8, max: 12)

    /// The day's most common reps target, counted once per exercise by its first set; a tie goes
    /// to the one that comes first.
    static func commonReps(_ day: Day) -> RepTarget {
        mostCommon(day.exercises.compactMap { exercise -> RepTarget? in
            guard case let .reps(target)? = exercise.sets.first?.work else { return nil }
            return target
        }) ?? fallbackReps
    }

    /// The value that occurs most, the earliest of equals; nil for none.
    private static func mostCommon<T: Equatable>(_ values: [T]) -> T? {
        var counted: [(value: T, count: Int)] = []
        for value in values {
            if let index = counted.firstIndex(where: { $0.value == value }) {
                counted[index].count += 1
            } else {
                counted.append((value, 1))
            }
        }
        var best: (value: T, count: Int)?
        for next in counted where next.count > (best?.count ?? 0) { best = next }
        return best?.value
    }
}
