import Foundation

/// SPEC §6.19 (D77, v1.9): a point where part of a plan is written as JSON — one exercise, one
/// day, exercises to add, a day to add, and a day just for a date (§6.50). One sheet serves them
/// all (D43); what differs between them is here, built from the plan and the target, and the
/// sheet only draws it:
///
/// 1. **Named** — `title` says what the JSON is, and `place` where it lands and for how long.
/// 2. **Pre-filled** — an edit opens on the part's own text; an addition on the smallest valid
///    example, so a change is one number and a paste replaces the box.
/// 3. **The error at the line** — `marks(for:in:)` finds the line each error's path names, or
///    leaves the sentence under the box.
/// 4. **Save says its effect** — `saveTitle`, never a bare Save.
struct JSONPoint: Equatable {
    enum Kind: Equatable {
        /// `days[day].exercises[exercise]`, replaced.
        case exercise(day: Int, exercise: Int)
        /// `days[day]`, replaced.
        case day(Int)
        /// Appended to `days[day]`, which had `after` exercises.
        case addExercises(day: Int, after: Int)
        /// Appended to the plan, which had `after` days.
        case addDays(after: Int)
        /// D76: a day just for one date, held by its swap; the plan never sees it.
        case ownDay
        /// D87, D95 (v1.11): a whole plan — Add plan's review, a draft's outline or its assembly,
        /// Plan detail's own text, a reply to **Say what should change**. Its refusals carry the
        /// plan's own paths ("days[1].exercises[0].reps", "units"), so each is marked where it is
        /// written: a day's path through the reader's origins, as `addDays` does, and the plan's
        /// own fields straight in the text.
        case plan
        /// D92, D95 (v1.11): a progression reply, one object whose paths start at its root.
        case progression
    }

    /// A marked line, and the sentences beneath it.
    struct Mark: Equatable {
        var line: Int
        var sentences: [String]
    }

    var kind: Kind
    /// "One exercise", "One day", "Exercises to add", "A day to add", "A day just for Wednesday".
    var title: String
    /// Where the text lands, and for how long: "Bench Press, exercise 3 of 5 in Push", "Added at
    /// the end of Push", "For Wednesday 16 September. Not saved to Push Pull Legs."
    var place: String
    /// The text the sheet opens with.
    var template: String
    /// "Replace Bench Press", "Replace Push", "Add to Push", "Add to Push Pull Legs", "Use for
    /// Wednesday".
    var saveTitle: String
    /// What to write, under the box while there is nothing to fix.
    var footer: String
}

extension JSONPoint {
    /// An exercise of the plan, opened on its own JSON.
    static func exercise(_ plan: Plan, day: Int, exercise: Int) -> JSONPoint? {
        guard let owner = plan.days[safe: day], let value = owner.exercises[safe: exercise] else { return nil }
        return JSONPoint(
            kind: .exercise(day: day, exercise: exercise), title: "One exercise",
            place: "\(value.name), exercise \(exercise + 1) of \(owner.exercises.count) in \(owner.name)",
            template: PlanJSON.render(exercise: value), saveTitle: "Replace \(value.name)",
            footer: "The same fields as a pasted plan's exercise. Sets can be a count or a list, so one set can differ from the others.")
    }

    /// A day of the plan, opened on its own JSON.
    static func day(_ plan: Plan, day: Int) -> JSONPoint? {
        guard let value = plan.days[safe: day] else { return nil }
        return JSONPoint(
            kind: .day(day), title: "One day",
            place: "\(value.name), day \(day + 1) of \(plan.days.count) in \(plan.name)",
            template: PlanJSON.render(day: value), saveTitle: "Replace \(value.name)",
            footer: "The whole day. Rename it here and the repeat block follows.")
    }

    /// Exercises added at the end of a day, opened on the example.
    static func addExercises(_ plan: Plan, day: Int) -> JSONPoint? {
        guard let owner = plan.days[safe: day] else { return nil }
        return JSONPoint(
            kind: .addExercises(day: day, after: owner.exercises.count), title: "Exercises to add",
            place: "Added at the end of \(owner.name)", template: exampleExercise,
            saveTitle: "Add to \(owner.name)",
            footer: "One exercise, or a list of them, in the same fields as a pasted plan's.")
    }

    /// Days added at the end of the plan, opened on a day of the example.
    static func addDays(_ plan: Plan) -> JSONPoint {
        // A weekday plan insists on a weekday (§6.19), so its example takes the first free one.
        let weekday = plan.schedule == .weekday
            ? Weekday.allCases.first { free in !plan.days.contains { $0.weekday == free } } : nil
        return JSONPoint(
            kind: .addDays(after: plan.days.count), title: "A day to add",
            place: "Added at the end of \(plan.name)",
            template: exampleDay(name: "Day \(plan.days.count + 1)", weekday: weekday),
            saveTitle: "Add to \(plan.name)",
            footer: "A day, or a whole plan whose days are added — the way to finish a week the chatbot cut short. "
                + (plan.schedule == .weekday ? "Each new day needs a weekday no other day has."
                                             : "A new day joins the repeat block."))
    }

    /// D76: a day just for a date — `when` as the strip says it ("Wednesday", "Today"), the date
    /// in full, the name a nameless day takes — opened on the date's own day when it has one.
    static func ownDay(when: String, date: String, name: String, plan: Plan, own: Day?) -> JSONPoint {
        JSONPoint(
            kind: .ownDay, title: "A day just for \(when)",
            place: "For \(date). Not saved to \(plan.name).",
            template: own.map(PlanJSON.render(day:)) ?? exampleDay(name: ""),
            saveTitle: "Use for \(when)",
            footer: "One day, in the same fields as a pasted plan's day. Left without a name, it is called \(name).")
    }

    /// The smallest exercise the importer takes as it stands (TQ30), so a change is one number.
    static let exampleExercise = """
    {
      "name": "Push-up",
      "sets": 3,
      "reps": "8-12",
      "restSeconds": 90
    }

    """

    /// A day of that one exercise, named `name` — "" to take the date's — with a weekday when the
    /// plan needs one.
    static func exampleDay(name: String, weekday: Weekday? = nil) -> String {
        var fields = ["  \"name\": \(PlanJSON.string(name))"]
        if let weekday { fields.append("  \"weekday\": \"\(weekday.rawValue)\"") }
        let exercise = exampleExercise.trimmed.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
        fields.append("  \"exercises\": [\n" + exercise + "\n  ]")
        return "{\n" + fields.joined(separator: ",\n") + "\n}\n"
    }

    /// What Save does to the plan; nil for a day just for a date, which is not the plan's.
    func operation(_ text: String) -> PlanEdit.Operation? {
        switch kind {
        case let .exercise(day, exercise): return .replaceExerciseJSON(day: day, exercise: exercise, text: text)
        case let .day(day): return .replaceDayJSON(day: day, text: text)
        case let .addExercises(day, _): return .insertExercisesJSON(day: day, at: nil, text: text)
        case .addDays: return .insertDaysJSON(text: text)
        // A whole plan is saved as a paste, and a progression read as a reply; neither is an
        // edit to a plan already on the phone, so neither has an operation.
        case .ownDay, .plan, .progression: return nil
        }
    }

    /// SPEC §6.19 (D77): each refusal marks the line its path names in `text`, with the sentence
    /// beneath it and without its place, because the line is the place — or, when no line can be
    /// named honestly, stays under the box with the whole sentence.
    func marks(for issues: [Issue], in text: String) -> (marked: [Mark], unmarked: [String]) {
        let origins = PlanEdit.located(text, as: reading).values?.map(\.origin)
        var lines: [Int: [String]] = [:]
        var unmarked: [String] = []
        for issue in issues {
            if let path = textPath(issue, origins: origins), let line = JSONLocator.line(of: path, in: text) {
                var placeless = issue
                placeless.path = ""
                lines[line, default: []].append(IssueText.friendly(placeless))
            } else {
                unmarked.append(IssueText.friendly(issue))
            }
        }
        return (lines.keys.sorted().map { Mark(line: $0, sentences: lines[$0] ?? []) }, unmarked)
    }

    /// How the text is read (D43): as exercises, or as days.
    private var reading: PlanEdit.FragmentKind {
        switch kind {
        case .exercise, .addExercises: return .exercises
        case .day, .addDays, .ownDay, .plan, .progression: return .days
        }
    }

    /// The issue's path in the text: which of the fragment's values the plan's path landed in,
    /// where the reader found that value, and the rest of the path. Nil for an issue about
    /// another part of the plan or about the paste as a whole, and for a value the reader made
    /// itself (loose exercises gathered into a day), which no line of the text is.
    private func textPath(_ issue: Issue, origins: [[JSONLocator.Component]?]?) -> [JSONLocator.Component]? {
        guard issue.code != "E_EDIT_INVALID", let origins,
              let path = JSONLocator.components(issue.path) else { return nil }
        let value: Int
        let rest: ArraySlice<JSONLocator.Component>
        switch kind {
        case let .exercise(day, exercise):
            guard path.starts(with: [.key("days"), .index(day), .key("exercises"), .index(exercise)]) else { return nil }
            value = 0
            rest = path.dropFirst(4)
        case let .day(day):
            guard path.starts(with: [.key("days"), .index(day)]) else { return nil }
            value = 0
            rest = path.dropFirst(2)
        case let .addExercises(day, after):
            guard path.count >= 4, path.starts(with: [.key("days"), .index(day), .key("exercises")]),
                  case let .index(added) = path[3], added >= after else { return nil }
            value = added - after
            rest = path.dropFirst(4)
        case let .addDays(after):
            guard path.count >= 2, path[0] == .key("days"),
                  case let .index(added) = path[1], added >= after else { return nil }
            value = added - after
            rest = path.dropFirst(2)
        case .ownDay:
            // `PlanLibrary.ownDay` already gives the day's own paths: "exercises[0].reps".
            value = 0
            rest = path[...]
        case .plan:
            // A day's path lands in the day the reader found; anything else — the plan's name,
            // its unit, its cycle — is written at that path in the text itself.
            guard path.count >= 2, path[0] == .key("days"), case let .index(day) = path[1] else { return path }
            guard let origin = origins[safe: day] ?? nil else { return nil }
            return origin + path.dropFirst(2)
        case .progression:
            // The reply's own paths, from its root: "exercises[0].steps[1]".
            return path
        }
        guard let origin = origins[safe: value] ?? nil else { return nil }
        return origin + rest
    }
}
