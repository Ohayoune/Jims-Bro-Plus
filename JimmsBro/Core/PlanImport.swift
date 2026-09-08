import Foundation

struct ImportStage<Value> { var value: Value?; var issues: [Issue] = [] }
struct ImportResult {
    var plan: Plan?
    var issues: [Issue]
    var errors: [Issue] { issues.filter { $0.severity == .error } }
}
enum PlanImport {
    static let promptMarker = "JIMMSBRO-PLAN-PROMPT-V1"
    static let maxBytes = 1_048_576
    static func run(_ text: String, settings: Settings = Settings(), now: Date = Date(), calendar: Calendar = .current) -> ImportResult {
        let extracted = extract(text)
        guard let body = extracted.value else { return ImportResult(plan: nil, issues: extracted.issues) }
        let decoded = decode(body)
        guard let raw = decoded.value else { return ImportResult(plan: nil, issues: extracted.issues + decoded.issues) }
        var normalized = normalize(raw, settings: settings, now: now, calendar: calendar)
        var issues = extracted.issues + decoded.issues + normalized.issues
        if let plan = normalized.value { issues += validate(plan) }
        issues = issues.enumerated().sorted { a, b in a.element.path == b.element.path ? a.offset < b.offset : a.element.path < b.element.path }.map(\.element)
        if issues.contains(where: { $0.severity == .error }) { normalized.value = nil }
        normalized.value?.sourceText = text
        normalized.value?.warnings = issues.filter { $0.severity == .warning }
        return ImportResult(plan: normalized.value, issues: issues)
    }
    static func extract(_ text: String) -> ImportStage<String> {
        func failure(_ code: String, _ message: String) -> ImportStage<String> { ImportStage(value: nil, issues: [Issue(severity: .error, code: code, path: "", message: message)]) }
        if text.utf8.count > maxBytes { return failure("E_TOO_LARGE", "The pasted text is over 1 MB. Paste one plan at a time.") }
        let text = text.replacing("[\u{FEFF}\u{200B}\u{200C}\u{200D}]", with: "")
        if text.trimmed.isEmpty { return failure("E_EMPTY", "Nothing to import. Paste the JSON the chatbot produced.") }
        let pattern = "(?s)```[A-Za-z0-9_-]*[ \\t]*\\r?\\n?(.*?)```"
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        let fences = matches.compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]).trimmed } }.filter { !$0.isEmpty }
        if text.contains(promptMarker) && fences.isEmpty { return failure("E_PROMPT_PASTED", "That's the prompt. Paste the chatbot's JSON reply instead.") }
        if fences.count > 1 { return failure("E_MULTIPLE_OBJECTS", "Found more than one code block. Paste just one plan.") }
        var body: String
        var surrounding = false
        if let fence = fences.first {
            body = fence
            surrounding = !text.replacing(pattern, with: "").trimmed.isEmpty
        } else {
            guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return failure("E_NOT_JSON", "No JSON found in the pasted text.") }
            if let end = valueEnd(text, start: start) {
                let suffix = String(text[end...]).trimmed
                if suffix.hasPrefix("{") || suffix.hasPrefix("[") { return failure("E_MULTIPLE_OBJECTS", "Found more than one JSON object. Paste just one plan.") }
                body = String(text[start..<end]); surrounding = !text[..<start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !suffix.isEmpty
            } else { body = String(text[start...]) }
        }
        // A single fence can still contain two top-level JSON values.
        if let start = body.firstIndex(where: { $0 == "{" || $0 == "[" }), let end = valueEnd(body, start: start) {
            let suffix = body[end...].trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.hasPrefix("{") || suffix.hasPrefix("[") { return failure("E_MULTIPLE_OBJECTS", "Found more than one JSON object. Paste just one plan.") }
        }
        return ImportStage(value: body, issues: surrounding ? [Issue(severity: .warning, code: "W_SURROUNDING_TEXT", path: "", message: "Text around the JSON was ignored.")] : [])
    }
    static func valueEnd(_ text: String, start: String.Index) -> String.Index? {
        var depth = 0, quoted = false, escaped = false
        for index in text.indices where index >= start {
            let c = text[index]
            if quoted {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { quoted = false }
            } else if c == "\"" { quoted = true }
            else if c == "{" || c == "[" { depth += 1 }
            else if c == "}" || c == "]" { depth -= 1; if depth == 0 { return text.index(after: index) } }
        }
        return nil
    }
    static func decode(_ body: String) -> ImportStage<RawPlan> {
        func strict(_ text: String) throws -> RawJSON {
            var grammar = StrictJSON(text); try grammar.validate()
            return try JSONDecoder().decode(RawJSON.self, from: Data(text.utf8))
        }
        do { return ImportStage(value: try strict(body)) }
        catch {
            let firstError = error.localizedDescription
            if body.matches("[“”„]"), let fixed = try? strict(body.replacing("[“”„]", with: "\"")) {
                return ImportStage(value: fixed, issues: [Issue(severity: .warning, code: "W_CURLY_QUOTES_FIXED", path: "", message: "Curly quotes were replaced with straight quotes.")])
            }
            return ImportStage(value: nil, issues: [Issue(severity: .error, code: "E_NOT_JSON", path: "", message: "This isn't valid JSON: \(firstError) Ask the chatbot for strict JSON, or use Copy fix-it prompt.")])
        }
    }
    static func normalize(_ raw: RawPlan, settings: Settings = Settings(), now: Date = Date(), calendar: Calendar = .current) -> ImportStage<Plan> {
        var normalizer = PlanNormalizer(settings: settings, now: now, calendar: calendar)
        let plan = normalizer.plan(raw)
        return ImportStage(value: normalizer.issues.contains(where: { $0.severity == .error }) ? nil : plan, issues: normalizer.issues)
    }
    static func validate(_ plan: Plan) -> [Issue] {
        var issues: [Issue] = []
        func error(_ code: String, _ path: String, _ message: String) { issues.append(Issue(severity: .error, code: code, path: path, message: message)) }
        if plan.days.isEmpty { error("E_NO_DAYS", "days", "Add at least one day with exercises.") }
        if plan.days.count > 31 { error("E_LIMIT_EXCEEDED", "days", "Use no more than 31 days.") }
        for (di, day) in plan.days.enumerated() {
            let dp = "days[\(di)].exercises"
            if day.exercises.isEmpty { error("E_NO_EXERCISES", dp, "Add at least one exercise to this day.") }
            if day.exercises.count > 50 { error("E_LIMIT_EXCEEDED", dp, "Use no more than 50 exercises per day.") }
            for (ei, exercise) in day.exercises.enumerated() {
                let ep = "\(dp)[\(ei)]"
                if exercise.name.trimmed.isEmpty { error("E_MISSING_NAME", ep + ".name", "Every exercise needs a name.") }
                if exercise.sets.isEmpty { error("E_SETS_INVALID", ep + ".sets", "Add at least one set.") }
                if exercise.sets.count > 50 { error("E_LIMIT_EXCEEDED", ep + ".sets", "Use no more than 50 sets.") }
            }
        }
        return issues
    }
}

private struct PlanNormalizer {
    let settings: Settings
    let now: Date
    let calendar: Calendar
    var issues: [Issue] = []
    mutating func issue(_ code: String, _ path: String, _ message: String) { issues.append(Issue(severity: code.hasPrefix("E_") ? .error : .warning, code: code, path: path, message: message)) }
    mutating func unknown(_ raw: RawJSON, _ known: Set<String>, _ path: String) {
        for key in (raw.object?.keys.sorted() ?? []) where !known.contains(key) { issue("W_UNKNOWN_FIELD", path.isEmpty ? key : path + "." + key, "Field \"\(key)\" was ignored.") }
    }
    mutating func integer(_ raw: RawJSON?, _ path: String, _ code: String, _ range: ClosedRange<Int>) -> Int? {
        guard let raw else { return nil }
        guard let n = raw.integer, range.contains(n) else { issue(code, path, "Use a whole number between \(range.lowerBound) and \(range.upperBound), got \(raw.display)."); return nil }
        return n
    }
    /// D51 (v1.5): the effort target — `inReserve`, with `rir` accepted as the alias people
    /// write. 0–20, reps on a rep set and seconds on a hold; anything else is
    /// E_IN_RESERVE_INVALID. `present` says whether the object said anything, so a set can
    /// fall back to its exercise only when it did not.
    mutating func reserve(_ raw: RawJSON, _ path: String) -> (value: Int?, present: Bool) {
        let key = raw["inReserve"] != nil ? "inReserve" : (raw["rir"] != nil ? "rir" : nil)
        guard let key else { return (nil, false) }
        return (integer(raw[key], path + "." + key, "E_IN_RESERVE_INVALID", 0...20), true)
    }
    mutating func name(_ raw: RawJSON?, _ path: String, _ fallback: String, warnDefault: Bool = true) -> String {
        guard let text = raw?.string?.trimmed, !text.isEmpty else { if warnDefault { issue("W_DEFAULT_NAME", path, "No name given; using \"\(fallback)\".") }; return fallback }
        if text.count > 100 { issue("W_NAME_TRUNCATED", path, "Name was cut to 100 characters.") }
        return String(text.prefix(100))
    }
    mutating func reps(_ raw: RawJSON, _ path: String, rangeOnly: Bool = false) -> RepTarget? {
        let code = rangeOnly ? "E_REPRANGE_INVALID" : "E_REPS_INVALID"
        func badMessage() -> String { "\(raw.display) is not a valid \(rangeOnly ? "rep range" : "reps value"). Use a whole number, a range like \"8-12\"\(rangeOnly ? "." : ", \"AMRAP\", or \"10+\".")" }
        if case let .number(n) = raw, n.isFinite, n.rounded() == n, (1...1000).contains(n) { return .fixed(Int(n)) }
        if let string = raw.string {
            let s = string.trimmed.lowercased().replacing(#"\s*reps?$"#, with: "")
            if !rangeOnly && ["amrap","max","failure","to failure","as many as possible"].contains(s) { return .amrap(min: nil) }
            if !rangeOnly, let m = s.captures(#"^(\d+)\s*\+$"#), let n = Int(m[1]), (1...1000).contains(n) { return .amrap(min: n) }
            if let m = s.captures(#"^(\d+)\s*(?:-|–|—|/|to)\s*(\d+)$"#), let a = Int(m[1]), let b = Int(m[2]), (1...1000).contains(a), (1...1000).contains(b) {
                if a > b { issue("W_RANGE_SWAPPED", path, "\"\(s)\" was read as \(b)-\(a).") }
                return a == b ? .fixed(a) : .range(min: min(a,b), max: max(a,b))
            }
            if s.matches(#"^\d+$"#), let n = Int(s), (1...1000).contains(n) { return .fixed(n) }
        }
        issue(code, path, badMessage()); return nil
    }
    mutating func duration(_ raw: RawJSON, _ path: String) -> WorkTarget? {
        if let s = raw.string?.trimmed.lowercased() {
            if ["max","open","amsap","as long as possible","to failure"].contains(s) { return .openDuration(minSeconds: nil) }
            if let m = s.captures(#"^(\d+)\s*\+$"#), let n = Int(m[1]), (1...86400).contains(n) { return .openDuration(minSeconds: n) }
        }
        guard let n = integer(raw, path, "E_DURATION_INVALID", 1...86400) else { return nil }
        return .duration(seconds: n)
    }
    static let units = ["kg": WeightUnit.kg, "kgs": .kg, "kilogram": .kg, "kilograms": .kg, "lb": .lb, "lbs": .lb, "pound": .lb, "pounds": .lb]
    static let bodyweightWords: Set<String> = ["bw", "bodyweight", "body weight"]
    mutating func weight(_ raw: RawJSON?, _ path: String, _ units: WeightUnit) -> (weight: Double?, bodyweight: Bool) {
        guard let raw else { return (nil, false) }
        var n: Double?
        if let s = raw.string?.trimmed.lowercased() {
            if Self.bodyweightWords.contains(s) { return (nil, true) }
            if ["none", ""].contains(s) { return (nil, false) }
            if let m = s.captures(#"^\+?\s*(\d+(?:[.,]\d+)?)\s*([a-z]*)\.?$"#), m[2].isEmpty || Self.units[m[2]] != nil {
                n = Double(m[1].replacingOccurrences(of: ",", with: "."))
                if let unit = Self.units[m[2]], unit != units { issue("W_WEIGHT_UNIT_IGNORED", path, "The unit in \"\(s)\" was ignored; this plan uses \(units.rawValue).") }
            }
        } else if case let .number(value) = raw { n = value }
        guard let n, n.isFinite, (0...10000).contains(n) else { issue("E_WEIGHT_INVALID", path, "\(raw.display) is not a valid weight. Use a number from 0 to 10000 in \(units.rawValue), or omit it."); return (nil, false) }
        let rounded = ((n + 1e-9) * 10).rounded(.toNearestOrAwayFromZero) / 10
        if abs(rounded - n) > 1e-9 { issue("W_WEIGHT_ROUNDED", path, "\(n) was rounded to \(rounded).") }
        return (rounded, false)
    }
    enum WarningSpec { case off, percent, seconds(Int) }
    mutating func warning(_ raw: RawJSON?, _ path: String) -> WarningSpec? {
        guard let raw else { return nil }
        if let b = raw.bool { return b ? .percent : .off }
        if raw.string == nil, let n = raw.integer, (1...86399).contains(n) { return .seconds(n) }
        issue("E_WARNING_BEEP_INVALID", path, "warningBeep must be true, false, or a whole number from 1 to 86399."); return nil
    }
    mutating func resolvedWarning(_ spec: WarningSpec?, _ work: WorkTarget, _ path: String) -> Int? {
        guard case let .duration(d) = work else { if spec != nil { issue("W_WARNING_BEEP_IGNORED", path, "warningBeep only applies to sets with a fixed durationSeconds.") }; return nil }
        switch spec {
        case nil, .percent?: return d < 10 ? nil : max(1, Int((Double(d) / 10).rounded(.toNearestOrAwayFromZero)))
        case .off?: return nil
        case let .seconds(n)?:
            if n >= d { issue("W_WARNING_BEEP_IGNORED", path, "warningBeep \(n) is not before the end of a \(d) s set."); return nil }
            return n
        }
    }
    mutating func drops(_ raw: RawJSON?, _ path: String, _ units: WeightUnit) -> [DropTarget]? {
        guard let raw else { return nil }
        guard let list = raw.array, (1...5).contains(list.count), list.allSatisfy({ $0.object != nil }) else { issue("E_DROPS_INVALID", path, "drops must be a list of 1 to 5 objects like { \"weight\": 20 }."); return nil }
        return list.enumerated().map { j, item in
            let p = "\(path)[\(j)]"
            unknown(item, ["weight","reps"], p)
            let work = item["reps"].flatMap { reps($0, p + ".reps") } ?? .amrap(min: nil)
            return DropTarget(work: .reps(work), weight: weight(item["weight"], p + ".weight", units).weight)
        }
    }
    mutating func exercise(_ raw: RawJSON, _ path: String, units: WeightUnit, fallbackRest: Int) -> (exercise: Exercise, explicitRest: Int?) {
        unknown(raw, ["name","group","notes","sets","reps","durationSeconds","warningBeep","bodyweight","weight","restSeconds","repRange","drops","inReserve","rir"], path)
        let ename: String
        if let s = raw["name"]?.string, !s.trimmed.isEmpty { ename = name(raw["name"], path + ".name", "?") }
        else { issue("E_MISSING_NAME", path + ".name", "Every exercise needs a name."); ename = "?" }
        let group = raw["group"]?.display.trimmed.uppercased()
        var notes = raw["notes"]?.display
        if let n = notes, n.count > 500 { issue("W_NOTES_TRUNCATED", path + ".notes", "Notes were cut to 500 characters."); notes = String(n.prefix(500)) }
        let rest = integer(raw["restSeconds"], path + ".restSeconds", "E_REST_INVALID", 0...3600)
        let exReps = raw["reps"].flatMap { reps($0, path + ".reps") }
        let exDuration = raw["durationSeconds"].flatMap { duration($0, path + ".durationSeconds") }
        var exWeight = weight(raw["weight"], path + ".weight", units)
        var bodyweight = exWeight.bodyweight
        if let bw = raw["bodyweight"] {
            if let flag = bw.bool { bodyweight = bodyweight || flag }
            else { issue("E_BODYWEIGHT_INVALID", path + ".bodyweight", "bodyweight must be true or false.") }
        }
        let exWarning = warning(raw["warningBeep"], path + ".warningBeep")
        let exReserve = reserve(raw, path).value
        if bodyweight && exWeight.weight != nil { issue("W_BODYWEIGHT_WEIGHT_IGNORED", path + ".weight", "Weight ignored on a bodyweight exercise."); exWeight.weight = nil }
        let exDrops = drops(raw["drops"], path + ".drops", units)
        let hasReps = raw["reps"] != nil, hasDuration = raw["durationSeconds"] != nil
        var repRange: RepRange?
        if let rr = raw["repRange"] {
            if hasDuration && !hasReps { issue("W_REPRANGE_IGNORED", path + ".repRange", "repRange is ignored on a timed exercise.") }
            else if let parsed = reps(rr, path + ".repRange", rangeOnly: true) {
                switch parsed {
                case let .fixed(n): repRange = RepRange(min: n, max: n)
                case let .range(a,b): repRange = RepRange(min: a, max: b)
                case .amrap: break
                }
                if let rr = repRange, case let .fixed(n)? = exReps, !(rr.min...rr.max).contains(n) { issue("W_REPRANGE_OUTSIDE", path + ".repRange", "The reps target \(n) is outside repRange \(rr.min)-\(rr.max).") }
            }
        } else if case let .range(a,b)? = exReps { repRange = RepRange(min: a, max: b) }
        let setsRaw = raw["sets"] ?? .number(1)
        var targets: [SetTarget] = []
        if let list = setsRaw.array {
            if list.isEmpty { issue("E_SETS_INVALID", path + ".sets", "sets must be a number of sets or a non-empty list of sets.") }
            else if list.count > 50 { issue("E_LIMIT_EXCEEDED", path + ".sets", "Use no more than 50 sets.") }
            else {
                for (si, s) in list.enumerated() {
                    let sp = "\(path).sets[\(si)]"
                    unknown(s, ["reps","durationSeconds","warningBeep","weight","restSeconds","drops","inReserve","rir"], sp)
                    if s["reps"] != nil && s["durationSeconds"] != nil { issue("E_TARGET_CONFLICT", sp, "A set can't have both reps and durationSeconds."); continue }
                    let work: WorkTarget?
                    if let r = s["reps"] { work = reps(r, sp + ".reps").map(WorkTarget.reps) }
                    else if let d = s["durationSeconds"] { work = duration(d, sp + ".durationSeconds") }
                    else if hasReps && hasDuration { issue("E_TARGET_CONFLICT", path, "An exercise can't have both reps and durationSeconds."); continue }
                    else if hasReps { work = exReps.map(WorkTarget.reps) }
                    else if hasDuration { work = exDuration }
                    else { issue("E_TARGET_MISSING", sp, "Each set needs reps or durationSeconds."); continue }
                    var w = exWeight.weight
                    if let rawWeight = s["weight"] {
                        let parsed = weight(rawWeight, sp + ".weight", units)
                        w = parsed.weight
                        if parsed.bodyweight { bodyweight = true }
                        else if bodyweight && w != nil { issue("W_BODYWEIGHT_WEIGHT_IGNORED", sp + ".weight", "Weight ignored on a bodyweight exercise."); w = nil }
                    }
                    let warningPath = s["warningBeep"] == nil ? path + ".warningBeep" : sp + ".warningBeep"
                    let warningSpec = s["warningBeep"] == nil ? exWarning : warning(s["warningBeep"], warningPath)
                    let sr = integer(s["restSeconds"], sp + ".restSeconds", "E_REST_INVALID", 0...3600)
                    let setReserve = reserve(s, sp)
                    var ds = s["drops"] == nil ? exDrops : drops(s["drops"], sp + ".drops", units)
                    guard let work else { continue }
                    if work.isTimed && !(ds ?? []).isEmpty { issue("W_DROPS_IGNORED", sp + ".drops", "Drops are ignored on a timed set."); ds = nil }
                    targets.append(SetTarget(work: work, weight: w, restSeconds: sr ?? rest ?? fallbackRest, warningBeepSeconds: resolvedWarning(warningSpec, work, warningPath), drops: ds ?? [], inReserve: setReserve.present ? setReserve.value : exReserve))
                }
            }
        } else if let count = setsRaw.integer, (1...50).contains(count) {
            if hasReps && hasDuration { issue("E_TARGET_CONFLICT", path, "An exercise can't have both reps and durationSeconds.") }
            else if !hasReps && !hasDuration { issue("E_TARGET_MISSING", path, "Each exercise needs reps or durationSeconds.") }
            else if let work = hasReps ? exReps.map(WorkTarget.reps) : exDuration {
                var ds = exDrops ?? []
                if work.isTimed && !ds.isEmpty { issue("W_DROPS_IGNORED", path + ".drops", "Drops are ignored on a timed exercise."); ds = [] }
                let beep = resolvedWarning(exWarning, work, path + ".warningBeep")
                targets = Array(repeating: SetTarget(work: work, weight: exWeight.weight, restSeconds: rest ?? fallbackRest, warningBeepSeconds: beep, drops: ds, inReserve: exReserve), count: count)
            }
        } else {
            let over = (setsRaw.integer ?? 0) > 50
            issue(over ? "E_LIMIT_EXCEEDED" : "E_SETS_INVALID", path + ".sets", "sets must be a whole number from 1 to 50 or a non-empty list of sets.")
            if hasReps && hasDuration { issue("E_TARGET_CONFLICT", path, "An exercise can't have both reps and durationSeconds.") }
            if !over && !hasReps && !hasDuration { issue("E_TARGET_MISSING", path, "Each exercise needs reps or durationSeconds.") }
        }
        if bodyweight {
            var dropWarning = false
            for i in targets.indices {
                // A later set can supply the bodyweight alias; the flag applies to the whole exercise.
                if targets[i].weight != nil {
                    issue("W_BODYWEIGHT_WEIGHT_IGNORED", path + ".sets[\(i)].weight", "Weight ignored on a bodyweight exercise.")
                    targets[i].weight = nil
                }
                for j in targets[i].drops.indices where targets[i].drops[j].weight != nil { dropWarning = true; targets[i].drops[j].weight = nil }
            }
            if dropWarning { issue("W_BODYWEIGHT_WEIGHT_IGNORED", "", "Drop weights ignored on bodyweight exercise \"\(ename)\".") }
        }
        return (Exercise(name: ename, group: group == "" ? nil : group, notes: notes, repRange: repRange, bodyweight: bodyweight, sets: targets), rest)
    }
    mutating func plan(_ input: RawJSON) -> Plan? {
        let planFields: Set<String> = ["schemaVersion","name","units","defaultRestSeconds","schedule","cycle","days"]
        let dayFields: Set<String> = ["name","weekday","defaultRestSeconds","exercises"]
        var raw = input, wrapped = false, bareDay = false
        if input.object?["days"] != nil { }
        else if input.object?["exercises"] != nil { raw = .object(["name": input["name"] ?? .null, "days": .array([input])]); wrapped = true; bareDay = true }
        else if let list = input.array, !list.isEmpty, list.allSatisfy({ $0.object?["exercises"] != nil }) { raw = .object(["days": input]); wrapped = true }
        else if let list = input.array, !list.isEmpty, list.allSatisfy({ $0.object?["name"] != nil && $0.object?["exercises"] == nil }) { raw = .object(["days": .array([.object(["exercises": input])])]); wrapped = true }
        else { issue("E_NOT_A_PLAN", "", "This JSON isn't a workout plan. Use an object with days or exercises."); return nil }
        if wrapped { issue("W_WRAPPED_SINGLE_DAY", "", "Wrapped the pasted content into a plan.") } else { unknown(raw, planFields, "") }
        if bareDay { unknown(input, dayFields, "days[0]") }
        if let sv = raw["schemaVersion"], sv.integer == nil || (sv.integer ?? 0) > 1 { issue("E_SCHEMA_VERSION", "schemaVersion", "This plan needs schemaVersion \(sv.display); the app supports 1. Update the app.") }
        let components = calendar.dateComponents([.year,.month,.day], from: now)
        let today = String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
        let pname = name(raw["name"], "name", "Imported plan \(today)")
        var units = settings.units
        if let u = raw["units"] {
            if let s = u.string, let parsed = Self.units[s.trimmed.lowercased()] { units = parsed }
            else { issue("E_UNITS_INVALID", "units", "units must be \"kg\" or \"lb\", got \(u.display).") }
        }
        let planRest = integer(raw["defaultRestSeconds"], "defaultRestSeconds", "E_REST_INVALID", 0...3600)
        guard let rawDays = raw["days"]?.array, !rawDays.isEmpty else { issue("E_NO_DAYS", "days", "The plan has no days. Add at least one day with exercises."); return nil }
        guard rawDays.count <= 31 else { issue("E_LIMIT_EXCEEDED", "days", "Use no more than 31 days."); return nil }
        let hasWeekdays = rawDays.map { $0["weekday"] != nil }
        let inferred: Schedule? = hasWeekdays.allSatisfy { $0 } ? .weekday : (!hasWeekdays.contains(true) ? .rotation : nil)
        let schedule: Schedule
        if let s = raw["schedule"]?.string?.trimmed.lowercased(), let known = Schedule(rawValue: s) { schedule = known }
        else {
            if raw["schedule"] != nil { issue("W_SCHEDULE_INFERRED", "schedule", "schedule was inferred from the days; use rotation or weekday.") }
            if inferred == nil { issue("E_SCHEDULE_MIXED", "schedule", "Give every day a weekday, or none, or set schedule.") }
            schedule = inferred ?? .rotation
        }
        var days: [Day] = [], seenWeekdays: Set<Weekday> = [], seenNames: Set<String> = []
        for (di, d) in rawDays.enumerated() {
            let dp = "days[\(di)]"
            guard d.object != nil else { issue("E_NO_EXERCISES", dp + ".exercises", "Each day must be an object with exercises."); continue }
            unknown(d, dayFields, dp)
            var dname = name(d["name"], dp + ".name", bareDay ? pname : "Day \(di + 1)", warnDefault: !(bareDay && d["name"] != nil))
            let original = dname
            var suffix = 2
            while seenNames.contains(normalized(dname)) { dname = "\(original) (\(suffix))"; suffix += 1 }
            if dname != original { issue("W_DAY_RENAMED", dp + ".name", "Renamed duplicate day to \"\(dname)\".") }
            seenNames.insert(normalized(dname))
            var weekday: Weekday?
            if schedule == .rotation {
                if d["weekday"] != nil { issue("W_WEEKDAY_IGNORED", dp + ".weekday", "weekday is ignored in a rotation plan.") }
            } else if let w = d["weekday"] {
                if let s = w.string?.trimmed.lowercased() { weekday = Weekday.allCases.first { $0.rawValue == s || String($0.rawValue.prefix(3)) == s } }
                if let weekday {
                    if !seenWeekdays.insert(weekday).inserted { issue("E_WEEKDAY_DUPLICATE", dp + ".weekday", "Two days are on \(weekday.rawValue); use different weekdays.") }
                } else { issue("E_WEEKDAY_INVALID", dp + ".weekday", "Use a weekday from monday to sunday, or its three-letter abbreviation.") }
            } else { issue("E_WEEKDAY_MISSING", dp + ".weekday", "This day needs a weekday in a weekday plan.") }
            let dayRest = integer(d["defaultRestSeconds"], dp + ".defaultRestSeconds", "E_REST_INVALID", 0...3600)
            var exercises: [Exercise] = [], explicitRests: [Int?] = []
            if let list = d["exercises"]?.array, !list.isEmpty {
                if list.count > 50 { issue("E_LIMIT_EXCEEDED", dp + ".exercises", "Use no more than 50 exercises per day.") }
                else {
                    for (ei, ex) in list.enumerated() {
                        let parsed = exercise(ex, "\(dp).exercises[\(ei)]", units: units, fallbackRest: dayRest ?? planRest ?? min(3600, max(0, settings.defaultRestSeconds)))
                        exercises.append(parsed.exercise); explicitRests.append(parsed.explicitRest)
                    }
                }
            } else { issue("E_NO_EXERCISES", dp + ".exercises", "Day \"\(dname)\" has no exercises.") }
            var i = 0, groupCounts: [String: Int] = [:]
            var usedGroups = Set(exercises.compactMap(\.group))
            while i < exercises.count {
                guard let g = exercises[i].group else { i += 1; continue }
                var end = i + 1
                while end < exercises.count && exercises[end].group == g { end += 1 }
                groupCounts[g, default: 0] += 1
                var tag = g
                if groupCounts[g, default: 0] > 1 {
                    var n = groupCounts[g, default: 0]
                    tag = "\(g)\(n)"
                    while usedGroups.contains(tag) { n += 1; tag = "\(g)\(n)" }
                    usedGroups.insert(tag)
                    issue("W_GROUP_SPLIT", "\(dp).exercises[\(i)].group", "Group \"\(g)\" appeared again; treating it as a separate group \"\(tag)\".")
                }
                if end - i == 1 { issue("W_GROUP_SINGLE", "\(dp).exercises[\(i)].group", "Group \"\(tag)\" has only one exercise; treating it as ungrouped."); exercises[i].group = nil }
                else {
                    if Set(exercises[i..<end].map { $0.sets.count }).count > 1 { issue("W_GROUP_SET_MISMATCH", "\(dp).exercises[\(i)].group", "Group members have different set counts; shorter ones drop out of later rounds.") }
                    let roundRest = explicitRests[i..<end].compactMap { $0 }.first
                    for e in i..<end {
                        exercises[e].group = tag
                        for s in exercises[e].sets.indices { exercises[e].sets[s].groupRestSeconds = roundRest }
                    }
                }
                i = end
            }
            days.append(Day(name: dname, weekday: weekday, exercises: exercises))
        }
        var cycle: [CycleEntry] = days.indices.map(CycleEntry.day)
        if schedule == .weekday {
            if raw["cycle"] != nil { issue("W_CYCLE_IGNORED", "cycle", "cycle is derived from weekdays and the explicit cycle was ignored.") }
            cycle = Weekday.allCases.map { w in days.firstIndex { $0.weekday == w }.map(CycleEntry.day) ?? .rest }
        } else if let c = raw["cycle"] {
            if let entries = c.array, (1...31).contains(entries.count), entries.allSatisfy({ $0.string != nil }) {
                cycle = []
                var unknownDay = false
                for (ci, entry) in entries.enumerated() {
                    let key = normalized(entry.string ?? "")
                    if ["rest","off"].contains(key) { cycle.append(.rest) }
                    else if let index = days.firstIndex(where: { normalized($0.name) == key }) { cycle.append(.day(index)) }
                    else { unknownDay = true; issue("E_CYCLE_UNKNOWN_DAY", "cycle[\(ci)]", "\"\(entry.display)\" is not one of this plan's days.") }
                }
                if !unknownDay && days.indices.contains(where: { !cycle.contains(.day($0)) }) { issue("W_CYCLE_MISSING_DAY", "cycle", "Some days never appear in the cycle.") }
            } else { issue("E_CYCLE_INVALID", "cycle", "cycle must be a list of 1 to 31 day names or rest.") }
        }
        return Plan(name: pname, units: units, schedule: schedule, days: days, importedAt: now, sourceText: "", cycle: cycle)
    }
}
