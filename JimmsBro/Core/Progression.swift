import Foundation

/// SPEC §6.21 (D44, v1.3): **Progression** — the chatbot round-trip run the other way. The app
/// writes out what the plan is and what you have actually done, the chatbot plans the next N
/// weeks, and the plan carries the answer week by week.
///
/// The week is calendar weeks from the start date. `Session.start` applies the current week's
/// targets to the day's snapshot (D7 holds: the session records what it was asked to do), and
/// everything downstream — prefill, the chip, advice, the Summary — reads the snapshot.
extension Progression {
    static let maxWeeks = 52
    static let periods = [4, 6, 8, 12]

    /// 0-based week on `date`, or nil before the start and after the last week.
    func weekIndex(on date: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: start, to: day).day, days >= 0 else { return nil }
        let week = days / 7
        return week < weeks ? week : nil
    }

    /// The day after the last week.
    func endDate(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: startDate)) ?? startDate
    }

    /// Calendar mode: the day after the last week. Performance mode (D53, v1.5): every entry
    /// past its last step — the calendar has nothing to say.
    func isFinished(on date: Date, calendar: Calendar = .current) -> Bool {
        switch mode {
        case .calendar: return calendar.startOfDay(for: date) >= endDate(calendar: calendar)
        case .performance: return entries.allSatisfy { $0.step >= $0.weeks.count }
        }
    }

    /// D53 (v1.5): the 0-based step an entry is on — the calendar week in calendar mode, its
    /// own earned step in performance mode; nil once it is past its last.
    func stepIndex(for entry: ProgressionEntry, on date: Date, calendar: Calendar = .current) -> Int? {
        switch mode {
        case .calendar: return weekIndex(on: date, calendar: calendar)
        case .performance: return entry.step < entry.weeks.count ? entry.step : nil
        }
    }

    /// The step to say for a day, or for the whole plan: the calendar week, or the lowest
    /// earned step among the entries still climbing. Nil when nothing is in progress.
    func currentStep(dayName: String? = nil, on date: Date, calendar: Calendar = .current) -> Int? {
        switch mode {
        case .calendar:
            return weekIndex(on: date, calendar: calendar)
        case .performance:
            let relevant = entries.filter { entry in dayName.map { normalized(entry.dayName) == normalized($0) } ?? true }
            return relevant.compactMap { $0.step < $0.weeks.count ? $0.step : nil }.min()
        }
    }

    /// D53 (v1.5): the day with each entry's *own* step applied, and the 1-based step per
    /// exercise index. In calendar mode every entry is on the same week and a step that
    /// changes nothing touches nothing, as in v1.3; in performance mode an entry on a step is
    /// counted even when the step is `{}`, because the workout still has to earn it against
    /// the plan's own targets.
    func apply(to day: Day, on date: Date, calendar: Calendar = .current) -> (day: Day, steps: [Int: Int]) {
        var result = day
        var steps: [Int: Int] = [:]
        for index in day.exercises.indices {
            guard let entry = entry(day: day.name, exercise: day.exercises[index].name),
                  let stepIndex = stepIndex(for: entry, on: date, calendar: calendar),
                  let change = entry.weeks[safe: stepIndex] else { continue }
            if change.isChange {
                result.exercises[index] = applied(change, to: day.exercises[index])
            } else if mode == .calendar {
                continue
            }
            steps[index] = stepIndex + 1
        }
        return (result, steps)
    }

    func entry(day: String, exercise: String) -> ProgressionEntry? {
        entries.first { normalized($0.dayName) == normalized(day) && normalized($0.exerciseName) == normalized(exercise) }
    }

    /// The day with the week's targets applied, and which exercises it touched. An exercise,
    /// week or set the progression says nothing about keeps the plan's own target. A range of
    /// reps also becomes the rep range advice judges by; a bodyweight exercise ignores weights.
    func apply(to day: Day, week: Int) -> (day: Day, touched: Set<Int>) {
        var result = day
        var touched = Set<Int>()
        for index in day.exercises.indices {
            guard let entry = entry(day: day.name, exercise: day.exercises[index].name),
                  let change = entry.weeks[safe: week], change.isChange else { continue }
            result.exercises[index] = applied(change, to: day.exercises[index])
            touched.insert(index)
        }
        return (result, touched)
    }

    /// One step's change written into an exercise's sets.
    private func applied(_ change: ProgressionWeek, to original: Exercise) -> Exercise {
        var exercise = original
        if let sets = change.sets, !sets.isEmpty {
            for (position, override) in sets.enumerated() where exercise.sets.indices.contains(position) {
                if let weight = override.weight, !exercise.bodyweight { exercise.sets[position].weight = weight }
                if let work = override.work { exercise.sets[position].work = work }
            }
        } else {
            for position in exercise.sets.indices {
                if let weight = change.weight, !exercise.bodyweight { exercise.sets[position].weight = weight }
                if let work = change.work { exercise.sets[position].work = work }
            }
        }
        if case let .reps(.range(low, high))? = change.work { exercise.repRange = RepRange(min: low, max: high) }
        return exercise
    }
}

/// D53 (v1.5): steps you earn. An exercise moves to its next step when a workout achieves the
/// current one; miss it and the step repeats.
enum ProgressionSteps {
    /// The one-rep slack the advice already allows (§6.11).
    static let tolerance = 1

    /// Whether the exercise's sets, as logged, met their targets: every main set logged, the
    /// reps summed across the exercise at or above the targets summed (the top of a range, the
    /// minimum of an AMRAP) less the one-rep tolerance — the advice's own arithmetic (§6.11) —
    /// every weight at or above the set's, every hold held for its seconds. The targets are
    /// the session's own snapshot, which in a progression step *is* the step.
    static func achieved(exercise: SessionExercise, steps: [SessionStep]) -> Bool {
        let main = steps.filter { $0.dropIndex == 0 }
        guard !main.isEmpty, main.allSatisfy({ $0.status == .logged }) else { return false }
        var done = 0, ceiling = 0
        for step in main {
            guard let target = exercise.targets[safe: step.setIndex], let result = step.result else { return false }
            switch target.work {
            case let .reps(reps):
                switch reps {
                case let .fixed(n): ceiling += n
                case let .range(_, high): ceiling += high
                case let .amrap(minimum): ceiling += minimum ?? 0
                }
                done += result.reps ?? 0
                if !exercise.bodyweight, let planned = target.weight, (result.weight ?? 0) + 0.001 < planned { return false }
            case let .duration(seconds):
                if (result.seconds ?? 0) < seconds { return false }
            case let .openDuration(minimum):
                if (result.seconds ?? 0) < (minimum ?? 0) { return false }
            }
        }
        return done >= ceiling - tolerance
    }

    /// After a workout, every exercise that was at its step moves on or tries again. Only an
    /// exercise the session stamped with the entry's current step counts — a session started
    /// before the step moved, or one of a substitute (D42), changes nothing. Returns the names
    /// that moved.
    @discardableResult
    static func advance(_ progression: inout Progression, after session: Session) -> [String] {
        guard progression.mode == .performance else { return [] }
        var moved: [String] = []
        for (index, exercise) in session.exercises.enumerated() {
            guard let step = exercise.progressionWeek,
                  let position = progression.entries.firstIndex(where: {
                      normalized($0.dayName) == normalized(session.dayName)
                          && normalized($0.exerciseName) == normalized(exercise.name) }),
                  progression.entries[position].step == step - 1 else { continue }
            let steps = session.steps.filter { $0.exerciseIndex == index }
            if achieved(exercise: exercise, steps: steps) {
                progression.entries[position].step += 1
                progression.entries[position].tries = 0
                moved.append(exercise.name)
            } else {
                progression.entries[position].tries += 1
            }
        }
        return moved
    }
}

/// What the screens say about a progression, resolved here so the wording is a unit test.
enum ProgressionText {
    /// "Week 3 of 8", "Finished", or nil before it starts (which cannot happen: it starts the
    /// day it is saved).
    static func status(_ progression: Progression, on date: Date, calendar: Calendar = .current) -> String {
        if let index = progression.currentStep(on: date, calendar: calendar) {
            return "\(word(progression.mode)) \(index + 1) of \(progression.weeks)"
        }
        return progression.isFinished(on: date, calendar: calendar) ? "Finished" : "Starts soon"
    }

    /// "Week" in calendar mode, "Step" in performance mode (D53).
    static func word(_ mode: ProgressionMode) -> String { mode == .performance ? "Step" : "Week" }

    /// The chip's reason: "Week 3 of 8 of your progression", or "Step 3 of 8 …" (D53).
    static func reason(week: Int, of weeks: Int?, mode: ProgressionMode = .calendar) -> String {
        weeks.map { "\(word(mode)) \(week) of \($0) of your progression" } ?? "\(word(mode)) \(week) of your progression"
    }

    /// "week 3 of 8" — or "step 3 of 8" — for a session that carried one, else nil.
    static func weekLine(_ session: Session) -> String? {
        guard let week = session.progressionWeek else { return nil }
        let noun = word(session.progressionMode ?? .calendar).lowercased()
        return session.progressionWeeks.map { "\(noun) \(week) of \($0)" } ?? "\(noun) \(week)"
    }

    /// D53: an entry's ladder with the current step marked: "1) 8 × 80 kg · ▸ 2) 8 × 82.5 kg · 3) same".
    static func ladder(_ entry: ProgressionEntry, units: WeightUnit, bodyweight: Bool, current: Int?) -> String {
        entry.weeks.enumerated().map { offset, week in
            (offset == current ? "▸ " : "") + "\(offset + 1)) \(change(week, units: units, bodyweight: bodyweight))"
        }.joined(separator: " · ")
    }

    /// D53: "Step 3 of 8", "Step 3 of 8 · 2 tries", or "Done" once an entry is past its last.
    static func entryStatus(_ entry: ProgressionEntry, of weeks: Int) -> String {
        guard entry.step < entry.weeks.count else { return "Done" }
        var text = "Step \(entry.step + 1) of \(weeks)"
        if entry.tries > 0 { text += " · \(entry.tries) \(entry.tries == 1 ? "try" : "tries")" }
        return text
    }

    /// One week's change, as a target: "8 × 82.5 kg", "82.5 kg", "8–12", "45 s", "60 / 65 / 70 kg",
    /// or "same" for a week that changes nothing.
    static func change(_ week: ProgressionWeek, units: WeightUnit, bodyweight: Bool) -> String {
        guard week.isChange else { return "same" }
        if let sets = week.sets, !sets.isEmpty {
            let parts = sets.map { set -> String in
                let weight = bodyweight ? nil : set.weight
                switch (set.work, weight) {
                case let (work?, weight?): return "\(TargetText.work(work, wording: .compact)) · \(TargetText.number(weight))"
                case let (work?, nil): return TargetText.work(work, wording: .compact)
                case let (nil, weight?): return TargetText.number(weight)
                case (nil, nil): return "–"
                }
            }
            var text = parts.joined(separator: " / ")
            if !bodyweight, sets.contains(where: { $0.weight != nil }) { text += " \(units.rawValue)" }
            return text
        }
        let weight = bodyweight ? nil : week.weight
        switch (week.work, weight) {
        case let (work?, weight?): return "\(TargetText.work(work, wording: .compact)) × \(TargetText.number(weight)) \(units.rawValue)"
        case let (work?, nil): return TargetText.work(work, wording: .compact)
        case let (nil, weight?): return "\(TargetText.number(weight)) \(units.rawValue)"
        case (nil, nil): return "same"
        }
    }

    /// An entry's weeks in one line: "w1 8 × 80 kg · w2 8 × 82.5 kg · w3 same".
    static func weeksLine(_ entry: ProgressionEntry, units: WeightUnit, bodyweight: Bool) -> String {
        entry.weeks.enumerated()
            .map { "w\($0.offset + 1) \(change($0.element, units: units, bodyweight: bodyweight))" }
            .joined(separator: " · ")
    }
}

/// The reply, read with the import pipeline's leniency and matched to the plan.
/// `docs/PROGRESSION_FORMAT.md` is the contract; the codes are listed there.
enum ProgressionImport {
    static let promptMarker = "JIMMSBRO-PROGRESSION-PROMPT-V1"

    struct Result: Equatable {
        var progression: Progression?
        var issues: [Issue]
        var errors: [Issue] { issues.filter { $0.severity == .error } }
    }

    /// `mode` is the user's choice on the planning screen (D53), not the reply's.
    static func run(_ text: String, plan: Plan, settings: Settings, now: Date = Date(),
                    calendar: Calendar = .current, mode: ProgressionMode = .calendar) -> Result {
        func failure(_ code: String, _ path: String, _ message: String) -> Result {
            Result(progression: nil, issues: [Issue(severity: .error, code: code, path: path, message: message)])
        }
        // The plan importer checks for *its* marker; this reply has its own.
        if text.contains(promptMarker), !text.contains("```") {
            return failure("E_PROMPT_PASTED", "", "That's the prompt. Paste the chatbot's JSON reply instead.")
        }
        let extracted = PlanImport.extract(text)
        guard let body = extracted.value else { return Result(progression: nil, issues: extracted.issues) }
        let decoded = PlanImport.decode(body)
        guard let raw = decoded.value else { return Result(progression: nil, issues: extracted.issues + decoded.issues) }
        var issues = extracted.issues + decoded.issues
        func issue(_ code: String, _ path: String, _ message: String) {
            issues.append(Issue(severity: code.hasPrefix("E_") ? .error : .warning, code: code, path: path, message: message))
        }

        // The object, wherever it was put: under "progression", bare, or as a bare list.
        var root: RawJSON = raw["progression"] ?? raw
        if let list = root.array { root = .object(["exercises": .array(list)]) }
        guard let object = root.object else {
            return failure("E_PROGRESSION_INVALID", "", "That's valid JSON, but it isn't a progression.")
        }
        for key in object.keys where !["schemaVersion", "weeks", "steps", "exercises", "progression"].contains(key) {
            issue("W_UNKNOWN_FIELD", key, "Unknown field \"\(key)\" was ignored.")
        }
        // D53 (v1.5): the reply says "steps"; v1.3's "weeks" is read as the same thing.
        var aliasUsed = false
        func stepsKey(_ fields: RawJSON) -> String? {
            if fields["steps"] != nil { return "steps" }
            if fields["weeks"] != nil { aliasUsed = true; return "weeks" }
            return nil
        }
        var declaredWeeks: Int?
        if let key = stepsKey(root), let weeks = root[key] {
            if let value = weeks.integer, (1...Progression.maxWeeks).contains(value) { declaredWeeks = value }
            else { issue("E_PROGRESSION_WEEKS_INVALID", key, "steps must be a whole number from 1 to \(Progression.maxWeeks), got \(weeks.display).") }
        }
        guard let list = root["exercises"]?.array, !list.isEmpty else {
            issue("E_PROGRESSION_INVALID", "exercises", "The reply has no exercises.")
            return Result(progression: nil, issues: issues)
        }
        let increment = settings.weightIncrement(for: plan.units)

        var entries: [ProgressionEntry] = []
        for (index, item) in list.enumerated() {
            let path = "exercises[\(index)]"
            guard let fields = item.object else {
                issue("E_PROGRESSION_EXERCISE_INVALID", path, "Each exercise must be an object with a name and weeks."); continue
            }
            for key in fields.keys where !["day", "name", "weeks", "steps", "notes"].contains(key) {
                issue("W_UNKNOWN_FIELD", "\(path).\(key)", "Unknown field \"\(key)\" was ignored.")
            }
            guard let name = item["name"]?.string?.trimmed, !name.isEmpty else {
                issue("E_PROGRESSION_EXERCISE_INVALID", "\(path).name", "This entry needs the exercise's name."); continue
            }
            let listKey = stepsKey(item) ?? "steps"
            guard let weeksList = item[listKey]?.array else {
                issue("E_PROGRESSION_WEEKS_INVALID", "\(path).\(listKey)", "Give \"\(name)\" a list of steps."); continue
            }
            let dayName = item["day"]?.string?.trimmed
            // Where in the plan this lands: the named day, or every day that has the exercise.
            var targets = plan.days.flatMap { day in
                day.exercises.filter { normalized($0.name) == normalized(name) }.map { (day: day.name, exercise: $0) }
            }
            if let dayName, !dayName.isEmpty { targets = targets.filter { normalized($0.day) == normalized(dayName) } }
            guard !targets.isEmpty else {
                let where_ = dayName.map { " on \($0)" } ?? ""
                issue("W_PROGRESSION_UNMATCHED", path, "\"\(name)\"\(where_) isn't in this plan; its progression was left out.")
                continue
            }
            if dayName == nil, Set(targets.map { normalized($0.day) }).count > 1 {
                issue("W_PROGRESSION_DAY_ASSUMED", path, "\"\(name)\" is on several days; the same progression was applied to each.")
            }

            var weeks: [ProgressionWeek] = []
            var valid = true
            for (offset, rawWeek) in weeksList.enumerated() {
                let weekPath = "\(path).\(listKey)[\(offset)]"
                guard let parsed = week(rawWeek, weekPath, issue: issue) else { valid = false; break }
                weeks.append(parsed)
            }
            guard valid else { continue }
            if let declaredWeeks {
                if weeks.count > declaredWeeks {
                    issue("W_PROGRESSION_LONG", "\(path).\(listKey)", "\"\(name)\" has \(weeks.count) steps; only the first \(declaredWeeks) are used.")
                    weeks = Array(weeks.prefix(declaredWeeks))
                } else if weeks.count < declaredWeeks {
                    issue("W_PROGRESSION_SHORT", "\(path).\(listKey)", "\"\(name)\" stops after step \(weeks.count); the plan's own targets apply after that.")
                }
            }
            for target in targets {
                var entry = ProgressionEntry(dayName: target.day, exerciseName: target.exercise.name, weeks: weeks)
                // Every weight the app will offer is loadable (D35); a bodyweight exercise has none.
                for w in entry.weeks.indices {
                    if target.exercise.bodyweight {
                        if entry.weeks[w].weight != nil || entry.weeks[w].sets?.contains(where: { $0.weight != nil }) == true {
                            issue("W_PROGRESSION_WEIGHT_IGNORED", "\(path).\(listKey)[\(w)]", "\"\(name)\" is bodyweight; its weights were ignored.")
                        }
                        entry.weeks[w].weight = nil
                        entry.weeks[w].sets = entry.weeks[w].sets?.map { ProgressionSet(weight: nil, work: $0.work) }
                        continue
                    }
                    if let weight = entry.weeks[w].weight {
                        let snapped = WeightRounding.snap(weight, increment: increment)
                        if snapped != weight {
                            issue("W_PROGRESSION_ROUNDED", "\(path).\(listKey)[\(w)].weight", "Rounded \(TargetText.number(weight)) to \(TargetText.number(snapped)) \(plan.units.rawValue), the smallest change your equipment makes.")
                            entry.weeks[w].weight = snapped
                        }
                    }
                    if let sets = entry.weeks[w].sets {
                        entry.weeks[w].sets = sets.enumerated().map { s, set in
                            guard let weight = set.weight else { return set }
                            let snapped = WeightRounding.snap(weight, increment: increment)
                            if snapped != weight {
                                issue("W_PROGRESSION_ROUNDED", "\(path).\(listKey)[\(w)].sets[\(s)].weight", "Rounded \(TargetText.number(weight)) to \(TargetText.number(snapped)) \(plan.units.rawValue), the smallest change your equipment makes.")
                            }
                            return ProgressionSet(weight: snapped, work: set.work)
                        }
                    }
                }
                entries.append(entry)
            }
        }
        if aliasUsed { issue("W_PROGRESSION_WEEKS_ALIAS", "", "\"weeks\" was read as steps.") }
        issues = issues.enumerated().sorted { a, b in
            a.element.path == b.element.path ? a.offset < b.offset : a.element.path < b.element.path
        }.map(\.element)
        guard issues.allSatisfy({ $0.severity == .warning }) else { return Result(progression: nil, issues: issues) }
        guard !entries.isEmpty else {
            issue("E_PROGRESSION_EMPTY", "exercises", "None of the exercises in the reply match this plan.")
            return Result(progression: nil, issues: issues)
        }
        let weeks = declaredWeeks ?? (entries.map { $0.weeks.count }.max() ?? 1)
        return Result(progression: Progression(startDate: calendar.startOfDay(for: now), weeks: weeks, entries: entries, mode: mode),
                      issues: issues)
    }

    /// One week object: `null` or `{}` is "same as the plan"; otherwise weight and/or reps or
    /// durationSeconds for every set, or `sets` for per-set values.
    private static func week(_ raw: RawJSON, _ path: String,
                             issue: (String, String, String) -> Void) -> ProgressionWeek? {
        if raw == .null { return ProgressionWeek() }
        guard let fields = raw.object else {
            issue("E_PROGRESSION_WEEK_INVALID", path, "Each step must be an object like {\"weight\": 62.5, \"reps\": \"8-12\"}, or {} for no change.")
            return nil
        }
        for key in fields.keys where !["weight", "reps", "durationSeconds", "sets", "notes"].contains(key) {
            issue("W_UNKNOWN_FIELD", "\(path).\(key)", "Unknown field \"\(key)\" was ignored.")
        }
        var result = ProgressionWeek()
        guard let weekWeight = Self.weight(raw["weight"], "\(path).weight", issue: issue) else { return nil }
        result.weight = weekWeight
        guard let weekWork = Self.work(raw, path, issue: issue) else { return nil }
        result.work = weekWork
        if let sets = raw["sets"] {
            guard let list = sets.array, !list.isEmpty, list.count <= 50 else {
                issue("E_SETS_INVALID", "\(path).sets", "sets must be a list of 1 to 50 set objects."); return nil
            }
            var parsed: [ProgressionSet] = []
            for (index, item) in list.enumerated() {
                let setPath = "\(path).sets[\(index)]"
                guard item.object != nil else {
                    issue("E_SETS_INVALID", setPath, "Each set must be an object."); return nil
                }
                guard let setWeight = Self.weight(item["weight"], "\(setPath).weight", issue: issue),
                      let setWork = Self.work(item, setPath, issue: issue) else { return nil }
                parsed.append(ProgressionSet(weight: setWeight, work: setWork))
            }
            result.sets = parsed
        }
        return result
    }

    /// `.some(nil)` for no weight, `.some(w)` for one, `nil` for an invalid value.
    private static func weight(_ raw: RawJSON?, _ path: String,
                               issue: (String, String, String) -> Void) -> Double?? {
        guard let raw else { return .some(nil) }
        if let number = raw.number, raw.string == nil {
            guard number.isFinite, (0...10_000).contains(number) else {
                issue("E_WEIGHT_INVALID", path, "weight must be between 0 and 10000, got \(raw.display)."); return nil
            }
            return .some(number)
        }
        guard let text = raw.string?.trimmed.lowercased() else {
            issue("E_WEIGHT_INVALID", path, "weight must be a number, got \(raw.display)."); return nil
        }
        if ["", "bw", "bodyweight", "body weight", "none", "same"].contains(text) { return .some(nil) }
        let stripped = text.replacing("\\s*(kgs?|kilograms?|lbs?|pounds?)$", with: "").replacingOccurrences(of: ",", with: ".")
        guard let number = Double(stripped), number.isFinite, (0...10_000).contains(number) else {
            issue("E_WEIGHT_INVALID", path, "weight must be a number, got \(raw.display)."); return nil
        }
        return .some(number)
    }

    /// `.some(nil)` for no target, `.some(work)` for one, `nil` for an invalid one.
    private static func work(_ raw: RawJSON, _ path: String,
                             issue: (String, String, String) -> Void) -> WorkTarget?? {
        let reps = raw["reps"], duration = raw["durationSeconds"]
        if reps != nil, duration != nil {
            issue("E_TARGET_CONFLICT", path, "Give reps or durationSeconds, not both."); return nil
        }
        if let reps {
            let text = reps.string ?? reps.integer.map(String.init) ?? reps.display
            let word = text.trimmed.lowercased().replacing("\\s*reps?$", with: "")
            let parsed = ["max", "failure", "to failure", "as many as possible"].contains(word)
                ? WorkTarget.reps(.amrap(min: nil))
                : PlanEdit.parseWork(word.replacingOccurrences(of: " to ", with: "-").replacingOccurrences(of: "–", with: "-"))
            guard let parsed, case .reps = parsed else {
                issue("E_REPS_INVALID", "\(path).reps", "\(reps.display) is not a valid reps value. Use a whole number, a range like \"8-12\", \"AMRAP\" or \"10+\".")
                return nil
            }
            return .some(parsed)
        }
        if let duration {
            if let seconds = duration.integer, duration.string == nil || duration.string?.trimmed.matches("^\\d+$") == true {
                guard (1...86_400).contains(seconds) else {
                    issue("E_DURATION_INVALID", "\(path).durationSeconds", "durationSeconds must be 1 to 86400 seconds."); return nil
                }
                return .some(.duration(seconds: seconds))
            }
            let text = duration.string?.trimmed.lowercased() ?? duration.display
            if ["max", "open", "amsap", "as long as possible", "to failure"].contains(text) { return .some(.openDuration(minSeconds: nil)) }
            if text.hasSuffix("+"), let minimum = Int(text.dropLast()), (1...86_400).contains(minimum) {
                return .some(.openDuration(minSeconds: minimum))
            }
            issue("E_DURATION_INVALID", "\(path).durationSeconds", "\(duration.display) is not a valid duration. Use seconds, \"max\", or \"30+\".")
            return nil
        }
        return .some(nil)
    }
}
