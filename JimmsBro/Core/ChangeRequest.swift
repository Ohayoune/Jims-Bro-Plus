import Foundation

/// SPEC §6.67 (D94, v1.11): **Say what should change**, as a trip (§6.60). One field holds the
/// request; the prompt carries it and the whole plan (PROMPT.md §7); the reply is read as any plan
/// (`PlanImport.run`) and reviewed as what changed (`PlanDiff`); **Apply** is an edit. The view
/// draws this and never composes it.
struct ChangeRequest: Equatable {
    /// Plan detail's ··· item.
    static let menuItem = "Say what should change"
    /// The field's placeholder.
    static let placeholder = "What should change?"
    /// Under *Nothing changed*, with the strip lit at Chat.
    static let nothingChanged = "The reply is the plan as it was. Say it differently, or ask the chatbot again."
    /// A refused reply's way back: the fix-it prompt (`Prompts.render(errors:)`), as on Add plan.
    static let askAgain = TripButtons(primary: "Ask for the whole plan", secondary: "Copy the prompt")
    /// The codes that mean the fix is at Paste — the prompt itself, or nothing, was pasted — rather
    /// than at Chat.
    static let pasteCodes: Set<String> = ["E_PROMPT_PASTED", "E_EMPTY"]

    /// The plan on the page when the screen opened: what the prompt carries and the reply is
    /// compared with.
    let plan: Plan
    var wording: Wording = .plain
    private(set) var request = ""
    private(set) var stage: TripStage = .ask
    /// The reply, read as a plan, while the screen is on Review.
    private(set) var reply: Plan?
    private(set) var diff: PlanDiff?
    /// The errors that refused the reply; empty unless the screen is on Refused.
    private(set) var refusal: [Issue] = []

    init(plan: Plan, wording: Wording = .plain) {
        self.plan = plan
        self.wording = wording
    }

    // MARK: - What the screen shows

    /// Send is disabled until something is typed — but for the fix-it prompt of a refused reply,
    /// which asks for the whole plan whatever the request was.
    var canSend: Bool { (stage == .refused && fixAt == 1) || !request.trimmed.isEmpty }

    /// A review whose reply is the plan as it was.
    var isNothingChanged: Bool { stage == .review && diff?.count == 0 }

    /// Where the fix is: 1, Chat — ask again; 2, Paste — what was pasted was the prompt or nothing.
    var fixAt: Int {
        if stage == .refused, refusal.contains(where: { Self.pasteCodes.contains($0.code) }) { return 2 }
        return 1
    }

    /// *Nothing changed* lights Chat, as a refusal there would.
    var strip: TripStrip { isNothingChanged ? .of(.refused, fixAt: 1) : .of(stage, fixAt: fixAt) }

    /// The bottom slot; nil for *Nothing changed*, which has no button.
    var buttons: TripButtons? {
        switch stage {
        case .ask: return .ask()
        case .paste: return .paste
        case .review:
            guard let diff, diff.count > 0 else { return nil }
            return .effect(Self.apply(count: diff.count))
        case .refused: return fixAt == 2 ? .ask() : Self.askAgain
        }
    }

    /// The review's title: *2 changes*, *1 change*, *Nothing changed*.
    var title: String? { diff.map { Self.title(count: $0.count) } }

    /// The navigation title: the review's, or the door's words before there is one.
    var heading: String { title ?? Self.menuItem }

    /// The sentence under the strip: the refusal's, or *Nothing changed*'s.
    var sentence: String? {
        if isNothingChanged { return Self.nothingChanged }
        guard stage == .refused, let first = refusal.first(where: { $0.severity == .error }) ?? refusal.first else { return nil }
        return IssueText.friendly(first)
    }

    /// The text the bottom slot sends: the fix-it prompt for a refused reply, the change prompt
    /// otherwise.
    func prompt(settings: Settings) -> String {
        if stage == .refused, fixAt == 1 { return Prompts.render(errors: refusal) }
        return Prompts.change(plan: plan, request: request, settings: settings)
    }

    /// The share sheet's subject.
    var subject: String { "Change \(plan.name)" }

    static func title(count: Int) -> String {
        count == 0 ? "Nothing changed" : count == 1 ? "1 change" : "\(count) changes"
    }

    static func apply(count: Int) -> String {
        count == 1 ? "Apply 1 change" : "Apply \(count) changes"
    }

    // MARK: - Transitions

    /// The field. A different request is a different prompt, so the screen returns to Ask.
    mutating func say(_ text: String) {
        guard text != request else { return }
        request = text
        stage = .ask
        reply = nil
        diff = nil
        refusal = []
    }

    /// The ···'s **Send the prompt again**: back to Ask, the request kept, so Send is one tap.
    mutating func restart() {
        stage = .ask
        reply = nil
        diff = nil
        refusal = []
    }

    /// Send or Copy went (D88): the screen waits for the reply.
    mutating func sent() {
        guard canSend else { return }
        stage = .paste
    }

    /// The reply, through the import pipeline: a plan is reviewed as what changed, anything else is
    /// refused.
    mutating func pasted(result: ImportResult) {
        guard var replied = result.plan else {
            stage = .refused
            reply = nil
            diff = nil
            refusal = result.errors.isEmpty ? result.issues : result.errors
            return
        }
        // A reply that dropped `units` took the setting's; the plan it was asked to change says
        // which unit its numbers are in.
        if !result.unitsStated { replied.units = plan.units }
        stage = .review
        reply = replied
        diff = PlanDiff.between(old: plan, new: replied, wording: wording)
        refusal = []
    }

    // MARK: - The text behind the ···

    /// D95 (§6.68): **Edit the text** opens the sheet on the whole plan — the reply when there is
    /// one, else the plan as it stands — and its Save reviews what changed, as a paste would.
    ///
    /// The kind is `.plan`, whose marks read a whole plan's paths — `days[1].exercises[0]`, and
    /// the plan's own fields — at their own lines (N6).
    func textPoint() -> JSONPoint {
        JSONPoint(kind: .plan,
                  title: "The plan",
                  place: "\(plan.name), changed. Nothing is saved until you apply it.",
                  template: reply?.sourceText ?? PlanJSON.render(plan),
                  saveTitle: "See what changed",
                  footer: "The whole plan, as the chatbot writes it back.")
    }
}
