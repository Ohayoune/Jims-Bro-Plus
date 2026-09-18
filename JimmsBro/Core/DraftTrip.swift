import Foundation

/// SPEC §6.64 (D91, v1.11): **day by day, offered on refusal**, as data. D52's pipeline —
/// `PlanDrafting`, `PlanDraft`, the outline and day prompts, `draft.json` — is untouched; this is
/// its screen. Before the outline there is no draft, and Ask sends **the outline prompt**; once
/// the outline is in, Add plan's review draws the plan with every unfilled day **hollow**, and
/// the bottom slot alternates **Send the prompt for Pull** and **Paste Pull**, always for the
/// first hollow day, until none is hollow and it reads **Use Push Pull Legs**.
struct DraftTrip: Equatable {
    /// The draft as the model holds it; nil until the outline is pasted.
    private(set) var draft: PlanDraft?
    private(set) var stage: TripStage
    /// The paste the pipeline refused — the outline's or a day's — whose sentences sit under the
    /// strip. A refused day stays hollow.
    private(set) var refusal: ImportTrip.Refusal?

    /// A draft in progress reopens where it was (§6.64): on its review, asking for the next day,
    /// or with Use when every day is in. Without one, Ask sends the outline prompt.
    init(draft: PlanDraft?) {
        self.draft = draft
        stage = draft?.isComplete == true ? .review : .ask
    }

    /// The days not pasted yet.
    var hollow: Set<Int> {
        guard let draft else { return [] }
        return Set(draft.dayTexts.indices.filter { draft.dayTexts[$0] == nil })
    }

    /// The day the buttons are for: the first hollow one.
    var next: Int? { hollow.min() }

    /// The next day's name, "Pull".
    var nextName: String? { next.flatMap { draft?.outline.days[safe: $0]?.name } }

    var strip: TripStrip { TripStrip.of(stage, fixAt: refusal?.fixAt ?? 1) }

    /// What the prompt buttons call the prompt: *the outline prompt*, *the prompt for Pull*.
    private var prompt: String { nextName.map { "the prompt for \($0)" } ?? "the outline prompt" }

    var buttons: TripButtons {
        switch stage {
        case .ask, .refused: return .ask(prompt)
        case .paste: return TripButtons(primary: nextName.map { "Paste \($0)" } ?? "Paste the outline", secondary: nil)
        case .review: return .effect(draft.map { "Use \($0.outline.name)" } ?? "Use this plan")
        }
    }

    /// The ···: **Keep without using** once every day is in, **Discard the draft** once there is
    /// one, and **Edit the text** last (D95).
    var menu: [ImportTrip.MenuItem] {
        guard draft != nil else { return [.editText] }
        return stage == .review ? [.keepWithoutUsing, .discardDraft, .editText] : [.discardDraft, .editText]
    }

    // MARK: - Transitions

    /// The outline prompt, or the next day's, went out.
    mutating func sent() {
        guard stage != .review else { return }
        stage = .paste
        refusal = nil
    }

    /// The outline pasted (`PlanDrafting.outline`, through `AppModel.startDraft`): the review
    /// with every day hollow — or already filled, when the chatbot wrote the whole plan — or the
    /// refusal.
    mutating func pastedOutline(_ read: (draft: PlanDraft?, issues: [Issue])) {
        take(read)
    }

    /// A day pasted into its slot (`PlanDrafting.day`, through `AppModel.pasteDraftDay`): its
    /// square fills and the buttons move to the next hollow day, or it stays hollow with the
    /// sentence under the strip.
    mutating func pasted(index: Int, read: (draft: PlanDraft?, issues: [Issue])) {
        take(read)
    }

    private mutating func take(_ read: (draft: PlanDraft?, issues: [Issue])) {
        if let updated = read.draft {
            draft = updated
            refusal = nil
            stage = updated.isComplete ? .review : .ask
        } else {
            refusal = ImportTrip.Refusal.of(read.issues.filter { $0.severity == .error })
            stage = .refused
        }
    }

    // MARK: - The review

    /// The plan the review draws: the outline, with every pasted day in its slot so its
    /// exercises show, and the hollow days empty. Read as `PlanDrafting.day` read it; a slot
    /// that no longer reads stays empty.
    func preview(settings: Settings, now: Date = Date()) -> Plan? {
        guard var plan = draft?.outline, let draft else { return nil }
        for (index, text) in draft.dayTexts.enumerated() {
            guard let text, let slot = plan.days[safe: index],
                  let object = PlanDrafting.dayObject(text, for: slot, index: index).object,
                  var tree = PlanDrafting.outlineTree(draft) else { continue }
            tree["days"] = .array([.object(object)])
            tree["cycle"] = nil
            guard let day = PlanImport.run(RawJSON.object(tree).jsonText, settings: settings, now: now).plan?.days.first
            else { continue }
            plan.days[index] = day
        }
        return plan
    }

    // MARK: - The text behind the ··· (D95)

    /// Where **Edit the text** saves: the next hollow day's slot, or — before the outline, or
    /// with every day in — a new outline, which may be the whole plan.
    enum TextTarget: Equatable {
        case day(Int)
        case outline
    }

    var textTarget: TextTarget { next.map(TextTarget.day) ?? .outline }

    /// The sheet for `textTarget`: the next day on D77's example day, named for its slot; the
    /// outline's example; or, with every day in, the whole plan as it would be saved.
    func textPoint(assembled: String?) -> JSONPoint {
        if let next, let draft, let slot = draft.outline.days[safe: next] {
            return JSONPoint(
                kind: .day(next), title: "One day",
                place: "\(slot.name), day \(next + 1) of \(draft.outline.days.count) in \(draft.outline.name)",
                template: JSONPoint.exampleDay(name: slot.name, weekday: slot.weekday),
                saveTitle: "Add \(slot.name)",
                footer: "One day, in the same fields as a pasted plan's day.")
        }
        if let assembled {
            return JSONPoint(
                kind: .plan, title: "The plan", place: "All of \(draft?.outline.name ?? "the plan"), before it is saved.",
                template: assembled, saveTitle: "Review the plan",
                footer: "A whole plan, in the fields the prompt asks a chatbot for.")
        }
        return JSONPoint(
            kind: .plan, title: "The outline", place: "The plan's name and its days, with no exercises yet.",
            template: Self.exampleOutline, saveTitle: "Use this outline",
            footer: "The days are pasted one at a time after it.")
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
}
