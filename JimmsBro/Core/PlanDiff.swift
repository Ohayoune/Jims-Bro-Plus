import Foundation

/// SPEC §6.67 (D94, v1.11): what a change did to a plan — the review of **Say what should
/// change** draws this and nothing else. The reply is a whole plan (PROMPT.md §7); the owner asked
/// for one sentence's worth of difference, and this finds it:
///
/// - **Days** are matched by name. A day the reply renamed is a day removed and a day added: a
///   day paired by its position and renamed would have no line to say so, and the review would
///   read *Nothing changed* over a plan that had changed (D55).
/// - **Exercises**, within a matched day, are matched by name in order — the longest run of names
///   the two days share — and then by position between those matches: a different name where an
///   old one stood is **replaced**. The same name with different targets is **changed**; what is
///   left is **removed** or **added**. An exercise moved within its day is two lines, not none —
///   the plan's choice; a *moved* line is parked.
/// - **The plan's own fields** — its name, its unit, its cycle (when no day came or went, since
///   then the day's own line says so), its walk between exercises — are lines too, so a reply
///   that changed only those is not *Nothing changed*.
struct PlanDiff: Equatable {
    /// A field of the plan itself, outside any day.
    enum Field: String, Equatable {
        case name = "Name"
        case units = "Units"
        case schedule = "Cycle"
        case walk = "Walk between exercises"
    }

    enum Line: Equatable {
        /// A different name at a matched position: the old name, and the exercise now there.
        case replaced(day: String, old: String, new: Exercise)
        /// The same name, different targets — `TargetText.summary` both sides.
        case changed(day: String, name: String, from: String, to: String)
        case removed(day: String, name: String)
        case added(day: String, exercise: Exercise)
        case dayAdded(Day)
        case dayRemoved(String)
        case dayUnchanged(String)
        case plan(Field, from: String, to: String)

        var isUnchanged: Bool { if case .dayUnchanged = self { return true }; return false }
    }

    /// The review's grouping: the plan's own lines first, then one group per day in the reply's
    /// order, a removed day where it stood.
    struct Group: Equatable {
        /// Nil for the plan's own lines.
        var day: String?
        /// The day's place in the plan it belongs to — the reply's, or the old plan's for a
        /// removed day — which is what gives its square a colour (D65).
        var dayIndex: Int?
        var lines: [Line]
    }

    /// One line as the review draws it (§6.67): a name struck, a name in ink, and the targets or
    /// the word beside them.
    struct Row: Equatable {
        enum Mark: Equatable { case replaced, changed, removed, added, unchanged, plan }
        var mark: Mark
        /// The old name, struck through.
        var struck: String?
        /// The name as it is now, in ink.
        var name: String?
        /// The new targets, *removed*, *added*, or from → to.
        var detail: String?

        /// What VoiceOver reads, since a strike is not heard: "Barbell Bench Press, replaced by
        /// Dumbbell Bench Press, 4 sets of 6–8 reps · 32 kg".
        var spoken: String {
            switch mark {
            case .replaced: return [struck ?? "", "replaced by " + (name ?? ""), detail].compactMap { $0 }.joined(separator: ", ")
            case .removed: return [struck, detail].compactMap { $0 }.joined(separator: ", ")
            default: return [name, detail].compactMap { $0 }.joined(separator: ", ")
            }
        }
    }

    var groups: [Group]
    /// The reply's unit, for its exercises' targets.
    var units: WeightUnit
    var wording: Wording

    var lines: [Line] { groups.flatMap(\.lines) }
    /// Every line but a day unchanged.
    var count: Int { lines.filter { !$0.isUnchanged }.count }

    static func between(old: Plan, new: Plan, wording: Wording = .plain) -> PlanDiff {
        var keyed: [(key: Double, group: Group)] = []

        // Days, by name.
        var unmatchedNew = Set(new.days.indices)
        var pairs: [Int: Int] = [:] // the reply's index → the old plan's
        var removedDays: [Int] = []
        for (oldIndex, day) in old.days.enumerated() {
            if let newIndex = new.days.indices.first(where: {
                unmatchedNew.contains($0) && normalized(new.days[$0].name) == normalized(day.name)
            }) {
                unmatchedNew.remove(newIndex)
                pairs[newIndex] = oldIndex
            } else {
                removedDays.append(oldIndex)
            }
        }
        for (newIndex, day) in new.days.enumerated() {
            let lines: [Line]
            if let oldIndex = pairs[newIndex] {
                let changes = exerciseLines(day: day.name, old: old.days[oldIndex].exercises, oldUnits: old.units,
                                            new: day.exercises, newUnits: new.units, wording: wording)
                lines = changes.isEmpty ? [.dayUnchanged(day.name)] : changes
            } else {
                lines = [.dayAdded(day)]
            }
            keyed.append((Double(newIndex), Group(day: day.name, dayIndex: newIndex, lines: lines)))
        }
        for oldIndex in removedDays {
            let name = old.days[oldIndex].name
            keyed.append((Double(oldIndex) - 0.5, Group(day: name, dayIndex: oldIndex, lines: [.dayRemoved(name)])))
        }
        // Stable: a removed day stands just before the day that now has its place.
        let days = keyed.enumerated()
            .sorted { $0.element.key == $1.element.key ? $0.offset < $1.offset : $0.element.key < $1.element.key }
            .map(\.element.group)

        var planLines: [Line] = []
        if old.name.trimmed != new.name.trimmed {
            planLines.append(.plan(.name, from: old.name.trimmed, to: new.name.trimmed))
        }
        if old.units != new.units {
            planLines.append(.plan(.units, from: old.units.rawValue, to: new.units.rawValue))
        }
        if removedDays.isEmpty, unmatchedNew.isEmpty {
            let from = scheduleText(old), to = scheduleText(new)
            if normalized(from) != normalized(to) { planLines.append(.plan(.schedule, from: from, to: to)) }
        }
        if old.restBetweenExercises != new.restBetweenExercises {
            planLines.append(.plan(.walk, from: walkText(old.restBetweenExercises),
                                   to: walkText(new.restBetweenExercises)))
        }
        let plan = planLines.isEmpty ? [] : [Group(day: nil, dayIndex: nil, lines: planLines)]
        return PlanDiff(groups: plan + days, units: new.units, wording: wording)
    }

    /// The row the review draws for a line.
    func row(_ line: Line) -> Row {
        switch line {
        case let .replaced(_, old, new):
            return Row(mark: .replaced, struck: old, name: new.name,
                       detail: TargetText.summary(new, units: units, wording: wording))
        case let .changed(_, name, from, to):
            return Row(mark: .changed, struck: nil, name: name, detail: "\(from) → \(to)")
        case let .removed(_, name):
            return Row(mark: .removed, struck: name, name: nil, detail: "removed")
        case let .added(_, exercise):
            return Row(mark: .added, struck: nil, name: exercise.name,
                       detail: "added · " + TargetText.summary(exercise, units: units, wording: wording))
        case let .dayAdded(day):
            let count = day.exercises.count
            return Row(mark: .added, struck: nil, name: day.name,
                       detail: "added · \(count) exercise\(count == 1 ? "" : "s")")
        case let .dayRemoved(name):
            return Row(mark: .removed, struck: name, name: nil, detail: "removed")
        case let .dayUnchanged(name):
            return Row(mark: .unchanged, struck: nil, name: name, detail: "No change")
        case let .plan(field, from, to):
            return Row(mark: .plan, struck: nil, name: field.rawValue, detail: "\(from) → \(to)")
        }
    }

    // MARK: - Exercises

    private static func exerciseLines(day: String, old: [Exercise], oldUnits: WeightUnit,
                                      new: [Exercise], newUnits: WeightUnit, wording: Wording) -> [Line] {
        let anchors = commonNames(old.map { normalized($0.name) }, new.map { normalized($0.name) })
        let matchedOld = Set(anchors.map(\.old)), matchedNew = Set(anchors.map(\.new))
        let leftOld = Set(old.indices.filter { !matchedOld.contains($0) }.map { normalized(old[$0].name) })
        let leftNew = Set(new.indices.filter { !matchedNew.contains($0) }.map { normalized(new[$0].name) })
        let shared = Set(anchors.map { normalized(old[$0.old].name) })

        var lines: [Line] = []
        var o = 0, n = 0
        for anchor in anchors + [(old: old.count, new: new.count)] {
            let gapOld = Array(o..<anchor.old), gapNew = Array(n..<anchor.new)
            var removed: [Int] = [], added: [Int] = []
            for k in 0..<max(gapOld.count, gapNew.count) {
                switch (gapOld[safe: k], gapNew[safe: k]) {
                case let (i?, j?):
                    // A name still in the day somewhere else was moved, not replaced.
                    if leftNew.contains(normalized(old[i].name)) || leftOld.contains(normalized(new[j].name)) {
                        removed.append(i)
                        added.append(j)
                    } else {
                        lines.append(.replaced(day: day, old: old[i].name, new: new[j]))
                    }
                case let (i?, nil): removed.append(i)
                case let (nil, j?): added.append(j)
                case (nil, nil): break
                }
            }
            lines += removed.map { .removed(day: day, name: old[$0].name) }
            lines += added.map { .added(day: day, exercise: new[$0]) }
            if anchor.old < old.count, anchor.new < new.count {
                let before = old[anchor.old], after = new[anchor.new]
                let pairedBefore = pairing(anchor.old, in: old, among: shared)
                let pairedAfter = pairing(anchor.new, in: new, among: shared)
                if differs(before, after) || pairedBefore != pairedAfter {
                    let text = changeText(before, oldUnits, pairedBefore, after, newUnits, pairedAfter, wording)
                    lines.append(.changed(day: day, name: after.name, from: text.from, to: text.to))
                } else if oldUnits != newUnits {
                    // The same numbers in another unit are other weights; a bodyweight
                    // exercise, which says no unit, is the same exercise.
                    let from = TargetText.summary(before, units: oldUnits, wording: wording)
                    let to = TargetText.summary(after, units: newUnits, wording: wording)
                    if from != to { lines.append(.changed(day: day, name: after.name, from: from, to: to)) }
                }
            }
            o = anchor.old + 1
            n = anchor.new + 1
        }
        return lines
    }

    /// The longest run of names two days share, in order, as index pairs.
    private static func commonNames(_ a: [String], _ b: [String]) -> [(old: Int, new: Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [(old: Int, new: Int)] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }

    /// Everything but the id, which every import makes afresh, and the group — its letter and its
    /// round rest are the importer's to work out (a lone tag is dropped, a repeated one renamed),
    /// so who an exercise is paired with is compared instead (`pairing`).
    private static func differs(_ a: Exercise, _ b: Exercise) -> Bool {
        func written(_ exercise: Exercise) -> Exercise {
            var exercise = exercise
            exercise.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            exercise.group = nil
            for index in exercise.sets.indices { exercise.sets[index].groupRestSeconds = nil }
            return exercise
        }
        return written(a) != written(b)
    }

    /// "paired with Face Pull", or "on its own": who shares the exercise's group in its day,
    /// counting only the exercises both days have — a partner removed or added has its own line,
    /// so a superset that lost its partner is not a second change beside the removal.
    private static func pairing(_ index: Int, in exercises: [Exercise], among shared: Set<String>) -> String {
        guard let group = exercises[index].group.map(normalized), !group.isEmpty else { return "on its own" }
        let partners = exercises.indices
            .filter { $0 != index && exercises[$0].group.map(normalized) == group
                && shared.contains(normalized(exercises[$0].name)) }
            .map { exercises[$0].name }
        return partners.isEmpty ? "on its own" : "paired with " + partners.joined(separator: " and ")
    }

    /// The targets from and to. `TargetText.summary` says the sets, the reps, the weight and the
    /// effort; when a change is in something it does not say, the rest is said too, so a line
    /// never reads the same on both sides of its arrow.
    private static func changeText(_ a: Exercise, _ aUnits: WeightUnit, _ aPairing: String,
                                   _ b: Exercise, _ bUnits: WeightUnit, _ bPairing: String,
                                   _ wording: Wording) -> (from: String, to: String) {
        var from = TargetText.summary(a, units: aUnits, wording: wording)
        var to = TargetText.summary(b, units: bUnits, wording: wording)
        guard from == to else { return (from, to) }
        let restA = restText(a), restB = restText(b)
        if restA != restB { return (from + " · " + restA, to + " · " + restB) }
        if aPairing != bPairing { return (from + " · " + aPairing, to + " · " + bPairing) }
        if a.notes != b.notes {
            from += a.notes == nil ? " · no notes" : " · notes"
            to += b.notes == nil ? " · no notes" : " · new notes"
        } else {
            to += " · other details"
        }
        return (from, to)
    }

    private static func restText(_ exercise: Exercise) -> String {
        let rests = Set(exercise.sets.map(\.restSeconds))
        guard rests.count == 1, let rest = rests.first else { return "rest varies" }
        return "rest \(TargetText.time(rest))"
    }

    /// "Push · Pull · Legs · rest" for a rotation; "Monday Push · Thursday Pull" by weekday.
    static func scheduleText(_ plan: Plan) -> String {
        switch plan.schedule {
        case .rotation:
            return plan.cycle.map { entry in
                if case let .day(index) = entry { return plan.days[safe: index]?.name ?? "?" }
                return "rest"
            }.joined(separator: " · ")
        case .weekday:
            func place(_ day: Day) -> Int { day.weekday.flatMap { Weekday.allCases.firstIndex(of: $0) } ?? 7 }
            return plan.days.sorted { place($0) < place($1) }
                .map { day in day.weekday.map { "\($0.rawValue.capitalized) \(day.name)" } ?? day.name }
                .joined(separator: " · ")
        }
    }

    private static func walkText(_ seconds: Int?) -> String {
        seconds.map(TargetText.time) ?? "the setting"
    }
}
