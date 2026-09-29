import Foundation

/// SPEC §6.19 (D77, v1.9): a point where part of a plan is written as JSON — one exercise, one
/// day, exercises to add, a day to add, and a day just for a date (§6.50); since v1.11 (D95) a
/// whole plan and a progression too, every one of them built here (v1.12, L5). One sheet serves
/// them all (D43); what differs between them is here, built from the plan and the target, and the
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

    // MARK: - A whole plan, and a progression (D87, D95)

    private static let wholePlanFooter = "A whole plan, in the fields the prompt asks a chatbot for."

    /// Add plan's **Edit the text**: a new plan, whose Save is a paste.
    static func newPlan(template: String) -> JSONPoint {
        JSONPoint(kind: .plan, title: "The plan", place: "A new plan. You see it before anything is saved.",
                  template: template, saveTitle: "Review the plan", footer: wholePlanFooter)
    }

    /// Plan detail's **Edit the text**: the plan's own text, saved in its place as an edit.
    static func replacing(_ name: String, text: String) -> JSONPoint {
        JSONPoint(kind: .plan, title: "The plan",
                  place: "All of \(name). Its history, its place in the cycle and its progression stay.",
                  template: text, saveTitle: "Replace \(name)", footer: wholePlanFooter)
    }

    /// A draft with every day in (D91): the whole plan as it would be saved.
    static func assembled(_ name: String, text: String) -> JSONPoint {
        JSONPoint(kind: .plan, title: "The plan", place: "All of \(name), before it is saved.",
                  template: text, saveTitle: "Review the plan", footer: wholePlanFooter)
    }

    /// A draft before its outline (D91): the outline's example.
    static let outline = JSONPoint(
        kind: .plan, title: "The outline", place: "The plan's name and its days, with no exercises yet.",
        template: exampleOutline, saveTitle: "Use this outline", footer: "The days are pasted one at a time after it.")

    /// A draft's day `index`, on D77's example day named for its slot.
    static func draftDay(_ outline: Plan, index: Int) -> JSONPoint? {
        guard let slot = outline.days[safe: index] else { return nil }
        return JSONPoint(
            kind: .day(index), title: "One day",
            place: "\(slot.name), day \(index + 1) of \(outline.days.count) in \(outline.name)",
            template: exampleDay(name: slot.name, weekday: slot.weekday),
            saveTitle: "Add \(slot.name)", footer: "One day, in the same fields as a pasted plan's day.")
    }

    /// **Say what should change**'s **Edit the text** (D94): the whole plan, whose Save reviews what
    /// changed, as a paste would.
    static func changing(_ name: String, text: String) -> JSONPoint {
        JSONPoint(kind: .plan, title: "The plan", place: "\(name), changed. Nothing is saved until you apply it.",
                  template: text, saveTitle: "See what changed", footer: "The whole plan, as the chatbot writes it back.")
    }

    /// Progression's **Edit the text** (D92): the last text read, or else a reply that reads as it
    /// stands — every exercise of the plan, each step `{}` — so a change is one number.
    static func progression(_ plan: Plan, steps: Int, text: String) -> JSONPoint {
        JSONPoint(kind: .progression, title: "The progression",
                  place: "Steps for \(plan.name). Nothing changes until you start.",
                  template: text.trimmed.isEmpty ? exampleProgression(plan, steps: steps) : text,
                  saveTitle: "Review the steps",
                  footer: "Each step gives a weight, reps or both; {} keeps the plan's own.")
    }

    /// The smallest plan the importer takes as it stands: one day of the example exercise, and no
    /// unit, so its review asks.
    static var examplePlan: String {
        let day = exampleDay(name: "Day 1").trimmed.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
        return "{\n  \"name\": \"My plan\",\n  \"days\": [\n" + day + "\n  ]\n}\n"
    }

    /// The smallest outline the drafting reader takes: a name and three empty days.
    static let exampleOutline = """
    {
      "name": "My plan",
      "days": [
        { "name": "Day 1" },
        { "name": "Day 2" },
        { "name": "Day 3" }
      ]
    }

    """

    /// A progression reply for `plan` that holds every exercise where it is for `steps` steps.
    static func exampleProgression(_ plan: Plan, steps: Int) -> String {
        let empty = Array(repeating: "{}", count: max(1, steps)).joined(separator: ", ")
        let lines = plan.days.flatMap { day in
            day.exercises.map { exercise in
                "    { \"day\": \(PlanJSON.string(day.name)), \"name\": \(PlanJSON.string(exercise.name)), \"steps\": [\(empty)] }"
            }
        }
        return "{\n  \"steps\": \(max(1, steps)),\n  \"exercises\": [\n" + lines.joined(separator: ",\n") + "\n  ]\n}\n"
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

    /// What Save does to the plan the sheet was opened on, in Plan detail; nil for a day just for a
    /// date, which is not the plan's, and a progression, which is read as a reply. A whole plan is
    /// Plan detail's **Edit the text** (`replacing`); the other whole-plan sheets — Add plan's, a
    /// draft's, Say what should change's — read their text as a paste and never ask.
    func operation(_ text: String) -> PlanEdit.Operation? {
        switch kind {
        case let .exercise(day, exercise): return .replaceExerciseJSON(day: day, exercise: exercise, text: text)
        case let .day(day): return .replaceDayJSON(day: day, text: text)
        case let .addExercises(day, _): return .insertExercisesJSON(day: day, at: nil, text: text)
        case .addDays: return .insertDaysJSON(text: text)
        case .plan: return .replacePlanJSON(text: text)
        case .ownDay, .progression: return nil
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
