import Foundation

/// SPEC §6.60 (D87, D96 v1.12): a reply the pipeline refused, as every trip screen draws it —
/// Add plan, a draft's outline and days, Progression and Say what should change. The screens
/// differ only in the way back they have (`WayBack`); everything else — where the fix is, what
/// the buttons send, whether day by day is offered, the sentence — is decided here, once.
///
/// It is not in `Trip.swift` because that file is compiled into the widget extension, which has
/// no `Issue`.
struct TripRefusal: Equatable {
    /// What the buttons send back.
    enum Sends: Equatable {
        /// The screen's own prompt, again: the plan prompt, the outline's or a day's, the
        /// progression's, the change prompt.
        case prompt
        /// The fix-it prompt, PROMPT.md §2 (`Prompts.render(errors:)`) — **Ask for the whole plan**.
        case wholePlan
    }

    /// The way back a screen has for a reply the chatbot must write again.
    enum WayBack: Equatable {
        /// Progression (§6.65) and a draft's outline and days (§6.64): the screen's own prompt,
        /// since neither has a fix-it prompt of its own.
        case prompt
        /// Say what should change (§6.67): **Ask for the whole plan**, for anything that is not a
        /// plan or came cut short.
        case wholePlan
        /// Add plan (§6.60, §6.64): **Ask for the whole plan**, with **Get it day by day** beneath
        /// it for a reply cut short — and the plan prompt for a plan written in words, which is the
        /// owner's own and has not met the prompt yet; its sentence says exactly that (D55).
        case wholePlanOrDayByDay
    }

    static let askForWholePlan = "Ask for the whole plan"
    static let dayByDay = "Get it day by day"

    /// The errors, for Details and for the fix-it prompt.
    var errors: [Issue]
    var fix: TripFix
    var sends: Sends
    /// D91 (§6.64): the reply came cut short, so **Get it day by day** is offered beneath Ask for
    /// the whole plan. No other refusal offers it.
    var offersDayByDay: Bool

    /// The friendly sentences, one per error (D26).
    var sentences: [String] { errors.map(IssueText.friendly) }
    /// The first of them, in the red band; the rest are behind Details.
    var sentence: String? { sentences.first }

    /// The refusal `issues` make, on a screen whose way back is `way`. The prompt pasted, or
    /// nothing, is fixed at Paste by sending the prompt again (§6.60); anything else at Chat. A
    /// refusal that names no error has nothing for a fix-it prompt to list, so the prompt goes
    /// again — at Chat, since SPEC names Paste only for the prompt pasted or nothing (L5).
    static func of(_ issues: [Issue], way: WayBack) -> TripRefusal {
        let errors = issues.filter { $0.severity == .error }
        let codes = Set(errors.map(\.code))
        if codes.contains("E_PROMPT_PASTED") || codes.contains("E_EMPTY") {
            return TripRefusal(errors: errors, fix: .paste, sends: .prompt, offersDayByDay: false)
        }
        let whole = way != .prompt && !errors.isEmpty
            && !(way == .wholePlanOrDayByDay && errors.contains(where: \.isPlanInWords))
        return TripRefusal(errors: errors, fix: .chat, sends: whole ? .wholePlan : .prompt,
                           offersDayByDay: whole && way == .wholePlanOrDayByDay && errors.contains(where: \.isCutShort))
    }

    /// The share-and-copy pair `PromptButtons` draws: the screen's own prompt by `name` — *the
    /// outline prompt*, *the prompt for Pull* — or **Ask for the whole plan** with **Copy the
    /// prompt** beneath (§6.60). Day by day, when offered, is a third button of its own.
    func buttons(prompt name: String = "the prompt") -> TripButtons {
        switch sends {
        case .prompt: return .ask(name)
        case .wholePlan: return TripButtons(primary: Self.askForWholePlan, secondary: TripButtons.ask().secondary)
        }
    }

    /// The text the buttons send: the fix-it prompt, or the screen's own.
    func prompt(or own: @autoclosure () -> String) -> String {
        sends == .wholePlan ? Prompts.render(errors: errors) : own()
    }
}
