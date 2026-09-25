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

    /// The plan on the page when the screen opened: what the prompt carries and the reply is
    /// compared with.
    let plan: Plan
    var wording: Wording = .plain
    private(set) var request = ""
    private(set) var stage: TripStage = .ask
    /// The reply, read as a plan, while the screen is on Review.
    private(set) var reply: Plan?
    private(set) var diff: PlanDiff?
    /// What refused the reply, while the screen is on Refused. Its way back is **Ask for the
    /// whole plan** (§6.67), as on Add plan.
    private(set) var refusal: TripRefusal?

    init(plan: Plan, wording: Wording = .plain) {
        self.plan = plan
        self.wording = wording
    }

    // MARK: - What the screen shows

    /// Send is disabled until something is typed — but for the fix-it prompt of a refused reply,
    /// which asks for the whole plan whatever the request was.
    var canSend: Bool { refusal?.sends == .wholePlan || !request.trimmed.isEmpty }

    /// A review whose reply is the plan as it was.
    var isNothingChanged: Bool { stage == .review && diff?.count == 0 }

    /// *Nothing changed* lights Chat, as a refusal there would.
    var strip: TripStrip { isNothingChanged ? .of(.refused, fix: .chat) : .of(stage, fix: refusal?.fix ?? .chat) }

    /// The bottom slot; nil for *Nothing changed*, which has no button.
    var buttons: TripButtons? {
        switch stage {
        case .ask: return .ask()
        case .paste: return .paste
        case .review:
            guard let diff, diff.count > 0 else { return nil }
            return .effect(Self.apply(count: diff.count))
        case .refused: return refusal?.buttons() ?? .ask()
        }
    }

    /// The review's title: *2 changes*, *1 change*, *Nothing changed*.
    var title: String? { diff.map { Self.title(count: $0.count) } }

    /// The navigation title: the review's, or the door's words before there is one.
    var heading: String { title ?? Self.menuItem }

    /// The sentence under the strip: the refusal's, or *Nothing changed*'s.
    var sentence: String? { isNothingChanged ? Self.nothingChanged : refusal?.sentence }

    /// The text the bottom slot sends: the fix-it prompt for a refused reply, the change prompt
    /// otherwise.
    func prompt(settings: Settings) -> String {
        let change = Prompts.change(plan: plan, request: request, settings: settings)
        return refusal?.prompt(or: change) ?? change
    }

    /// The ··· (D95): **Send the prompt again** once the prompt has gone, and **Edit the text** last.
    var menu: [TripMenuItem] { stage == .ask ? [.editText] : [.sendAgain, .editText] }

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
        refusal = nil
    }

    /// The ···'s **Send the prompt again**: back to Ask, the request kept, so Send is one tap.
    mutating func restart() {
        stage = .ask
        reply = nil
        diff = nil
        refusal = nil
    }

    /// Send or Copy went (D88): the screen waits for the reply.
    mutating func sent() {
        guard canSend else { return }
        stage = .paste
    }

    /// The reply, through the import pipeline: a plan is reviewed as what changed, anything else is
    /// refused.
    mutating func pasted(result: ImportResult) {
        guard let replied = result.planKeepingUnits(of: plan) else {
            stage = .refused
            reply = nil
            diff = nil
            refusal = TripRefusal.of(result.issues, way: .wholePlan)
            return
        }
        stage = .review
        reply = replied
        diff = PlanDiff.between(old: plan, new: replied, wording: wording)
        refusal = nil
    }

    // MARK: - The text behind the ···

    /// D95 (§6.68): **Edit the text** opens the sheet on the whole plan — the reply when there is
    /// one, else the plan as it stands — and its Save reviews what changed, as a paste would.
    func textPoint() -> JSONPoint {
        JSONPoint.changing(plan.name, text: reply?.sourceText ?? PlanJSON.render(plan))
    }
}
