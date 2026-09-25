import Foundation

/// D52 (v1.5): a plan built in several pastes. The outline first — name, units, schedule, the
/// day names and the repeat block, no exercises — then one paste per day into its slot, and
/// the whole thing through the ordinary import once, so the app holds nothing it would refuse.
///
/// The owner's concern was size: a six-day plan is 4–5,000 characters of JSON, over what a
/// free chatbot tier writes in one reply. One day at a time is a paste anyone can carry.
struct PlanDraft: Codable, Equatable {
    /// The chatbot's outline reply, as pasted. Re-read at assembly, so the draft holds what
    /// you pasted rather than a rendering of it.
    var outlineText: String
    /// The outline read as a plan: its header and its days, most of them empty.
    var outline: Plan
    /// One fragment per day, as pasted; nil until it is.
    var dayTexts: [String?]
    var createdAt: Date

    var filled: Int { dayTexts.filter { $0 != nil }.count }
    var isComplete: Bool { !dayTexts.isEmpty && dayTexts.allSatisfy { $0 != nil } }
    /// "2 of 4 days pasted"
    var progress: String { "\(filled) of \(dayTexts.count) day\(dayTexts.count == 1 ? "" : "s") pasted" }

    enum CodingKeys: String, CodingKey { case outlineText, outline, dayTexts, createdAt }
}

extension PlanDraft {
    /// SPEC §8.3's rule, as for every file: what makes it this draft is required, the rest
    /// has a default. A draft file written by a later version with more in it still reads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outline = try container.decode(Plan.self, forKey: .outline)
        self.init(outlineText: try container.decode(String.self, forKey: .outlineText),
                  outline: outline,
                  dayTexts: container.value(.dayTexts, or: Array(repeating: nil, count: outline.days.count)),
                  createdAt: container.value(.createdAt, or: Date(timeIntervalSince1970: 0)))
    }
}

enum PlanDrafting {
    /// The outline read with the ordinary importer, empty days allowed. A chatbot that wrote
    /// the whole plan anyway is not refused: its days arrive already filled.
    static func outline(_ text: String, settings: Settings, now: Date = Date()) -> (draft: PlanDraft?, issues: [Issue]) {
        let result = PlanImport.run(text, settings: settings, now: now, allowEmptyDays: true)
        guard let plan = result.plan else { return (nil, result.issues) }
        let texts: [String?] = plan.days.map { $0.exercises.isEmpty ? nil : PlanJSON.render(day: $0) }
        return (PlanDraft(outlineText: text, outline: plan, dayTexts: texts, createdAt: now), result.issues)
    }

    /// A day pasted into slot `index`, read as generously as any fragment (D43) — a day, a plan
    /// holding it, a list of exercises — named by the slot, and checked as that day alone under
    /// the outline's header (`tried`). Errors carry the slot's real path, so the sentence says
    /// "Day 3".
    static func day(_ text: String, into draft: PlanDraft, index: Int, settings: Settings,
                    now: Date = Date()) -> (draft: PlanDraft?, issues: [Issue]) {
        let trial = tried(text, in: draft, index: index, settings: settings, now: now)
        let errors = trial.issues.filter { $0.severity == .error }
        let warnings = trial.issues.filter { $0.severity == .warning }
        guard trial.day != nil else { return (nil, errors + warnings) }
        var updated = draft
        updated.dayTexts[index] = text
        return (updated, warnings)
    }

    /// The plan the review draws while a draft is being filled (D91): the outline, with every
    /// pasted day in its slot so its exercises show, read as `day` read it; a slot that no longer
    /// reads, and a slot not pasted yet, stays empty.
    static func preview(_ draft: PlanDraft, settings: Settings, now: Date = Date()) -> Plan {
        var plan = draft.outline
        for (index, text) in draft.dayTexts.enumerated() {
            guard let text, let day = tried(text, in: draft, index: index, settings: settings, now: now).day else { continue }
            plan.days[index] = day
        }
        return plan
    }

    /// Slot `index`'s text as that day alone under the outline's header — the check a day's paste
    /// runs before it is taken, and the day the review draws once it has been. Checked alone: this
    /// one day and no repeat block, since the block names days that are not here yet, and this is
    /// not the moment to say so. Paths are the slot's.
    private static func tried(_ text: String, in draft: PlanDraft, index: Int, settings: Settings,
                              now: Date) -> (day: Day?, issues: [Issue]) {
        guard draft.dayTexts.indices.contains(index), let slot = draft.outline.days[safe: index] else {
            return (nil, [invalid("That day isn't in the outline.", path: "days[\(index)]")])
        }
        let read = dayObject(text, for: slot, index: index)
        guard let object = read.object else { return (nil, read.issues) }
        guard var tree = outlineTree(draft) else {
            return (nil, [invalid("The outline can't be read any more. Discard the draft and paste it again.", path: "")])
        }
        tree["days"] = .array([.object(object)])
        tree["cycle"] = nil
        let trial = PlanImport.run(RawJSON.object(tree).jsonText, settings: settings, now: now)
        let issues = read.issues + trial.issues.map { issue in
            var moved = issue
            if moved.path.hasPrefix("days[0]") { moved.path = "days[\(index)]" + moved.path.dropFirst("days[0]".count) }
            return moved
        }
        return (trial.plan?.days.first, issues)
    }

    /// The whole plan's JSON: the outline's tree with every slot's day in place of its empty
    /// one. Nil, with a reason, while a slot is still empty.
    static func assembledText(_ draft: PlanDraft) -> (text: String?, issues: [Issue]) {
        guard draft.isComplete else {
            let left = draft.dayTexts.count - draft.filled
            return (nil, [Issue(severity: .error, code: "E_DRAFT_INCOMPLETE", path: "",
                                message: "\(left) of \(draft.dayTexts.count) days still to paste.")])
        }
        guard var tree = outlineTree(draft) else {
            return (nil, [invalid("The outline can't be read any more. Discard the draft and paste it again.", path: "")])
        }
        var days: [RawJSON] = []
        var issues: [Issue] = []
        for (index, slot) in draft.outline.days.enumerated() {
            guard let text = draft.dayTexts[index] else { continue }
            let read = dayObject(text, for: slot, index: index)
            guard let object = read.object else { return (nil, issues + read.issues) }
            issues += read.issues
            days.append(.object(object))
        }
        tree["days"] = .array(days)
        return (RawJSON.object(tree).jsonText, issues)
    }

    /// Every slot filled, through the ordinary import once. The plan's text is the canonical
    /// rendering, as after any edit.
    static func assemble(_ draft: PlanDraft, settings: Settings, now: Date = Date()) -> ImportResult {
        let built = assembledText(draft)
        guard let text = built.text else { return ImportResult(plan: nil, issues: built.issues) }
        var result = PlanImport.run(text, settings: settings, now: now)
        result.issues = built.issues + result.issues
        if var plan = result.plan {
            plan.sourceText = PlanJSON.render(plan)
            plan.warnings = result.issues.filter { $0.severity == .warning }
            result.plan = plan
        }
        return result
    }

    // MARK: - Pieces

    /// The outline's JSON tree, re-read from the text as pasted; a bare list of days is wrapped
    /// the way the importer wraps it.
    static func outlineTree(_ draft: PlanDraft) -> [String: RawJSON]? {
        guard let body = PlanImport.extract(draft.outlineText).value,
              let raw = PlanImport.decode(body).value else { return nil }
        if let object = raw.object { return object }
        if let list = raw.array { return ["days": .array(list)] }
        return nil
    }

    /// The one day the fragment holds for this slot: the only one, or the one named like the
    /// slot when several came. The slot names the day — the outline decided that, and the
    /// repeat block refers to it — and lends its weekday when the fragment has none.
    static func dayObject(_ text: String, for slot: Day, index: Int) -> (object: [String: RawJSON]?, issues: [Issue]) {
        let parsed = PlanEdit.fragment(text, as: .days)
        guard let values = parsed.values else { return (nil, parsed.issues) }
        let chosen = values.count == 1
            ? values[0]
            : values.first { normalized($0["name"]?.string ?? "") == normalized(slot.name) }
        guard var object = chosen?.object else {
            return (nil, parsed.issues + [invalid(
                "Paste one day here — \"\(slot.name)\" — or a plan that has a day by that name.",
                path: "days[\(index)]")])
        }
        object["name"] = .string(slot.name)
        if let weekday = slot.weekday, object["weekday"] == nil { object["weekday"] = .string(weekday.rawValue) }
        return (object, parsed.issues)
    }

    private static func invalid(_ message: String, path: String) -> Issue {
        Issue(severity: .error, code: "E_EDIT_INVALID", path: path, message: message)
    }
}
