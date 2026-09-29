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
    /// The paste the pipeline refused — the outline's or a day's — whose sentence sits under the
    /// strip. A refused day stays hollow. Its way back is the prompt it answered, again.
    private(set) var refusal: TripRefusal?
    /// The plan the review draws (`PlanDrafting.preview`), read when the draft changes rather
    /// than each time the screen is drawn; nil before the outline.
    private(set) var preview: Plan?

    /// A draft in progress reopens where it was (§6.64): on its review, asking for the next day,
    /// or with Use when every day is in. Without one, Ask sends the outline prompt.
    init(draft: PlanDraft?, settings: Settings, now: Date = Date()) {
        self.draft = draft
        stage = draft?.isComplete == true ? .review : .ask
        preview = draft.map { PlanDrafting.preview($0, settings: settings, now: now) }
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

    var strip: TripStrip { TripStrip.of(stage, fix: refusal?.fix ?? .chat) }

    /// What the prompt buttons call the prompt: *the outline prompt*, *the prompt for Pull*.
    private var promptName: String { nextName.map { "the prompt for \($0)" } ?? "the outline prompt" }

    var buttons: TripButtons {
        switch stage {
        case .ask: return .ask(promptName)
        case .refused: return refusal?.buttons(prompt: promptName) ?? .ask(promptName)
        case .paste: return TripButtons(primary: nextName.map { "Paste \($0)" } ?? "Paste the outline", secondary: nil)
        case .review: return .effect(draft.map { "Use \($0.outline.name)" } ?? "Use this plan")
        }
    }

    /// What Send and Copy send: the next hollow day's prompt (PROMPT.md §5), or the outline's
    /// (§4) before there is one.
    func prompt(settings: Settings) -> String {
        guard let draft, let next else { return Prompts.outline(settings: settings) }
        return Prompts.day(outline: draft.outline, dayIndex: next, settings: settings)
    }

    /// The share sheet's subject.
    var subject: String { nextName.map { "\($0), one day" } ?? "A plan's outline" }

    /// The ···: **Keep without using** once every day is in, **Discard the draft** once there is
    /// one, and **Edit the text** last (D95).
    var menu: [TripMenuItem] {
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

    /// The outline pasted (`PlanDrafting.outline`, through `AppModel.startDraft`), or a day into
    /// its slot (`PlanDrafting.day`, through `AppModel.pasteDraftDay`): the review with every
    /// unfilled day hollow — none, when the chatbot wrote the whole plan — and the buttons on the
    /// next of them; or the refusal, the day left hollow with the sentence under the strip.
    mutating func pasted(_ read: (draft: PlanDraft?, issues: [Issue]), settings: Settings, now: Date = Date()) {
        if let updated = read.draft {
            draft = updated
            preview = PlanDrafting.preview(updated, settings: settings, now: now)
            refusal = nil
            stage = updated.isComplete ? .review : .ask
        } else {
            refusal = TripRefusal.of(read.issues, way: .prompt)
            stage = .refused
        }
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
        if let draft, let next, let day = JSONPoint.draftDay(draft.outline, index: next) { return day }
        if let assembled { return JSONPoint.assembled(draft?.outline.name ?? "the plan", text: assembled) }
        return JSONPoint.outline
    }
}
