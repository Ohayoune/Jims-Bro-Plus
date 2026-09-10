import Foundation

/// SPEC §6.10. Each field filters what it will accept as the user types, so an unacceptable
/// edit leaves the last valid text in place rather than clearing the field.
enum InputRules {
    static let maxWeight = 10_000.0

    /// Digits only, at most three. Over-long input is truncated; non-digits are refused.
    static func reps(_ new: String, previous: String = "") -> String {
        guard new.allSatisfy(\.isWholeNumber) else { return previous }
        return String(new.prefix(3))
    }

    /// Digits only, at most five.
    static func seconds(_ new: String, previous: String = "") -> String {
        guard new.allSatisfy(\.isWholeNumber) else { return previous }
        return String(new.prefix(5))
    }

    /// Digits plus at most one decimal separator; both `.` and `,` are accepted and stored as `.`.
    /// A partial entry like "62." is kept so the user can keep typing; rounding happens on commit.
    static func weight(_ new: String, previous: String = "") -> String {
        let text = new.replacingOccurrences(of: ",", with: ".")
        guard text.allSatisfy({ $0.isWholeNumber || $0 == "." }) else { return previous }
        guard text.filter({ $0 == "." }).count <= 1 else { return previous }
        guard let value = Double(text) ?? (text.isEmpty || text == "." ? 0 : nil) else { return previous }
        guard value <= maxWeight else { return previous }
        return text
    }

    static func repsValue(_ text: String) -> Int? { text.isEmpty ? nil : Int(text) }
    static func secondsValue(_ text: String) -> Int? { text.isEmpty ? nil : Int(text) }

    /// One decimal place is kept on commit: "62.55" becomes 62.6. Empty means no weight.
    static func weightValue(_ text: String) -> Double? {
        let text = text.replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, text != ".", let value = Double(text), value.isFinite else { return nil }
        return min(maxWeight, max(0, (value * 10).rounded() / 10))
    }

    /// The text a committed weight goes back into the field as.
    static func weightText(_ value: Double?) -> String { value.map(TargetText.number) ?? "" }

    /// − / + never go below zero (N7).
    /// D35 (v1.2): a tap of − or + lands on a weight the equipment can make.
    ///
    /// From a weight that is **already loadable** it moves by one step and rounds that onto the
    /// grid: 60 kg, step 2.5, increment 2.5 → 62.5. From one that is **not** — a number typed by
    /// hand, or history from another gym — the first tap simply brings it onto the grid in the
    /// direction asked for: 61 kg → 62.5 up, 60 down; 134 lb → 135 up. Jumping from 134 to 140
    /// because the arithmetic said 139 is the behavior the owner complained about.
    static func stepped(weight: Double?, by step: Double, up: Bool, increment: Double? = nil) -> Double {
        let base = weight ?? 0
        guard let increment, increment > 0 else {
            let moved = up ? base + step : base - step
            return min(maxWeight, max(0, (moved * 10).rounded() / 10))
        }
        let direction: WeightRounding.Direction = up ? .up : .down
        let target = WeightRounding.isLoadable(base, increment: increment)
            ? (up ? base + step : base - step)
            : base
        return min(maxWeight, WeightRounding.snap(target, increment: increment, direction: direction))
    }

    static func stepped(reps: Int?, up: Bool) -> Int {
        let base = reps ?? 0
        return min(999, max(0, up ? base + 1 : base - 1))
    }

    static func stepped(seconds: Int?, by step: Int, up: Bool) -> Int {
        let base = seconds ?? 0
        return min(99_999, max(0, up ? base + step : base - step))
    }
}

/// One row of `StepCard.setRows` (SPEC §4.5 zone 2).
struct SetRow: Equatable {
    var stepIndex: Int
    var status: StepStatus
    var isCurrent: Bool
    var label: String
    var value: String
    var lastTime: String?
}

/// The step card's text, resolved without view code (SPEC §4.5).
enum StepCard {
    /// "Set 5 of 18" — position among all steps, as the header shows it.
    static func header(session: Session, step index: Int) -> String {
        "Set \(index + 1) of \(session.steps.count)"
    }

    /// "Set 2 of 4", "Set 2 of 4 · drop 1 of 2", or "A · Set 2 of 4" for a superset member.
    ///
    /// D58 (v1.6): plain says who the exercise is paired with instead of tagging it "A", and
    /// calls a drop what it is — a lighter set. `group: false` is for a row that already names
    /// its exercise, where either form would only repeat what the rows around it say.
    static func setLine(session: Session, step index: Int, wording: Wording = .plain,
                        group: Bool = true) -> String {
        guard let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex] else { return "" }
        var text = "Set \(step.setIndex + 1) of \(exercise.targets.count)"
        if group, let tag = exercise.group {
            switch wording {
            case .compact: text = "\(tag) · " + text
            case .plain:
                if let phrase = pairedWith(session: session, step: index) { text += " · " + phrase }
                else { text = "\(tag) · " + text }
            }
        }
        if step.dropIndex > 0, let target = exercise.targets[safe: step.setIndex] {
            text += " · " + drop(step.dropIndex, of: target.drops.count, wording: wording)
        }
        return text
    }

    /// "paired with Tricep Pushdown", or "paired with X and Y" in a longer round. Nil when the
    /// block holds nothing else — a group tag on a lone exercise says nothing plain.
    static func pairedWith(session: Session, step index: Int) -> String? {
        guard let step = session.steps[safe: index] else { return nil }
        var names: [String] = []
        for other in session.steps where other.blockIndex == step.blockIndex
            && other.exerciseIndex != step.exerciseIndex {
            if let name = session.exercises[safe: other.exerciseIndex]?.name,
               !names.contains(name) { names.append(name) }
        }
        guard !names.isEmpty else { return nil }
        let list = names.count == 1 ? names[0]
            : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return "paired with \(list)"
    }

    /// "drop 1 of 2" / "lighter set 1 of 2".
    static func drop(_ index: Int, of count: Int, wording: Wording = .plain) -> String {
        wording == .compact ? "drop \(index) of \(count)" : "lighter set \(index) of \(count)"
    }

    /// The label a list row uses for a step. In a block holding more than one exercise (a
    /// superset), `setLine` alone gives every row the same text — "A · Set 2 of 3" — with no way
    /// to tell the two exercises apart, so the row names the exercise and drops the group tag
    /// that is no longer telling you anything. Shared by the workout's set rows, the Overview
    /// and Session detail, which each used to work this out for themselves.
    static func rowLabel(session: Session, step index: Int, naming: Bool,
                         wording: Wording = .plain) -> String {
        guard naming, let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex] else {
            return setLine(session: session, step: index, wording: wording)
        }
        let bare = setLine(session: session, step: index, wording: wording, group: false)
        return "\(exercise.name) · \(bare)"
    }

    /// True when the step's block holds more than one exercise, i.e. it is a superset round.
    static func blockNamesRows(session: Session, block: Int) -> Bool {
        Set(session.steps.filter { $0.blockIndex == block }.map(\.exerciseIndex)).count > 1
    }

    /// The target line, with the exercise's notes after a "·" when it has any. The set rows of
    /// zone 2 pass `notes: false`: the notes belong to the exercise, and repeating them on all
    /// four of its rows is noise, not information.
    static func targetLine(session: Session, step index: Int, notes: Bool = true,
                           wording: Wording = .plain) -> String {
        guard let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex],
              let resolved = session.target(at: index) else { return "" }
        let target = SetTarget(work: resolved.work, weight: resolved.weight, restSeconds: 0,
                               inReserve: resolved.reserve)
        var text = TargetText.target(target, range: step.dropIndex == 0 ? exercise.repRange : nil,
                                     units: session.units, wording: wording)
        // D42: said once, on the exercise's line, like the notes — never on every row.
        if notes, let was = exercise.substitutedFor { text += " · was \(was)" }
        if notes, let note = exercise.notes?.trimmed, !note.isEmpty { text += " · \(note)" }
        return text
    }

    /// O8: Log set is disabled until the field holds a number.
    static func canLog(repsText: String, isTimed: Bool) -> Bool {
        isTimed ? true : InputRules.repsValue(repsText) != nil
    }

    /// The "Last: 70 kg" line under the weight field, absent when there is nothing to say.
    static func lastWeightLine(_ values: PrefillValues, units: WeightUnit) -> String? {
        values.lastWeight.map { "Last \(TargetText.number($0)) \(units.rawValue)" }
    }

    /// D36 (v1.2): "Try 8 × 82.5 kg". v1.1's chip read "82.5 kg suggested" and appeared only
    /// when the whole exercise had earned progression advice; this one covers every set that
    /// has anything to say, and the reason travels with it.
    static func suggestionChip(_ values: PrefillValues, units: WeightUnit) -> String? {
        if let suggestion = values.suggestion, !suggestion.text.isEmpty { return suggestion.chip }
        return values.suggestedWeight.map { "Try \(TargetText.number($0)) \(units.rawValue)" }
    }

    /// SPEC §9: VoiceOver reads the card as one element — "Bench press, set 2 of 4, target 8 to
    /// 12 reps at 60 kilograms". Written out rather than reusing the visual text, which is full
    /// of dots and dashes that do not read aloud.
    static func spoken(session: Session, step index: Int) -> String {
        guard let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex],
              let target = session.target(at: index) else { return "" }
        var parts = [exercise.name, "set \(step.setIndex + 1) of \(exercise.targets.count)"]
        if let n = target.reserve { parts.append(TargetText.reserve(n)) }
        if step.dropIndex > 0, let set = exercise.targets[safe: step.setIndex] {
            parts.append(drop(step.dropIndex, of: set.drops.count))
        }
        parts.append("target " + spokenWork(target.work, range: step.dropIndex == 0 ? exercise.repRange : nil))
        if let weight = target.weight {
            parts.append("at \(TargetText.number(weight)) \(spokenUnit(session.units))")
        }
        if let notes = exercise.notes?.trimmed, !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: ", ")
    }

    static func spokenUnit(_ units: WeightUnit) -> String {
        units == .kg ? "kilograms" : "pounds"
    }

    /// "Exercise 2 of 5 · Set 2 of 3", "... · drop 1 of 2", or "A · round 2 of 3 · Incline Press"
    /// for a superset member. v1.1 (D22): replaces the header's old "Set 5 of 18", which counted
    /// drops as if they were separate sets.
    static func progress(session: Session, step index: Int, wording: Wording = .plain) -> String {
        guard let step = session.steps[safe: index],
              let exercise = session.exercises[safe: step.exerciseIndex] else { return "" }
        var text: String
        if let group = exercise.group {
            let rounds = (session.steps.filter { $0.blockIndex == step.blockIndex }.map(\.setIndex).max()
                          ?? step.setIndex) + 1
            // D58: the round and the exercise are the content; "A" is a label for the round.
            let tag = wording == .compact ? "\(group) · round" : "Round"
            text = "\(tag) \(step.setIndex + 1) of \(rounds) · \(exercise.name)"
        } else {
            // The same count the stage uses (D34), so the header cannot disagree with itself
            // after "Do later" (D28) or a substitution (D42).
            let order = SessionBlocks.exerciseOrder(session)
            let position = (order.firstIndex(of: SessionBlocks.canonical(session, step.exerciseIndex)) ?? 0) + 1
            text = "Exercise \(position) of \(max(order.count, position))"
                 + " · Set \(step.setIndex + 1) of \(exercise.targets.count)"
        }
        if step.dropIndex > 0, let target = exercise.targets[safe: step.setIndex] {
            text += " · " + drop(step.dropIndex, of: target.drops.count, wording: wording)
        }
        return text
    }

    /// A logged step's short result text, e.g. "10 × 80" or "10 × 80 · 0:34" with its set time.
    /// D58 (v1.6): "×" reads as "by" to everyone; "@" read as an email address to the audit's
    /// stranger. Compact keeps "@".
    static func resultText(_ result: SetResult, setSeconds: Int? = nil,
                           wording: Wording = .plain) -> String {
        var text = result.reps.map(String.init) ?? result.seconds.map(TargetText.time) ?? ""
        if let weight = result.weight {
            text += "\(wording == .compact ? " @ " : " × ")\(TargetText.number(weight))"
        }
        if let setSeconds { text += " · \(TargetText.time(setSeconds))" }
        return text
    }

    /// The current exercise's set rows (SPEC §4.5 zone 2): every set of a straight exercise, or
    /// just the current round's members for a superset. Written and tested in v1.1's R1
    /// milestone; R2 renders it. `history` is history only, never the current session.
    static func setRows(session: Session, step index: Int, history: [Session],
                        wording: Wording = .plain) -> [SetRow] {
        guard let step = session.steps[safe: index],
              session.exercises[safe: step.exerciseIndex] != nil else { return [] }
        let exercise = session.exercises[step.exerciseIndex]
        let indices: [Int]
        if exercise.group != nil {
            indices = session.steps.indices.filter {
                session.steps[$0].blockIndex == step.blockIndex && session.steps[$0].setIndex == step.setIndex
            }
        } else {
            // An ungrouped exercise is its own block, so this is the exercise's steps — and,
            // after a substitution (D42), the logged sets of the exercise it stood in for,
            // which stay on screen under their own name rather than vanishing.
            indices = session.steps.indices.filter { session.steps[$0].blockIndex == step.blockIndex }
        }
        let naming = blockNamesRows(session: session, block: step.blockIndex)
        return indices.map { i in
            let s = session.steps[i]
            let value: String
            switch s.status {
            case .pending: value = targetLine(session: session, step: i, notes: false,
                                              wording: wording)
            case .skipped: value = "skipped"
            // D19 (v1.1): no set duration here. A finished row reads "10 @ 80"; the seconds
            // belong to the Overview, Session detail, the strip and the Summary's details,
            // never to the screen you are working on.
            case .logged: value = s.result.map { resultText($0, wording: wording) } ?? ""
            }
            // D58 (v1.6): the row's second line is a sentence — "Last time 10 × 100 kg" —
            // written here rather than in the view, so a test can pin it (Y13's rule).
            let lastTime = Prefill.historicalResult(session: session, step: i, history: history)
                .map { result -> String in
                    let text = resultText(result, wording: wording)
                    guard wording == .plain else { return "last " + text }
                    let unit = result.weight == nil ? "" : " \(session.units.rawValue)"
                    return "Last time " + text + unit
                }
            return SetRow(stepIndex: i, status: s.status, isCurrent: i == index,
                         label: rowLabel(session: session, step: i, naming: naming,
                                         wording: wording),
                         value: value, lastTime: lastTime)
        }
    }

    /// The status strip's block-just-finished line (SPEC §4.7): "Barbell Row done · 9:40 ·
    /// try 72.5 kg next time". `nil` only when the block has no identifiable exercise.
    static func blockDoneLine(session: Session, blockDone: BlockDone) -> String? {
        let steps = session.steps.filter { $0.blockIndex == blockDone.finishedBlock }
        // D42: a block that ended on a substitute is named for the substitute — that is the
        // exercise that was just done.
        guard let first = steps.first,
              let exercise = steps.compactMap({ session.exercises[safe: $0.exerciseIndex] })
                .first(where: { $0.replaces != nil })
                ?? session.exercises[safe: first.exerciseIndex] else { return nil }
        var text = "\(exercise.name) done"
        if let seconds = SessionStats.blockDuration(blockDone.finishedBlock, session: session) {
            text += " · \(TargetText.time(seconds))"
        }
        for i in Set(steps.map(\.exerciseIndex)).sorted() {
            guard let e = session.exercises[safe: i], let advice = e.advice, let range = e.repRange else { continue }
            let logged = session.steps.filter { $0.exerciseIndex == i && $0.status == .logged }
            text += " · " + ProgressionAdvice.message(advice, range: range, loggedSets: logged.count,
                                                       currentWeight: logged.first?.result?.weight,
                                                       units: session.units)
        }
        return text
    }

    private static func spokenWork(_ work: WorkTarget, range: RepRange?) -> String {
        switch work {
        case let .duration(seconds): return "\(seconds) seconds"
        case let .openDuration(minimum):
            return minimum.map { "at least \($0) seconds" } ?? "as long as possible"
        case let .reps(target):
            switch target {
            case let .fixed(n):
                guard let range, range.min != n || range.max != n else { return "\(n) reps" }
                return "\(n) reps, range \(range.min) to \(range.max)"
            case let .range(low, high): return "\(low) to \(high) reps"
            case let .amrap(minimum):
                return minimum.map { "at least \($0) reps" } ?? "as many reps as possible"
            }
        }
    }
}
