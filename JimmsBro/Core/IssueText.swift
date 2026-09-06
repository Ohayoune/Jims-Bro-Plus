import Foundation

/// SPEC §4.4 (D26, v1.1): an import problem said in a sentence, before any path or code.
/// The importer's own `message` is precise and machine-shaped ("expected int, got string");
/// this is the same fact addressed to the person holding the phone. The path and the code are
/// still shown, behind Details, because the fix-it prompt and the docs are written in them.
enum IssueText {
    /// "Day 1, exercise 2, set 3" — nil when the path is plan-wide or absent.
    static func location(_ path: String) -> String? {
        var parts: [String] = []
        for component in path.split(separator: ".") {
            let name = component.prefix { $0 != "[" }
            guard let index = indexIn(component) else { continue }
            switch name {
            case "days": parts.append("Day \(index + 1)")
            case "exercises": parts.append("exercise \(index + 1)")
            case "sets": parts.append("set \(index + 1)")
            case "drops": parts.append("drop \(index + 1)")
            case "cycle": parts.append("repeat block entry \(index + 1)")
            default: continue
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// One plain sentence per error code in PLAN_FORMAT §4, with a generic fallback so a code
    /// added later degrades to the importer's own wording rather than to nothing (M8).
    static func friendly(_ issue: Issue) -> String {
        let here = location(issue.path)
        // "Day 1, exercise 2" as a subject, or "That set" when the path says nothing.
        func subject(_ fallback: String) -> String { here ?? fallback }
        func prefixed(_ sentence: String) -> String {
            guard let here else { return sentence.prefix(1).uppercased() + sentence.dropFirst() }
            return "\(here): \(sentence)"
        }

        switch issue.code {
        case "E_EMPTY":
            return "There was nothing to import. Paste the reply your chatbot gave you."
        case "E_TOO_LARGE":
            return "That's too big to be a plan. Paste just the plan itself, not the whole conversation."
        case "E_PROMPT_PASTED":
            return "That's the prompt, not a plan. Paste it into your chatbot first, then bring its reply back here."
        case "E_MULTIPLE_OBJECTS":
            return "There's more than one plan in there. Paste one at a time."
        case "E_NOT_JSON":
            return "The plan isn't complete — the chatbot's reply looks cut off. Ask it to send the whole plan again."
        case "E_NOT_A_PLAN":
            return "That's valid JSON, but it isn't a workout plan."
        case "E_SCHEMA_VERSION":
            return "This plan was written for a newer version of the app than this one."
        case "E_UNITS_INVALID":
            return "The units must be either kg or lb."
        case "E_SCHEDULE_MIXED":
            return "Some days name a weekday and some don't. Give every day a weekday, or none of them."
        case "E_NO_DAYS":
            return "The plan has no days in it."
        case "E_NO_EXERCISES":
            return "\(subject("One of the days")) has no exercises."
        case "E_MISSING_NAME":
            return "\(subject("An exercise")) needs a name."
        case "E_SETS_INVALID":
            return "\(subject("An exercise")) needs a whole number of sets, at least one."
        case "E_REPS_INVALID":
            return prefixed("the reps need to be a number, a range like 8-12, or AMRAP.")
        case "E_REPRANGE_INVALID":
            return prefixed("the rep range should look like 8-12.")
        case "E_DROPS_INVALID":
            return prefixed("the drop sets aren't in a form the app understands.")
        case "E_CYCLE_INVALID":
            return "The repeat block needs to be a list of day names, and \"rest\", between 1 and 31 long."
        case "E_CYCLE_UNKNOWN_DAY":
            return "\(subject("The repeat block")) names a day this plan doesn't have."
        case "E_DURATION_INVALID":
            return prefixed("the duration needs to be a number of seconds from 1 to 86400, or \"max\".")
        case "E_WARNING_BEEP_INVALID":
            return prefixed("the warning beep needs to be true, false, or a number of seconds.")
        case "E_BODYWEIGHT_INVALID":
            return prefixed("bodyweight needs to be true or false.")
        case "E_TARGET_MISSING":
            return "\(subject("A set")) needs either a rep target or a duration."
        case "E_TARGET_CONFLICT":
            return "\(subject("A set")) has both reps and a duration. It can only have one."
        case "E_WEIGHT_INVALID":
            return prefixed("the weight isn't a number.")
        case "E_REST_INVALID":
            return prefixed("rest needs to be a whole number of seconds, from 0 to 3600.")
        case "E_WEEKDAY_INVALID":
            return prefixed("that isn't a weekday the app recognizes.")
        case "E_WEEKDAY_DUPLICATE":
            return "\(subject("Two days")) is set to a weekday another day already uses."
        case "E_WEEKDAY_MISSING":
            return "\(subject("A day")) needs a weekday, because this plan is anchored to weekdays."
        case "E_LIMIT_EXCEEDED":
            return "That's more than the app can hold: at most 31 days, 50 exercises in a day, and 50 sets in an exercise."
        default:
            // An unrecognized code still says something true (M8).
            return here.map { "\($0): \(issue.message)" } ?? issue.message
        }
    }

    /// Every error code this knows a sentence for, so a test can prove none was forgotten.
    static let knownErrorCodes = [
        "E_EMPTY", "E_TOO_LARGE", "E_PROMPT_PASTED", "E_MULTIPLE_OBJECTS", "E_NOT_JSON",
        "E_NOT_A_PLAN", "E_SCHEMA_VERSION", "E_UNITS_INVALID", "E_SCHEDULE_MIXED", "E_NO_DAYS",
        "E_NO_EXERCISES", "E_MISSING_NAME", "E_SETS_INVALID", "E_REPS_INVALID",
        "E_REPRANGE_INVALID", "E_DROPS_INVALID", "E_CYCLE_INVALID", "E_CYCLE_UNKNOWN_DAY",
        "E_DURATION_INVALID", "E_WARNING_BEEP_INVALID", "E_BODYWEIGHT_INVALID",
        "E_TARGET_MISSING", "E_TARGET_CONFLICT", "E_WEIGHT_INVALID", "E_REST_INVALID",
        "E_WEEKDAY_INVALID", "E_WEEKDAY_DUPLICATE", "E_WEEKDAY_MISSING", "E_LIMIT_EXCEEDED",
    ]

    /// SPEC §4.4 (v1.1): a **material** warning changed the workout you will actually do — a
    /// stated unit dropped, a load removed, a grouping or a schedule reinterpreted. A **cleanup**
    /// warning only tidied the text: curly quotes, an unknown field, a rounded weight. Material
    /// warnings are shown; cleanup warnings go behind "Details (n)", so the ones worth reading
    /// aren't buried under the ones that aren't.
    static let cleanupWarningCodes: Set<String> = [
        "W_CURLY_QUOTES_FIXED", "W_SURROUNDING_TEXT", "W_UNKNOWN_FIELD", "W_NAME_TRUNCATED",
        "W_NOTES_TRUNCATED", "W_WEIGHT_ROUNDED", "W_DEFAULT_NAME", "W_DAY_RENAMED",
        "W_WRAPPED_SINGLE_DAY",
    ]

    static func isMaterial(_ issue: Issue) -> Bool { !cleanupWarningCodes.contains(issue.code) }

    /// Warnings split into the two lists the review screen shows.
    static func split(_ warnings: [Issue]) -> (material: [Issue], cleanup: [Issue]) {
        (warnings.filter(isMaterial), warnings.filter { !isMaterial($0) })
    }

    private static func indexIn(_ component: Substring) -> Int? {
        guard let open = component.firstIndex(of: "["),
              let close = component.firstIndex(of: "]"),
              open < close else { return nil }
        return Int(component[component.index(after: open)..<close])
    }
}
