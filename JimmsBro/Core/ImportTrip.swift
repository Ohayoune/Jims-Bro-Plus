import Foundation

/// SPEC §4.4 (D87, D88, D90, v1.11): **Add plan** as data. One screen in three states — Ask,
/// Paste, Review — and a fourth for a refusal; the view holds an `ImportTrip`, draws what it
/// says and calls its transitions, and never composes a title of its own.
///
/// The pipeline under it does not change: a paste is `PlanImport.run`'s result handed to
/// `pasted(result:text:)`, a built-in plan is `AppModel.loadBuiltInPlan`'s handed to `builtIn`.
struct ImportTrip: Equatable {
    private(set) var stage: TripStage = .ask
    /// The plan on the review.
    private(set) var review: Plan?
    /// D46: a built-in plan's paragraph, above the days; nil for a paste.
    private(set) var about: String?
    /// D90: the review is a built-in plan's, which is saved beside a copy of itself rather than
    /// asking about the name (§6.8, as the picker did).
    private(set) var fromBuiltIn = false
    /// D57: whether the reviewed plan named its unit. When it did not, the review asks.
    private(set) var unitsStated = true
    private(set) var refusal: TripRefusal?
    /// The text of the last paste, which Edit the text opens on after a refusal.
    private(set) var pastedText: String?

    // MARK: - What the screen draws

    var strip: TripStrip { TripStrip.of(stage, fix: refusal?.fix ?? .chat) }

    /// The bottom slot's words: Send the prompt / Copy the prompt on Ask, Paste, **Use Push Pull
    /// Legs** on the review, and on a refusal what sends the trouble back (`TripRefusal`) — with
    /// **Get it day by day** as a button of its own beneath, when the refusal offers it.
    var buttons: TripButtons {
        switch stage {
        case .ask: return .ask()
        case .paste: return .paste
        case .review: return .effect(review.map(PlanText.useTitle) ?? "Use this plan")
        case .refused: return refusal?.buttons() ?? .ask()
        }
    }

    /// What Send and Copy send: the plan prompt (PROMPT.md §1), or a refusal's fix-it prompt.
    func prompt(settings: Settings) -> String {
        refusal?.prompt(or: Prompts.render(settings: settings)) ?? Prompts.render(settings: settings)
    }

    /// The share sheet's subject.
    var subject: String { "A workout plan" }

    /// D57: the review asks kg / lb only when the plan named no unit.
    var asksUnits: Bool { stage == .review && !unitsStated }

    /// The ··· for this stage (§4.4, §6.68).
    var menu: [TripMenuItem] {
        switch stage {
        case .ask, .refused: return [.openFile, .editText]
        case .paste: return [.sendAgain, .openFile, .editText]
        case .review: return [.keepWithoutUsing, .editText]
        }
    }

    // MARK: - Transitions

    /// Send the prompt or Copy the prompt: the screen moves to Paste (D88) — from Ask, or from a
    /// refusal whose trouble went back to the chatbot.
    mutating func sent() {
        stage = .paste
        refusal = nil
        review = nil
        about = nil
        fromBuiltIn = false
    }

    /// A paste ran the pipeline: the review, or the refusal.
    mutating func pasted(result: ImportResult, text: String? = nil) {
        pastedText = text
        about = nil
        fromBuiltIn = false
        if let plan = result.plan, result.errors.isEmpty {
            stage = .review
            review = plan
            unitsStated = result.unitsStated
            refusal = nil
        } else {
            stage = .refused
            review = nil
            refusal = TripRefusal.of(result.errors, way: .wholePlanOrDayByDay)
        }
    }

    /// D90: a tile of the built-ins row. A built-in plan names no unit, so the review asks.
    mutating func builtIn(_ plan: Plan, about: String?) {
        stage = .review
        review = plan
        self.about = about
        fromBuiltIn = true
        unitsStated = false
        refusal = nil
    }

    /// Back from the review or a refusal to Ask, where the built-ins row is.
    mutating func restart() {
        stage = .ask
        review = nil
        about = nil
        fromBuiltIn = false
        refusal = nil
    }

    /// The plan Use (or Keep without using) saves: the unit the review asked for written into it
    /// and its text when the plan named none (D57), otherwise the plan as reviewed.
    func planToSave(units: WeightUnit) -> Plan? {
        guard var plan = review else { return nil }
        if !unitsStated {
            plan.units = units
            plan.sourceText = PlanJSON.render(plan)
        }
        return plan
    }

    // MARK: - The text behind the ··· (D95)

    /// Add plan's **Edit the text**: the plan on the review, the paste a refusal refused — unless
    /// what was pasted was the prompt, or nothing — or else the smallest plan the importer takes.
    /// Its save is an ordinary paste.
    var textPoint: JSONPoint {
        let template: String
        if let review {
            template = review.sourceText.trimmed.isEmpty ? PlanJSON.render(review) : review.sourceText
        } else if let pastedText, refusal?.fix == .chat, !pastedText.trimmed.isEmpty {
            template = pastedText
        } else {
            template = JSONPoint.examplePlan
        }
        return JSONPoint.newPlan(template: template)
    }

    // MARK: - The review's squares

    /// The cycle as the plan's page draws it (§6.51, D86, `CycleSquare.of`), without Next up or
    /// today — a plan on review has no place in time yet — and with a draft's unfilled days
    /// hollow (D91).
    static func squares(_ plan: Plan, hollow: Set<Int> = []) -> [CycleSquare] {
        CycleSquare.of(plan).map { square in
            var square = square
            square.hollow = square.dayIndex.map(hollow.contains) ?? false
            return square
        }
    }
}
