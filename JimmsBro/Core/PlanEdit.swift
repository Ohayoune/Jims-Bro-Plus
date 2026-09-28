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
        if let walk = plan.restBetweenExercises { out += "  \"restBetweenExercises\": \(walk),\n" }
        out += "  \"schedule\": \"\(plan.schedule.rawValue)\",\n"
        if !plan.cycle.isEmpty {
            out += "  \"cycle\": [\(plan.cycleNames.map { string($0 ?? "rest") }.joined(separator: ", "))],\n"
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
        if let weight = target.weight { fields.append("              \"weight\": \(TargetText.number(weight))") }
        fields.append("              \"restSeconds\": \(target.restSeconds)")
        // D51 (v1.5): the effort target, per set — the importer defaults it from the exercise,
        // but the rendering is the explicit form, so every set says its own.
        if let reserve = target.inReserve { fields.append("              \"inReserve\": \(reserve)") }
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
                if let weight = drop.weight { parts.append("                  \"weight\": \(TargetText.number(weight))") }
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

    /// A JSON string literal. Only the escapes JSON requires; plan text is ordinary prose. The
    /// one escaper (D96): every piece of JSON the app writes by hand quotes its text here.
    static func string(_ value: String) -> String {
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
    /// E_EDIT_INVALID: the operation names a day, exercise or set the plan does not have.
    static let notApplicable = Issue(severity: .error, code: "E_EDIT_INVALID", path: "",
                                     message: "That edit doesn't apply to this plan.")

    enum Operation: Equatable {
        case renameExercise(day: Int, exercise: Int, name: String)
        case setSetCount(day: Int, exercise: Int, count: Int)
        case setWeight(day: Int, exercise: Int, weight: Double?)
        case setReps(day: Int, exercise: Int, text: String)
        case setRepRange(day: Int, exercise: Int, text: String?)
        case setRest(day: Int, exercise: Int, seconds: Int)
        /// D51 (v1.5): the effort target for every set of the exercise; nil clears it.
        case setInReserve(day: Int, exercise: Int, value: Int?)
        /// D96 (v1.12 L6): the exercise sheet's Save — every field it changed, as one edit and
        /// one pipeline run. The sheet sent one operation per field until then: N runs, N writes,
        /// and a refusal part-way left the fields before it saved and the ones after it not.
        case editExercise(day: Int, exercise: Int, changes: [ExerciseChange])
        case moveExercise(day: Int, from: Int, to: Int)
        case deleteExercise(day: Int, exercise: Int)
        case duplicateDay(day: Int)
        case renameDay(day: Int, name: String)
        /// Plan detail's Rename. An edit like the others (v1.12's review), so the plan's text says
        /// the new name: set beside it, the text kept the old one, and Edit the text saved it back.
        case renamePlan(name: String)
        /// D43 (v1.3): the JSON edits. Each takes text, spliced into the plan's own JSON and
        /// re-imported, so the errors it can raise are the import pipeline's, with full paths.
        case replaceExerciseJSON(day: Int, exercise: Int, text: String)
        case replaceDayJSON(day: Int, text: String)
        /// Appended to the day (`at` nil) or inserted before the exercise at `at`.
        case insertExercisesJSON(day: Int, at: Int?, text: String)
        /// Appended after the last day, and added to a rotation's repeat block.
        case insertDaysJSON(text: String)
        /// D95, F1 (v1.12): the whole plan's text — Plan detail's **Edit the text** — read as a
        /// paste and carried as an edit. A text that names no unit keeps the plan's (D57 asks only
        /// on a new plan's review).
        case replacePlanJSON(text: String)
    }

    /// The edited plan, or the errors that stopped it. The plan keeps its id, its position in
    /// the cycle, the date the cycle is anchored to (D37) and its original import date — it is
    /// the same plan, changed, not a new one.
    static func apply(_ operation: Operation, to plan: Plan, settings: Settings,
                      now: Date = Date()) -> ImportResult {
        let text: String
        // The plan as the edit left it, before the importer reads it back: its day names are the
        // re-import's, so the cycle's place, which follows its day by name, follows a rename.
        var edited = plan
        switch operation {
        case .replaceExerciseJSON, .replaceDayJSON, .insertExercisesJSON, .insertDaysJSON:
            let splice = spliced(plan, operation)
            guard let spliced = splice.text else { return ImportResult(plan: nil, issues: splice.issues) }
            text = spliced
        case let .replacePlanJSON(whole):
            text = whole
        default:
            guard let changed = mutated(operation, plan) else {
                return ImportResult(plan: nil, issues: [notApplicable])
            }
            edited = changed
            text = PlanJSON.render(edited)
        }
        var result = PlanImport.run(text, settings: settings, now: now)
        guard let reimported = result.planKeepingUnits(of: plan) else { return result }
        // A day pasted in its own place keeps it, and a renamed one took its old name's place in
        // the repeat block (`spliced`).
        if case let .replaceDayJSON(day, _) = operation, let renamed = reimported.days[safe: day] {
            edited.days[day].name = renamed.name
        }
        // D96 (v1.12 L3): an edit, as Apply is — the id, the import date, the cycle's place and its
        // anchor (v1.3: an edit used to drop the anchor, and the calendar moved), the progression
        // (D44), and the canonical text: a spliced tree is JSON in the encoder's key order.
        result.plan = edited.carried(into: reimported, as: .edit)
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
        let read = located(text, as: kind)
        return (read.values?.map(\.value), read.issues)
    }

    /// D77 (v1.9): one value of a fragment, and where the reader found it in the JSON — `[]` for
    /// the whole of it, `[1]`, `days[0]`, `[0].exercises[2]` — so the JSON sheet can mark the line
    /// an error names. Nil for a day made here out of loose exercises, which no line of the text is.
    struct Located {
        var value: RawJSON
        var origin: [JSONLocator.Component]?
    }

    /// `fragment(_:as:)`, keeping each value's origin: the one reading of a fragment's shape, so
    /// the place an error is marked is the place its value was read from.
    static func located(_ text: String, as kind: FragmentKind) -> (values: [Located]?, issues: [Issue]) {
        let extracted = PlanImport.extract(text)
        guard let body = extracted.value else { return (nil, extracted.issues) }
        let decoded = PlanImport.decode(body)
        guard let raw = decoded.value else { return (nil, extracted.issues + decoded.issues) }
        let issues = extracted.issues + decoded.issues
        func isDay(_ value: RawJSON) -> Bool { value.object?["exercises"] != nil }
        func isPlan(_ value: RawJSON) -> Bool { value.object?["days"] != nil }
        // The elements of `key` in `parent`, each found under its parent.
        func children(_ parent: Located, _ key: String) -> [Located] {
            (parent.value[key]?.array ?? []).enumerated().map { index, child in
                Located(value: child, origin: parent.origin.map { $0 + [.key(key), .index(index)] })
            }
        }
        let list: [Located]
        if let array = raw.array {
            list = array.enumerated().map { Located(value: $1, origin: [.index($0)]) }
        } else if raw.object != nil {
            list = [Located(value: raw, origin: [])]
        } else {
            return (nil, issues + [Issue(severity: .error, code: "E_NOT_A_PLAN", path: "",
                                         message: "This JSON isn't a workout plan. Use an object with days or exercises.")])
        }
        guard !list.isEmpty, list.allSatisfy({ $0.value.object != nil }) else {
            return (nil, issues + [Issue(severity: .error, code: "E_NOT_A_PLAN", path: "",
                                         message: "Paste an exercise, a day, or a list of them.")])
        }
        // Flatten whatever was pasted down to the shape asked for.
        let days: [Located] = list.flatMap { item -> [Located] in
            if isPlan(item.value) { return children(item, "days") }
            if isDay(item.value) { return [item] }
            return []
        }
        // An object that is neither a plan nor a day is an exercise when it says something an
        // exercise says; otherwise, read as days, it is a day with nothing in it, and the
        // importer's own sentence for that ("has no exercises") is the right refusal.
        let exerciseKeys: Set<String> = ["reps", "durationSeconds", "sets", "weight", "repRange",
                                         "bodyweight", "drops", "group", "warningBeep", "restSeconds",
                                         "inReserve", "rir"]
        func isExerciseLike(_ value: RawJSON) -> Bool {
            !Set(value.object?.keys.map { $0 } ?? []).isDisjoint(with: exerciseKeys)
        }
        let loose = list.filter { !isPlan($0.value) && !isDay($0.value) }
        switch kind {
        case .exercises:
            return (days.flatMap { children($0, "exercises") } + loose, issues)
        case .days:
            let exercises = loose.filter { isExerciseLike($0.value) }
            let bare = loose.filter { !isExerciseLike($0.value) }
            let gathered: [Located] = exercises.isEmpty ? []
                : [Located(value: .object(["exercises": .array(exercises.map(\.value))]), origin: nil)]
            return (days + bare + gathered, issues)
        }
    }

    /// The plan's own JSON with the fragment spliced in, ready for the import pipeline, or the
    /// errors that stopped it. Works on the tree rather than the text so a fragment lands at a
    /// real path and the pipeline's errors name it — `days[1].exercises[2].sets[0].reps`.
    static func spliced(_ plan: Plan, _ operation: Operation) -> (text: String?, issues: [Issue]) {
        func invalid() -> (String?, [Issue]) { (nil, [notApplicable]) }
        guard var tree = PlanImport.decode(PlanJSON.render(plan)).value?.object,
              var days = tree["days"]?.array else { return invalid() }
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
        let text = RawJSON.object(tree).jsonText
        guard !text.isEmpty else { return invalid() }
        return (text, issues)
    }

    /// The structural change, before the pipeline gets to say whether it is legal.
    private static func mutated(_ operation: Operation, _ plan: Plan) -> Plan? {
        var plan = plan
        switch operation {
        case let .renameExercise(day, exercise, name):
            guard let target = exerciseIndex(plan, day, exercise), let name = TargetGrammar.cleanName(name) else { return nil }
            plan.days[target.day].exercises[target.exercise].name = name

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
            if let weight, !TargetGrammar.isWeight(weight) { return nil }
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

        case let .setInReserve(day, exercise, value):
            guard let target = exerciseIndex(plan, day, exercise) else { return nil }
            if let value, !(0...20).contains(value) { return nil }
            for index in plan.days[target.day].exercises[target.exercise].sets.indices {
                plan.days[target.day].exercises[target.exercise].sets[index].inReserve = value
            }

        case let .editExercise(day, exercise, changes):
            // Each field as its own edit makes it, in the order the sheet lists them, so a rest
            // in a superset still reaches the round (`setRest`); all of them or none.
            for change in changes {
                guard let next = mutated(change.operation(day: day, exercise: exercise), plan) else { return nil }
                plan = next
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
            copy.name = TargetGrammar.cleanName("\(copy.name) copy") ?? copy.name
            copy.exercises = copy.exercises.map { var e = $0; e.id = UUID(); return e }
            plan.days.insert(copy, at: day + 1)

        case let .renameDay(day, name):
            guard plan.days.indices.contains(day), let name = TargetGrammar.cleanName(name) else { return nil }
            // `CycleEntry.day` holds an index, not a name, so the cycle needs no fixup here;
            // `PlanJSON.render` writes the day's current name into it on the way out.
            plan.days[day].name = name

        case let .renamePlan(name):
            guard let name = TargetGrammar.cleanName(name) else { return nil }
            plan.name = name

        case .replaceExerciseJSON, .replaceDayJSON, .insertExercisesJSON, .insertDaysJSON, .replacePlanJSON:
            // Text edits are spliced (`spliced`) or read whole, never mutated here.
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
        // Open duration, no minimum. The words that mean either in the plan format ("max",
        // "to failure") are reps here: in a field you type reps into, reps is the commoner meaning.
        if TargetGrammar.openHoldWords.subtracting(TargetGrammar.amrapWords).contains(value) {
            return .openDuration(minSeconds: nil)
        }
        // "30s+": an open hold with a minimum.
        if value.hasSuffix("s+"), let minimum = Int(value.dropLast(2)), TargetGrammar.seconds.contains(minimum) {
            return .openDuration(minSeconds: minimum)
        }
        if value.hasSuffix("s"), let seconds = Int(value.dropLast()), TargetGrammar.seconds.contains(seconds) {
            return .duration(seconds: seconds)
        }
        // Reps as the plan format reads them — except a range written high to low, which the
        // sheet refuses rather than swaps: it has no warning to say so.
        guard let read = TargetGrammar.reps(value), !read.swapped else { return nil }
        return .reps(read.target)
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

    /// A rep range as a plan's `repRange` is read — "8-12", "8–12", "8 to 12", or one number
    /// for a range of one — except written high to low, which the sheet refuses.
    static func parseRange(_ text: String) -> RepRange? {
        guard let read = TargetGrammar.reps(text, rangeOnly: true), !read.swapped else { return nil }
        return TargetGrammar.range(read.target)
    }
}

// MARK: - D29, D93 (v1.11): the exercise sheet's fields, in two forms

extension PlanEdit {
    /// One field of the exercise sheet that changed, with no address: the operation form turns it
    /// into a `PlanEdit.Operation` for an exercise of a saved plan, the value form applies it to
    /// an exercise that belongs to no plan (a day written for one date, D93).
    enum ExerciseChange: Equatable {
        case name(String)
        case setCount(Int)
        case reps(String)
        case range(String?)
        case weight(Double?)
        case rest(Int)
        case inReserve(Int?)

        func operation(day: Int, exercise: Int) -> Operation {
            switch self {
            case let .name(name): return .renameExercise(day: day, exercise: exercise, name: name)
            case let .setCount(count): return .setSetCount(day: day, exercise: exercise, count: count)
            case let .reps(text): return .setReps(day: day, exercise: exercise, text: text)
            case let .range(text): return .setRepRange(day: day, exercise: exercise, text: text)
            case let .weight(weight): return .setWeight(day: day, exercise: exercise, weight: weight)
            case let .rest(seconds): return .setRest(day: day, exercise: exercise, seconds: seconds)
            case let .inReserve(value): return .setInReserve(day: day, exercise: exercise, value: value)
            }
        }
    }

    /// The exercise sheet's fields as the sheet holds them — text, and a count — so what it can
    /// save, and what saving changes, is decided here rather than in the view (SPEC §4.3, D29).
    struct ExerciseFields: Equatable {
        var name: String
        var sets: Int
        var reps: String
        var range: String
        var weight: String
        var rest: String
        /// D51 (v1.5): the effort target, empty when the plan did not say.
        var reserve: String

        /// The fields as the sheet opens on `exercise`.
        init(_ exercise: Exercise) {
            name = exercise.name
            sets = exercise.sets.count
            reps = exercise.sets.first.map { PlanEdit.text(for: $0.work) } ?? ""
            range = exercise.repRange.map { "\($0.min)-\($0.max)" } ?? ""
            weight = InputRules.weightText(exercise.sets.first?.weight)
            rest = exercise.sets.first.map { String($0.restSeconds) } ?? ""
            reserve = exercise.sets.first?.inReserve.map(String.init) ?? ""
        }

        var canSave: Bool {
            !name.trimmed.isEmpty
                && PlanEdit.parseWork(reps) != nil
                && (range.trimmed.isEmpty || PlanEdit.parseRange(range) != nil)
                && (rest.isEmpty || InputRules.secondsValue(rest).map { (0...3600).contains($0) } == true)
                && (reserve.isEmpty || Int(reserve).map { (0...20).contains($0) } == true)
        }

        /// Only the fields that actually changed from `exercise`, so an untouched exercise is
        /// untouched — in the order the sheet has always committed them.
        func changes(from exercise: Exercise) -> [ExerciseChange] {
            var changes: [ExerciseChange] = []
            if name.trimmed != exercise.name { changes.append(.name(name)) }
            if sets != exercise.sets.count { changes.append(.setCount(sets)) }
            if let work = PlanEdit.parseWork(reps), work != exercise.sets.first?.work { changes.append(.reps(reps)) }
            let newRange = range.trimmed.isEmpty ? nil : PlanEdit.parseRange(range)
            if newRange != exercise.repRange { changes.append(.range(range.trimmed.isEmpty ? nil : range)) }
            let newWeight = InputRules.weightValue(weight)
            if newWeight != exercise.sets.first?.weight { changes.append(.weight(newWeight)) }
            if let seconds = InputRules.secondsValue(rest), seconds != exercise.sets.first?.restSeconds {
                changes.append(.rest(seconds))
            }
            let newReserve = reserve.isEmpty ? nil : Int(reserve)
            if newReserve != exercise.sets.first?.inReserve { changes.append(.inReserve(newReserve)) }
            return changes
        }
    }

    /// The value form (D93): `changes` applied to `exercise` alone, by the same structural edits
    /// the operation form makes, without the pipeline — the caller runs that on the whole day
    /// (`ChangeDay.ownDay`), where an exercise out of its day cannot be judged. Nil when a change
    /// does not apply, as the operation form refuses it with `E_EDIT_INVALID`.
    static func edited(_ exercise: Exercise, _ changes: [ExerciseChange]) -> Exercise? {
        let plan = Plan(name: "", units: .kg, schedule: .rotation, days: [Day(name: "", exercises: [exercise])],
                        importedAt: Date(timeIntervalSince1970: 0), sourceText: "", cycle: [.day(0)])
        return mutated(.editExercise(day: 0, exercise: 0, changes: changes), plan)?.days.first?.exercises.first
    }
}
