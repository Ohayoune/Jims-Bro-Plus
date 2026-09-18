import Foundation

/// SPEC §4.4 (D87, D88, D90, v1.11): **Add plan** as data. One screen in three states — Ask,
/// Paste, Review — and a fourth for a refusal; the view holds an `ImportTrip`, draws what it
/// says and calls its transitions, and never composes a title of its own.
///
/// The pipeline under it does not change: a paste is `PlanImport.run`'s result handed to
/// `pasted(result:text:)`, a built-in plan is `AppModel.loadBuiltInPlan`'s handed to `builtIn`.
struct ImportTrip: Equatable {
    /// What the Refused state (or Ask) sends through the share sheet.
    enum Outgoing: Equatable {
        /// The plan prompt, PROMPT.md §1.
        case prompt
        /// The fix-it prompt, PROMPT.md §2 — **Ask for the whole plan**.
        case wholePlan
    }

    /// A reply the pipeline refused, as the Refused state draws it (§6.60).
    struct Refusal: Equatable {
        /// The errors, for Details and for the fix-it prompt.
        var errors: [Issue]
        /// Where the fix is on the strip: 1, Chat — the reply must be asked for again; 2, Paste —
        /// what was pasted was the prompt itself, or nothing.
        var fixAt: Int
        /// What the buttons send back.
        var sends: Outgoing
        /// D91 (§6.64): the reply came cut short, so **Get it day by day** is offered beneath
        /// Ask for the whole plan. No other refusal offers it.
        var offersDayByDay: Bool

        /// The friendly sentences, one per error (D26).
        var sentences: [String] { errors.map(IssueText.friendly) }

        /// The refusal an import's errors make. The prompt pasted, or nothing, is fixed at Paste
        /// by sending the prompt again; a plan written in words has not met the prompt yet, so it
        /// is sent the prompt too, at Chat — its sentence says exactly that (D55); a reply that
        /// looks cut off is asked for whole, or day by day; anything else is asked for whole.
        static func of(_ errors: [Issue]) -> Refusal {
            let codes = Set(errors.map(\.code))
            if errors.isEmpty || codes.contains("E_PROMPT_PASTED") || codes.contains("E_EMPTY") {
                return Refusal(errors: errors, fixAt: 2, sends: .prompt, offersDayByDay: false)
            }
            if errors.contains(where: \.isPlanInWords) {
                return Refusal(errors: errors, fixAt: 1, sends: .prompt, offersDayByDay: false)
            }
            return Refusal(errors: errors, fixAt: 1, sends: .wholePlan, offersDayByDay: errors.contains(where: \.isCutShort))
        }
    }

    /// D95 (§6.68): the ···'s items, in order. **Edit the text** is always last.
    enum MenuItem: Equatable {
        case sendAgain, openFile, keepWithoutUsing, discardDraft, editText

        var title: String {
            switch self {
            case .sendAgain: return TripText.sendAgain
            case .openFile: return "Open a file"
            case .keepWithoutUsing: return "Keep without using"
            case .discardDraft: return "Discard the draft"
            case .editText: return TripText.editText
            }
        }
    }

    static let askForWholePlan = "Ask for the whole plan"
    static let dayByDay = "Get it day by day"

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
    private(set) var refusal: Refusal?
    /// The text of the last paste, which Edit the text opens on after a refusal.
    private(set) var pastedText: String?

    // MARK: - What the screen draws

    var strip: TripStrip { TripStrip.of(stage, fixAt: refusal?.fixAt ?? 1) }

    /// The bottom slot's words: Send the prompt / Copy the prompt on Ask, Paste, **Use Push Pull
    /// Legs** on the review, and on a refusal what sends the trouble back — with **Get it day by
    /// day** as the second button for a reply cut short.
    var buttons: TripButtons {
        switch stage {
        case .ask: return .ask()
        case .paste: return .paste
        case .review: return .effect(review.map(PlanText.useTitle) ?? "Use this plan")
        case .refused:
            guard let refusal, refusal.sends == .wholePlan else { return .ask() }
            return TripButtons(primary: Self.askForWholePlan, secondary: refusal.offersDayByDay ? Self.dayByDay : nil)
        }
    }

    /// What goes out through the share sheet, when this stage sends something.
    var outgoing: Outgoing? {
        switch stage {
        case .ask: return .prompt
        case .refused: return refusal?.sends ?? .prompt
        case .paste, .review: return nil
        }
    }

    /// The share-and-copy pair `PromptButtons` draws for `outgoing`: the prompt's own words, or
    /// **Ask for the whole plan** with **Copy the prompt** beneath (§6.60).
    var sendButtons: TripButtons? {
        switch outgoing {
        case .prompt: return .ask()
        case .wholePlan: return TripButtons(primary: Self.askForWholePlan, secondary: TripButtons.ask().secondary)
        case nil: return nil
        }
    }

    /// D57: the review asks kg / lb only when the plan named no unit.
    var asksUnits: Bool { stage == .review && !unitsStated }

    /// The ··· for this stage (§4.4, §6.68).
    var menu: [MenuItem] {
        switch stage {
        case .ask, .refused: return [.openFile, .editText]
        case .paste: return [.sendAgain, .openFile, .editText]
        case .review: return [.keepWithoutUsing, .editText]
        }
    }

    // MARK: - Transitions

    /// Send the prompt or Copy the prompt: the screen moves to Paste (D88) — from Ask, from a
    /// refusal, or from Paste itself (the ···'s Send the prompt again).
    mutating func sent() {
        stage = .paste
        refusal = nil
        review = nil
        about = nil
        fromBuiltIn = false
    }

    /// Ask for the whole plan, or Send the prompt again from a refusal: the trouble went back to
    /// the chatbot, so the screen waits for its reply.
    mutating func fix() { sent() }

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
            refusal = Refusal.of(result.errors)
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
    /// Its save is an ordinary paste; the kind is `.plan`, whose marks read a whole plan's own
    /// paths at their lines (N6 gave `JSONPoint` that kind).
    var textPoint: JSONPoint {
        let template: String
        if let review {
            template = review.sourceText.trimmed.isEmpty ? PlanJSON.render(review) : review.sourceText
        } else if let pastedText, refusal?.fixAt == 1, !pastedText.trimmed.isEmpty {
            template = pastedText
        } else {
            template = Self.examplePlan
        }
        return Self.planPoint(template: template, place: "A new plan. You see it before anything is saved.",
                              saveTitle: "Review the plan")
    }

    /// Plan detail's **Edit the text** (D95): the plan's own text, saved in place.
    static func replacing(_ name: String, text: String) -> JSONPoint {
        planPoint(template: text, place: "All of \(name). Its history and its place in the cycle stay.",
                  saveTitle: "Replace \(name)")
    }

    private static func planPoint(template: String, place: String, saveTitle: String) -> JSONPoint {
        JSONPoint(kind: .plan, title: "The plan", place: place, template: template,
                  saveTitle: saveTitle, footer: "A whole plan, in the fields the prompt asks a chatbot for.")
    }

    /// The smallest plan the importer takes as it stands: one day of D77's example exercise, and
    /// no unit, so its review asks.
    static var examplePlan: String {
        let day = JSONPoint.exampleDay(name: "Day 1").trimmed.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
        return "{\n  \"name\": \"My plan\",\n  \"days\": [\n" + day + "\n  ]\n}\n"
    }

    // MARK: - The review's squares

    /// A square of the review's cycle: the day's colour, grey for rest, the name beneath, a
    /// weekday plan's weekday above — and hollow for a day a draft has not filled (D91).
    struct Square: Equatable {
        var colour: DayColour?
        var name: String
        var weekday: String?
        var dayIndex: Int?
        var hollow: Bool
    }

    /// The cycle as the plan's page draws it (§6.51, D86), without Next up or today — a plan on
    /// review has no place in time yet — and with a draft's unfilled days hollow.
    static func squares(_ plan: Plan, hollow: Set<Int> = []) -> [Square] {
        let colours = DayColour.cycle(of: plan)
        func square(_ offset: Int, _ index: Int?, weekday: String?) -> Square {
            Square(colour: colours[safe: offset] ?? nil, name: index.map { plan.days[$0].name } ?? "Rest",
                   weekday: weekday, dayIndex: index, hollow: index.map(hollow.contains) ?? false)
        }
        switch plan.schedule {
        case .rotation:
            return plan.cycle.enumerated().map { offset, entry in
                guard case let .day(day) = entry, plan.days.indices.contains(day) else {
                    return square(offset, nil, weekday: nil)
                }
                return square(offset, day, weekday: nil)
            }
        case .weekday:
            return Weekday.allCases.enumerated().map { offset, weekday in
                square(offset, plan.days.firstIndex { $0.weekday == weekday }, weekday: WeekdayText.short(weekday))
            }
        }
    }
}
