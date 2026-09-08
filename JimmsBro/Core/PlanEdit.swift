import Foundation

/// Writes a `Plan` back out as the JSON of PLAN_FORMAT §1, so an edited plan has a `sourceText`
/// that matches it — Copy JSON, the export file and a Replace round-trip all read the edit.
///
/// It always emits the explicit array-of-sets form. The compact forms (`"sets": 4` with
/// exercise-level defaults) are a convenience for whoever is writing the plan by hand or by
/// chatbot; a generator has nothing to gain from them and everything to lose by guessing which
/// values happen to be shared.
enum PlanJSON {
    static func render(_ plan: Plan) -> String {
        var out = "{\n"
        out += "  \"schemaVersion\": 1,\n"
        out += "  \"name\": \(string(plan.name)),\n"
        out += "  \"units\": \"\(plan.units.rawValue)\",\n"
        out += "  \"schedule\": \"\(plan.schedule.rawValue)\",\n"
        if !plan.cycle.isEmpty {
            let names = plan.cycle.map { entry -> String in
                guard case let .day(index) = entry, let day = plan.days[safe: index] else { return "rest" }
                return day.name
            }
            out += "  \"cycle\": [\(names.map(string).joined(separator: ", "))],\n"
        }
        out += "  \"days\": [\n"
        out += plan.days.map(day).joined(separator: ",\n")
        out += "\n  ]\n}\n"
        return out
    }

    /// D43 (v1.3): one day, as the text an editor shows — the same JSON `render(_:)` would
    /// write for it inside the plan, moved to the left margin.
    static func render(day: Day) -> String { dedent(self.day(day)) }

    /// D43 (v1.3): one exercise, likewise. A superset member carries its round rest as the
    /// exercise-level `restSeconds`, exactly as it does inside the plan.
    static func render(exercise: Exercise) -> String { dedent(self.exercise(exercise)) }

    private static func dedent(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let indent = lines.filter { !$0.trimmed.isEmpty }
            .map { $0.prefix { $0 == " " }.count }.min() ?? 0
        return lines.map { String($0.dropFirst(min(indent, $0.prefix { $0 == " " }.count))) }
            .joined(separator: "\n") + "\n"
    }

    private static func day(_ day: Day) -> String {
        var fields = ["      \"name\": \(string(day.name))"]
        if let weekday = day.weekday { fields.append("      \"weekday\": \"\(weekday.rawValue)\"") }
        fields.append("      \"exercises\": [\n"
                      + day.exercises.map(exercise).joined(separator: ",\n")
                      + "\n      ]")
        return "    {\n" + fields.joined(separator: ",\n") + "\n    }"
    }

    private static func exercise(_ exercise: Exercise) -> String {
        var fields = ["          \"name\": \(string(exercise.name))"]
        if let group = exercise.group { fields.append("          \"group\": \(string(group))") }
        if let notes = exercise.notes, !notes.isEmpty {
            fields.append("          \"notes\": \(string(notes))")
        }
        if let range = exercise.repRange {
            fields.append("          \"repRange\": \"\(range.min)-\(range.max)\"")
        }
        if exercise.bodyweight { fields.append("          \"bodyweight\": true") }
        // A superset's between-round rest lives in `groupRestSeconds`, which the importer
        // resolves from the first member's *exercise-level* `restSeconds` — a field the
        // explicit array-of-sets form does not otherwise need. Without writing it back, a
        // re-import (which is what every edit is) would find no exercise-level rest, set
        // `groupRestSeconds` to nil, and quietly fall back to the last member's own rest.
        if exercise.group != nil,
           let round = exercise.sets.compactMap(\.groupRestSeconds).first {
            fields.append("          \"restSeconds\": \(round)")
        }
        fields.append("          \"sets\": [\n"
                      + exercise.sets.map { set(_: $0) }.joined(separator: ",\n")
                      + "\n          ]")
        return "        {\n" + fields.joined(separator: ",\n") + "\n        }"
    }

    private static func set(_ target: SetTarget) -> String {
        var fields = ["              " + work(target.work)]
        if let weight = target.weight { fields.append("              \"weight\": \(number(weight))") }
        fields.append("              \"restSeconds\": \(target.restSeconds)")
        // Only a fixed duration carries a beep offset; anywhere else the importer drops it.
        // `nil` must be written as an explicit `false`: leaving the field out means "default",
        // which the importer resolves to 10 % of the duration, not to "no warning".
        if case .duration = target.work {
            fields.append("              \"warningBeep\": "
                          + (target.warningBeepSeconds.map(String.init) ?? "false"))
        }
        if !target.drops.isEmpty {
            let drops = target.drops.map { drop -> String in
                var parts = ["                  " + work(drop.work)]
                if let weight = drop.weight { parts.append("                  \"weight\": \(number(weight))") }
                return "                {\n" + parts.joined(separator: ",\n") + "\n                }"
            }
            fields.append("              \"drops\": [\n" + drops.joined(separator: ",\n") + "\n              ]")
        }
        return "            {\n" + fields.joined(separator: ",\n") + "\n            }"
    }

    /// The one field that says what the set is: `reps` or `durationSeconds` (PLAN_FORMAT §3.2, §3.12).
    static func work(_ work: WorkTarget) -> String {
        switch work {
        case let .duration(seconds): return "\"durationSeconds\": \(seconds)"
        case let .openDuration(minimum):
            return minimum.map { "\"durationSeconds\": \"\($0)+\"" } ?? "\"durationSeconds\": \"max\""
        case let .reps(target):
            switch target {
            case let .fixed(n): return "\"reps\": \(n)"
            case let .range(low, high): return "\"reps\": \"\(low)-\(high)\""
            case let .amrap(minimum):
                return minimum.map { "\"reps\": \"\($0)+\"" } ?? "\"reps\": \"AMRAP\""
            }
        }
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// A JSON string literal. Only the escapes JSON requires; plan text is ordinary prose.
    private static func string(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                out += character.value < 0x20 ? String(format: "\\u%04x", character.value)
                                              : String(character)
            }
        }
        return out + "\""
    }
}

/// SPEC §4.3 (D29, v1.1): editing a plan in the app rather than going back to the chatbot for a
/// one-word change. Every operation produces JSON and puts it straight back through the import
/// pipeline, so an edit is validated and normalized by exactly the code an import is — an edit
/// can never produce a plan the app would have refused to import.
enum PlanEdit {
    enum Operation: Equatable {
        case renameExercise(day: Int, exercise: Int, name: String)
        case setSetCount(day: Int, exercise: Int, count: Int)
        case setWeight(day: Int, exercise: Int, weight: Double?)
        case setReps(day: Int, exercise: Int, text: String)
        case setRepRange(day: Int, exercise: Int, text: String?)
        case setRest(day: Int, exercise: Int, seconds: Int)
        case moveExercise(day: Int, from: Int, to: Int)
        case deleteExercise(day: Int, exercise: Int)
        case duplicateDay(day: Int)
        case renameDay(day: Int, name: String)
        /// D43 (v1.3): the JSON edits. Each takes text, spliced into the plan's own JSON and
        /// re-imported, so the errors it can raise are the import pipeline's, with full paths.
        case replaceExerciseJSON(day: Int, exercise: Int, text: String)
        case replaceDayJSON(day: Int, text: String)
        /// Appended to the day (`at` nil) or inserted before the exercise at `at`.
        case insertExercisesJSON(day: Int, at: Int?, text: String)
        /// Appended after the last day, and added to a rotation's repeat block.
        case insertDaysJSON(text: String)
    }

    /// The edited plan, or the errors that stopped it. The plan keeps its id, its position in
    /// the cycle, the date the cycle is anchored to (D37) and its original import date — it is
    /// the same plan, changed, not a new one.
    static func apply(_ operation: Operation, to plan: Plan, settings: Settings,
                      now: Date = Date()) -> ImportResult {
        let text: String
        switch operation {
        case .replaceExerciseJSON, .replaceDayJSON, .insertExercisesJSON, .insertDaysJSON:
            let splice = spliced(plan, operation)
            guard let spliced = splice.text else { return ImportResult(plan: nil, issues: splice.issues) }
            text = spliced
        default:
            guard var edited = mutated(operation, plan) else {
                return ImportResult(plan: nil, issues: [Issue(
                    severity: .error, code: "E_EDIT_INVALID", path: "",
                    message: "That edit doesn't apply to this plan.")])
            }
            edited.sourceText = PlanJSON.render(edited)
            text = edited.sourceText
        }
        var result = PlanImport.run(text, settings: settings, now: now)
        guard var reimported = result.plan else { return result }
        reimported.id = plan.id
        reimported.importedAt = plan.importedAt
        reimported.cyclePosition = plan.cyclePosition
        // v1.3: an edit used to drop the anchor, so the next launch re-anchored the rotation
        // to that day and the calendar moved — the compounding D37 had just fixed.
        reimported.cycleAnchor = plan.cycleAnchor
        // D44: an edit to the plan is not a reason to lose the progression attached to it;
        // entries match by name, so a renamed exercise simply stops matching.
        reimported.progression = plan.progression
        // A spliced tree is JSON in the encoder's key order; what the plan keeps as its text
        // is the canonical rendering, the same as after any other edit.
        reimported.sourceText = PlanJSON.render(reimported)
        result.plan = reimported
        return result
    }

    // MARK: - D43: JSON fragments

    /// What a pasted fragment is being read as.
    enum FragmentKind { case exercises, days }

    /// D43: a fragment decoded with the import pipeline's own leniency — fences, prose around
    /// it, curly quotes — and read as `kind`. Generous about shape, because a chatbot asked for
    /// "the missing day" may answer with a day, a whole plan holding it, or a bare list of
    /// exercises: a plan gives its days (or all its exercises), a day gives itself (or its
    /// exercises), an exercise gives itself (or a day of one), and an array is read the same way.
    static func fragment(_ text: String, as kind: FragmentKind) -> (values: [RawJSON]?, issues: [Issue]) {
        let extracted = PlanImport.extract(text)
        guard let body = extracted.value else { return (nil, extracted.issues) }
        let decoded = PlanImport.decode(body)
        guard let raw = decoded.value else { return (nil, extracted.issues + decoded.issues) }
        let issues = extracted.issues + decoded.issues
        func isDay(_ value: RawJSON) -> Bool { value.object?["exercises"] != nil }
        func isPlan(_ value: RawJSON) -> Bool { value.object?["days"] != nil }
        let list: [RawJSON]
        if let array = raw.array { list = array } else if raw.object != nil { list = [raw] } else {
            return (nil, issues + [Issue(severity: .error, code: "E_NOT_A_PLAN", path: "",
                                         message: "This JSON isn't a workout plan. Use an object with days or exercises.")])
        }
        guard !list.isEmpty, list.allSatisfy({ $0.object != nil }) else {
            return (nil, issues + [Issue(severity: .error, code: "E_NOT_A_PLAN", path: "",
                                         message: "Paste an exercise, a day, or a list of them.")])
        }
        // Flatten whatever was pasted down to the shape asked for.
        let days: [RawJSON] = list.flatMap { value -> [RawJSON] in
            if isPlan(value) { return value["days"]?.array ?? [] }
            if isDay(value) { return [value] }
            return []
        }
        // An object that is neither a plan nor a day is an exercise when it says something an
        // exercise says; otherwise, read as days, it is a day with nothing in it, and the
        // importer's own sentence for that ("has no exercises") is the right refusal.
        let exerciseKeys: Set<String> = ["reps", "durationSeconds", "sets", "weight", "repRange",
                                         "bodyweight", "drops", "group", "warningBeep", "restSeconds"]
        func isExerciseLike(_ value: RawJSON) -> Bool {
            !Set(value.object?.keys.map { $0 } ?? []).isDisjoint(with: exerciseKeys)
        }
        let loose = list.filter { !isPlan($0) && !isDay($0) }
        switch kind {
        case .exercises:
            let fromDays = days.flatMap { $0["exercises"]?.array ?? [] }
            return (fromDays + loose, issues)
        case .days:
            let exercises = loose.filter(isExerciseLike)
            let bare = loose.filter { !isExerciseLike($0) }
            return (days + bare + (exercises.isEmpty ? [] : [.object(["exercises": .array(exercises)])]), issues)
        }
    }

    /// The plan's own JSON with the fragment spliced in, ready for the import pipeline, or the
    /// errors that stopped it. Works on the tree rather than the text so a fragment lands at a
    /// real path and the pipeline's errors name it — `days[1].exercises[2].sets[0].reps`.
    static func spliced(_ plan: Plan, _ operation: Operation) -> (text: String?, issues: [Issue]) {
        guard var tree = PlanImport.decode(PlanJSON.render(plan)).value?.object,
              var days = tree["days"]?.array else {
            return (nil, [Issue(severity: .error, code: "E_EDIT_INVALID", path: "",
                                message: "That edit doesn't apply to this plan.")])
        }
        func invalid() -> (String?, [Issue]) {
            (nil, [Issue(severity: .error, code: "E_EDIT_INVALID", path: "",
                         message: "That edit doesn't apply to this plan.")])
        }
        func cycleNames() -> [RawJSON] { tree["cycle"]?.array ?? [] }
        var issues: [Issue] = []

        switch operation {
        case let .replaceExerciseJSON(day, exercise, text):
            guard plan.days.indices.contains(day), plan.days[day].exercises.indices.contains(exercise),
                  var dayObject = days[day].object, var exercises = dayObject["exercises"]?.array,
                  exercises.indices.contains(exercise) else { return invalid() }
            let parsed = fragment(text, as: .exercises)
            guard let values = parsed.values else { return (nil, parsed.issues) }
            issues += parsed.issues
            guard values.count == 1 else {
                return (nil, issues + [Issue(severity: .error, code: "E_EDIT_INVALID", path: "days[\(day)].exercises[\(exercise)]",
                                              message: "Paste one exercise here; use Add exercise for several.")])
            }
            exercises[exercise] = values[0]
            dayObject["exercises"] = .array(exercises)
            days[day] = .object(dayObject)

        case let .replaceDayJSON(day, text):
            guard plan.days.indices.contains(day) else { return invalid() }
            let parsed = fragment(text, as: .days)
            guard let values = parsed.values else { return (nil, parsed.issues) }
            issues += parsed.issues
            guard values.count == 1, var dayObject = values[0].object else {
                return (nil, issues + [Issue(severity: .error, code: "E_EDIT_INVALID", path: "days[\(day)]",
                                              message: "Paste one day here; use Add day for several.")])
            }
            // The day keeps its identity: an unnamed fragment keeps the old name, and a renamed
            // one takes its place in the repeat block, which refers to days by name.
            let oldName = plan.days[day].name
            if dayObject["name"]?.string?.trimmed.isEmpty ?? true { dayObject["name"] = .string(oldName) }
            if let newName = dayObject["name"]?.string, normalized(newName) != normalized(oldName) {
                tree["cycle"] = .array(cycleNames().map {
                    normalized($0.string ?? "") == normalized(oldName) ? .string(newName) : $0
                })
            }
            days[day] = .object(dayObject)

        case let .insertExercisesJSON(day, at, text):
            guard plan.days.indices.contains(day), var dayObject = days[day].object,
                  var exercises = dayObject["exercises"]?.array else { return invalid() }
            let parsed = fragment(text, as: .exercises)
            guard let values = parsed.values else { return (nil, parsed.issues) }
            issues += parsed.issues
            guard !values.isEmpty else {
                return (nil, issues + [Issue(severity: .error, code: "E_NO_EXERCISES", path: "days[\(day)].exercises",
                                              message: "Nothing to add: paste at least one exercise.")])
            }
            let position = min(max(at ?? exercises.count, 0), exercises.count)
            exercises.insert(contentsOf: values, at: position)
            dayObject["exercises"] = .array(exercises)
            days[day] = .object(dayObject)

        case let .insertDaysJSON(text):
            let parsed = fragment(text, as: .days)
            guard let values = parsed.values else { return (nil, parsed.issues) }
            issues += parsed.issues
            guard !values.isEmpty else {
                return (nil, issues + [Issue(severity: .error, code: "E_NO_DAYS", path: "days",
                                              message: "Nothing to add: paste at least one day.")])
            }
            var cycle = cycleNames()
            for (offset, value) in values.enumerated() {
                guard var dayObject = value.object else { continue }
                // Named here, deliberately, so it can be put into the repeat block by name.
                if dayObject["name"]?.string?.trimmed.isEmpty ?? true {
                    dayObject["name"] = .string("Day \(plan.days.count + offset + 1)")
                }
                days.append(.object(dayObject))
                // A day you add is a day you mean to train: it joins a rotation's repeat block.
                if plan.schedule == .rotation, let name = dayObject["name"] { cycle.append(name) }
            }
            if plan.schedule == .rotation { tree["cycle"] = .array(cycle) }

        default:
            return invalid()
        }
        tree["days"] = .array(days)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(RawJSON.object(tree)),
              let text = String(data: data, encoding: .utf8) else { return invalid() }
        return (text, issues)
    }

    /// The structural change, before the pipeline gets to say whether it is legal.
    private static func mutated(_ operation: Operation, _ plan: Plan) -> Plan? {
        var plan = plan
        switch operation {
        case let .renameExercise(day, exercise, name):
            guard let target = exerciseIndex(plan, day, exercise), !name.trimmed.isEmpty else { return nil }
            plan.days[target.day].exercises[target.exercise].name = String(name.trimmed.prefix(100))

        case let .setSetCount(day, exercise, count):
            guard let target = exerciseIndex(plan, day, exercise), (1...50).contains(count) else { return nil }
            var sets = plan.days[target.day].exercises[target.exercise].sets
            guard let last = sets.last else { return nil }
            // Growing repeats the last set, which is what "one more set" means in a pyramid too.
            while sets.count < count { sets.append(last) }
            if sets.count > count { sets.removeLast(sets.count - count) }
            plan.days[target.day].exercises[target.exercise].sets = sets

        case let .setWeight(day, exercise, weight):
            guard let target = exerciseIndex(plan, day, exercise) else { return nil }
            if let weight, !(0...10_000).contains(weight) { return nil }
            for index in plan.days[target.day].exercises[target.exercise].sets.indices {
                plan.days[target.day].exercises[target.exercise].sets[index].weight = weight
            }

        case let .setReps(day, exercise, text):
            guard let target = exerciseIndex(plan, day, exercise),
                  let work = parseWork(text) else { return nil }
            for index in plan.days[target.day].exercises[target.exercise].sets.indices {
                plan.days[target.day].exercises[target.exercise].sets[index].work = work
            }

        case let .setRepRange(day, exercise, text):
            guard let target = exerciseIndex(plan, day, exercise) else { return nil }
            guard let text, !text.trimmed.isEmpty else {
                plan.days[target.day].exercises[target.exercise].repRange = nil
                break
            }
            guard let range = parseRange(text) else { return nil }
            plan.days[target.day].exercises[target.exercise].repRange = range

        case let .setRest(day, exercise, seconds):
            guard let target = exerciseIndex(plan, day, exercise), (0...3600).contains(seconds) else { return nil }
            for index in plan.days[target.day].exercises[target.exercise].sets.indices {
                plan.days[target.day].exercises[target.exercise].sets[index].restSeconds = seconds
            }
            // Rest resolution reads `groupRestSeconds`, not the per-set value, for anything in
            // a superset (§6.3). Editing one member's rest is therefore an edit to the round
            // rest the whole group shares — changing only the per-set value would have looked
            // like it worked and changed nothing.
            for member in groupMembers(plan, target) {
                for index in plan.days[target.day].exercises[member].sets.indices {
                    plan.days[target.day].exercises[member].sets[index].groupRestSeconds = seconds
                }
            }

        case let .moveExercise(day, from, to):
            guard plan.days.indices.contains(day) else { return nil }
            var exercises = plan.days[day].exercises
            guard exercises.indices.contains(from), (0...exercises.count - 1).contains(to) else { return nil }
            let moving = exercises.remove(at: from)
            exercises.insert(moving, at: to)
            plan.days[day].exercises = exercises

        case let .deleteExercise(day, exercise):
            guard let target = exerciseIndex(plan, day, exercise),
                  plan.days[target.day].exercises.count > 1 else { return nil }
            plan.days[target.day].exercises.remove(at: target.exercise)

        case let .duplicateDay(day):
            guard plan.days.indices.contains(day), plan.days.count < 31 else { return nil }
            var copy = plan.days[day]
            copy.id = UUID()
            // Named rather than left to the importer's duplicate-name suffix, so the copy says
            // what it is. It is deliberately not added to the cycle: duplicating a day is not a
            // request to change how often you train.
            copy.name = String("\(copy.name) copy".prefix(100))
            copy.exercises = copy.exercises.map { var e = $0; e.id = UUID(); return e }
            plan.days.insert(copy, at: day + 1)

        case let .renameDay(day, name):
            guard plan.days.indices.contains(day), !name.trimmed.isEmpty else { return nil }
            // `CycleEntry.day` holds an index, not a name, so the cycle needs no fixup here;
            // `PlanJSON.render` writes the day's current name into it on the way out.
            plan.days[day].name = String(name.trimmed.prefix(100))

        case .replaceExerciseJSON, .replaceDayJSON, .insertExercisesJSON, .insertDaysJSON:
            // Text edits are spliced (`spliced`), never mutated here.
            return nil
        }
        return plan
    }

    /// The contiguous run of exercises sharing `target`'s group tag, or nothing when it has none.
    /// The importer only ever groups a contiguous run, so this is the same span it grouped.
    private static func groupMembers(_ plan: Plan, _ target: (day: Int, exercise: Int)) -> [Int] {
        let exercises = plan.days[target.day].exercises
        guard let group = exercises[target.exercise].group else { return [] }
        var first = target.exercise, last = target.exercise
        while first > 0, exercises[first - 1].group == group { first -= 1 }
        while last + 1 < exercises.count, exercises[last + 1].group == group { last += 1 }
        return Array(first...last)
    }

    private static func exerciseIndex(_ plan: Plan, _ day: Int, _ exercise: Int) -> (day: Int, exercise: Int)? {
        guard plan.days.indices.contains(day),
              plan.days[day].exercises.indices.contains(exercise) else { return nil }
        return (day, exercise)
    }

    /// The one field that says what a set is, in text. A trailing "s" means seconds, so the
    /// four shapes the plan format keeps in two different JSON keys stay distinguishable here:
    ///
    ///     10      8-12    AMRAP    5+          reps
    ///     45s     30s+    open                 time
    ///
    /// `text(for:)` is its inverse — every `WorkTarget` prints as something this parses back to
    /// the same value (L45), so opening the edit sheet and saving it cannot silently change a
    /// timed set into a rep set.
    static func parseWork(_ text: String) -> WorkTarget? {
        let value = text.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        // Open duration, no minimum. "max" is deliberately not here: the plan format lets it
        // mean either, and in a field you type reps into, reps is the commoner meaning.
        if ["open", "amsap", "as long as possible"].contains(value) {
            return .openDuration(minSeconds: nil)
        }
        if value == "max" || value == "amrap" || value == "failure" { return .reps(.amrap(min: nil)) }
        // "30s+": an open hold with a minimum.
        if value.hasSuffix("s+"), let minimum = Int(value.dropLast(2)), (1...86_400).contains(minimum) {
            return .openDuration(minSeconds: minimum)
        }
        if value.hasSuffix("s"), let seconds = Int(value.dropLast()), (1...86_400).contains(seconds) {
            return .duration(seconds: seconds)
        }
        if let range = parseRange(value) { return .reps(.range(min: range.min, max: range.max)) }
        if value.hasSuffix("+"), let minimum = Int(value.dropLast()), minimum > 0 {
            return .reps(.amrap(min: minimum))
        }
        if let reps = Int(value), (0...999).contains(reps) { return .reps(.fixed(reps)) }
        return nil
    }

    /// What the edit sheet shows for a target, in the vocabulary `parseWork` accepts back.
    static func text(for work: WorkTarget) -> String {
        switch work {
        case let .duration(seconds): return "\(seconds)s"
        case let .openDuration(minimum): return minimum.map { "\($0)s+" } ?? "open"
        case let .reps(target):
            switch target {
            case let .fixed(n): return "\(n)"
            case let .range(low, high): return "\(low)-\(high)"
            case let .amrap(minimum): return minimum.map { "\($0)+" } ?? "AMRAP"
            }
        }
    }

    /// "8-12" or "8–12".
    static func parseRange(_ text: String) -> RepRange? {
        let parts = text.trimmed.replacingOccurrences(of: "–", with: "-").split(separator: "-")
        guard parts.count == 2, let low = Int(String(parts[0]).trimmed), let high = Int(String(parts[1]).trimmed),
              low > 0, high >= low, high <= 999 else { return nil }
        return RepRange(min: low, max: high)
    }
}
