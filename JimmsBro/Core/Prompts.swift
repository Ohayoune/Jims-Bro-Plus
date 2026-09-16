import Foundation

/// D50 (v1.5): the two sentences that explain the chatbot round-trip where its buttons are,
/// and the line under the Progression row. Core strings, so the views that show them are
/// pinned to them (Z1) and a rewording is one edit. (Until v1.9 the name of Today's Plan a
/// progression too; D75 took the link off Today, and its name went with it.)
enum PromptText {
    /// Step 1 of Add plan and of Progression, beside the accent Copy prompt button.
    static let copyStep = "Copy the prompt. It tells the chatbot the exact format the app "
        + "reads, so its reply pastes straight back in."
    /// The chatbot section's footer, in both places.
    static let mechanism = "The app never talks to the chatbot itself; you carry the text "
        + "both ways."
    /// The second line under the Progression row — History's since D67 (v1.7).
    static let progressionRow = "A chatbot plans your next steps from what you have lifted."
}

enum Prompts {
    static let marker = PlanImport.promptMarker
    /// The prompt's two halves, with `exampleTemplate` between them. One copy of the example
    /// JSON: it used to be written out verbatim twice — here and in `exampleTemplate` — with
    /// nothing to notice when they drifted apart. `M9` pins the whole thing to docs/PROMPT.md.
    static let planHeader = #"""
JIMMSBRO-PLAN-PROMPT-V1
Convert my workout plan to JSON for a workout-tracking app. Reply with ONE complete JSON object in a single code block tagged json, with no other text.

FORMAT (schemaVersion 1):
"""#
    static let planRules = #"""
RULES
- days: training days in order; one workout = one day. Do not list rest days as days.
- schedule: rotation = repeat days in order. Use weekday only for a fixed weekly schedule; give every day a weekday (monday…sunday) and omit cycle.
- cycle: rotation's full repeating block, using day names and "rest", including rest days. Example: ["Push","Pull","Legs","Push","Pull","Legs","rest"]. This drives the calendar.
- sets: a count for identical sets; otherwise an array of set objects. Exercise-level fields default each set. Prefer the count form.
- Each set needs exactly one of reps or durationSeconds. Duration is seconds for holds/cardio; "max" = stopwatch until stopped, "30+" = at least 30 seconds.
- Fixed durations beep at the end. warningBeep: true or omitted = warning at 10% remaining, false = off, or a number of seconds before the end (e.g. 5). Fixed durations only.
- bodyweight: true when no weight applies (push-ups, planks, hangs); omit weight. For weighted calisthenics use added load as weight and omit the flag.
- reps: whole number, "8-12", "AMRAP" (as many as possible), or "10+" (at least 10). Nothing else.
- repRange: give every rep exercise a working range for weight progression, e.g. "8-12". Omit if reps already is a range. For fixed targets choose a range containing it (10 → "8-12", 5 → "4-6"). No repRange for timed exercises.
- weight: number in {{units}}, without unit text. Omit for bodyweight or unspecified weight.
- restSeconds: always include whole seconds. If unspecified: 120-180 for heavy compounds, 60-90 for isolation, 30-60 for circuits/core.
- restBetweenExercises: whole seconds to walk between exercises; if unspecified, 120.
- drops: list on exercise or individual set, e.g. [{"weight":20},{"weight":15}], done immediately after the main set with no rest. Reps default to AMRAP.
- Supersets/circuits: same group letter, consecutive exercises, equal set counts. Rest after each round.
- Names: specific and consistent ("Barbell Back Squat", not "Squats"); reuse spelling across days for history matching.
- Keep execution order. If I supply exercises, use exactly those: no additions, removals, or reordering. If I request a plan, design a sensible one.
- inReserve: how many reps (or seconds, for holds) short of failure each set should stop, e.g. 2. Omit when I do not say.
- Put tempo, cues and "each side" in notes.
- Return ALL JSON, never abbreviate with "...".

My plan:
"""#
    static var planTemplate: String {
        // A blank line between the example and the rules, exactly as docs/PROMPT.md §1 has it.
        planHeader + "\n" + exampleTemplate + "\n\n" + planRules + "\n"
    }
    static let fixTemplate = #"""
JIMMSBRO-PLAN-PROMPT-V1
The workout app rejected the JSON with these errors:
{{errorLines}}

Fix them and reply with the complete corrected JSON only, in one code block tagged json, keeping the same format and rules as before. Do not change anything else.
"""#
    static let exampleTemplate = #"""
{
  "schemaVersion": 1,
  "name": "Push Pull Legs",
  "units": "{{units}}",
  "defaultRestSeconds": {{defaultRest}},
  "restBetweenExercises": 120,
  "schedule": "rotation",
  "cycle": ["Push", "rest"],
  "days": [
    {
      "name": "Push",
      "exercises": [
        { "name": "Barbell Bench Press", "sets": 4, "reps": "6-8", "weight": 80, "restSeconds": 150, "notes": "Pause on chest" },
        { "name": "Incline Dumbbell Press", "sets": [ { "reps": 12, "weight": 24 }, { "reps": 10, "weight": 26 }, { "reps": 8, "weight": 28 } ], "repRange": "8-12", "restSeconds": 90 },
        { "name": "Lateral Raise", "group": "A", "sets": 3, "reps": 15, "repRange": "12-15", "weight": 10, "restSeconds": 60 },
        { "name": "Tricep Pushdown", "group": "A", "sets": 3, "reps": 12, "repRange": "10-12", "weight": 25, "restSeconds": 60, "drops": [ { "weight": 20 }, { "weight": 15 } ] },
        { "name": "Plank", "sets": 3, "durationSeconds": 45, "warningBeep": true, "bodyweight": true, "restSeconds": 45 },
        { "name": "Dead Hang", "sets": 2, "durationSeconds": "max", "bodyweight": true, "restSeconds": 60 }
      ]
    }
  ]
}
"""#
    static var exampleJSON: String { substitute(exampleTemplate, settings: Settings()) }
    /// The example with explicit placeholders filled in, for the test that checks it appears
    /// in the prompt exactly once and is itself importable.
    static func exampleJSONText(units: WeightUnit, defaultRest: Int) -> String {
        substitute(exampleTemplate, settings: Settings(units: units, defaultRestSeconds: defaultRest))
    }
    private static func substitute(_ template: String, settings: Settings) -> String {
        template.replacingOccurrences(of: "{{units}}", with: settings.units.rawValue)
            .replacingOccurrences(of: "{{defaultRest}}", with: String(settings.defaultRestSeconds))
    }
    static func render(settings: Settings) -> String { substitute(planTemplate, settings: settings) }

    // MARK: - D52 (v1.5): a plan in several pastes

    /// Pinned to docs/PROMPT.md §4 by `PromptPinningTests`.
    static let outlineTemplate = #"""
JIMMSBRO-PLAN-PROMPT-V1
I am building my workout plan for a workout-tracking app one day at a time. First, reply with ONE JSON object holding only the plan's OUTLINE, in a single code block tagged json, with no other text.

FORMAT (schemaVersion 1):
{
  "schemaVersion": 1,
  "name": "Push Pull Legs",
  "units": "{{units}}",
  "defaultRestSeconds": {{defaultRest}},
  "restBetweenExercises": 120,
  "schedule": "rotation",
  "cycle": ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "rest"],
  "days": [ { "name": "Push" }, { "name": "Pull" }, { "name": "Legs" } ]
}

RULES
- days: training days in order, each with a name only — NO exercises yet. Do not list rest days as days.
- schedule: rotation = repeat days in order. Use weekday only for a fixed weekly schedule; give every day a weekday (monday…sunday) and omit cycle.
- cycle: rotation's full repeating block, using day names and "rest", including rest days. This drives the calendar.
- restBetweenExercises: whole seconds to walk between exercises; if unspecified, 120.
- Keep the day names short and distinct; I will ask for each day's exercises separately, one per message.
- Return ALL JSON, never abbreviate with "...".

My plan:
"""#

    /// The day prompt's head; the rules follow, shared with the plan prompt.
    static let dayHeader = #"""
JIMMSBRO-PLAN-PROMPT-V1
Now write ONLY the day "{{day}}" of my plan for the workout-tracking app. Reply with ONE JSON object in a single code block tagged json, with no other text.

FORMAT:
{
  "name": "{{day}}",
  "exercises": [
    { "name": "Barbell Bench Press", "sets": 4, "reps": "6-8", "weight": 80, "restSeconds": 150, "notes": "Pause on chest" },
    { "name": "Lateral Raise", "group": "A", "sets": 3, "reps": 15, "repRange": "12-15", "weight": 10, "restSeconds": 60 },
    { "name": "Tricep Pushdown", "group": "A", "sets": 3, "reps": 12, "repRange": "10-12", "weight": 25, "restSeconds": 60 },
    { "name": "Plank", "sets": 3, "durationSeconds": 45, "warningBeep": true, "bodyweight": true, "restSeconds": 45 }
  ]
}

THE OUTLINE (already agreed)
{{outline}}

RULES
"""#

    /// The plan prompt's rules minus the four the outline settled — days, schedule, cycle and,
    /// since v1.10 (D82), the walk between exercises — computed from `planRules` so the two
    /// cannot drift (Z16).
    static var dayRules: String {
        planRules.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.isEmpty && $0 != "RULES" && $0 != "My plan:"
                && !$0.hasPrefix("- days:") && !$0.hasPrefix("- schedule:") && !$0.hasPrefix("- cycle:")
                && !$0.hasPrefix("- restBetweenExercises:") }
            .joined(separator: "\n")
    }

    /// Pinned to docs/PROMPT.md §5 by `PromptPinningTests`.
    static var dayTemplate: String { dayHeader + "\n" + dayRules + "\n" }

    static func outline(settings: Settings) -> String { substitute(outlineTemplate, settings: settings) }

    /// The prompt for one day of an outline: the day by name, the outline as a listing, and
    /// the rules in the outline's own units.
    static func day(outline plan: Plan, dayIndex: Int, settings: Settings) -> String {
        let name = plan.days[safe: dayIndex]?.name ?? "Day \(dayIndex + 1)"
        return dayTemplate
            .replacingOccurrences(of: "{{day}}", with: name)
            .replacingOccurrences(of: "{{outline}}", with: outlineListing(plan))
            .replacingOccurrences(of: "{{units}}", with: plan.units.rawValue)
            .replacingOccurrences(of: "{{defaultRest}}", with: String(settings.defaultRestSeconds))
    }

    /// "Push Pull Legs · kg · rotation", the days, and a rotation's repeat block.
    static func outlineListing(_ plan: Plan) -> String {
        var lines = ["\(plan.name) · \(plan.units.rawValue) · \(plan.schedule.rawValue)"]
        let days = plan.days.map { day in day.weekday.map { "\(day.name) (\($0.rawValue))" } ?? day.name }
        lines.append("Days: " + days.joined(separator: ", "))
        if plan.schedule == .rotation {
            lines.append("Repeat block: " + RepeatBlock.chips(plan).map { $0 == "Rest" ? "rest" : $0 }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - D44 (v1.3): the progression prompt

    static let progressionMarker = ProgressionImport.promptMarker
    /// Pinned to docs/PROMPT.md §3 by `PromptPinningTests`.
    static let progressionTemplate = #"""
JIMMSBRO-PROGRESSION-PROMPT-V1
Plan my progression as {{steps}} steps for the workout plan below. {{cadence}} Reply with ONE complete JSON object in a single code block tagged json, with no other text.

FORMAT:
{
  "steps": {{steps}},
  "exercises": [
    { "day": "Push", "name": "Barbell Bench Press", "steps": [ { "weight": 80, "reps": "6-8" }, { "weight": 82.5, "reps": "6-8" }, {} ] }
  ]
}

RULES
- One entry per exercise in the plan, with its day and its exact name as written below. Leave an exercise out only if nothing about it should change.
- steps: exactly {{steps}} objects per exercise, step 1 first. An object gives the weight (in {{units}}, no unit text) and/or the reps for every set at that step; {} means no change from the plan at that step.
- reps: a whole number, a range like "8-12", "AMRAP", or "10+". For timed exercises give durationSeconds instead of reps. For bodyweight exercises give reps only.
- To vary the sets within a step, give "sets": [ { "weight": 60, "reps": 10 }, { "weight": 65, "reps": 8 } ] instead of weight and reps.
- Every weight must be loadable: a multiple of {{increment}} {{units}}.
- Progress conservatively from the plan and from my history below. If there are 6 steps or more, make one of them easier.
- Return ALL JSON, never abbreviate with "...".

MY PLAN
{{plan}}{{history}}
"""#

    /// D53 (v1.5): the sentence that says what a step is, by mode.
    static func cadence(_ mode: ProgressionMode) -> String {
        switch mode {
        case .performance:
            return "One step is one workout's targets; I move to the next step only when I hit the current one, so make each step a small, achievable increase."
        case .calendar:
            return "One step is one calendar week, starting the day I save it."
        }
    }

    /// The prompt for `plan`, over `weeks`, with the plan as a compact listing and — when asked
    /// and there is any — the last sessions of every exercise in it. Kept under the paste bound
    /// by shortening the history first, never the plan.
    static func progression(plan: Plan, history: [Session], weeks: Int, includeHistory: Bool,
                            settings: Settings, now: Date = Date(), mode: ProgressionMode = .calendar) -> String {
        let increment = TargetText.number(settings.weightIncrement(for: plan.units))
        func render(sessionsPerExercise: Int) -> String {
            let listing = includeHistory && sessionsPerExercise > 0
                ? historyListing(plan: plan, history: history, now: now, sessionsPerExercise: sessionsPerExercise) : ""
            return progressionTemplate
                .replacingOccurrences(of: "{{steps}}", with: String(weeks))
                .replacingOccurrences(of: "{{cadence}}", with: cadence(mode))
                .replacingOccurrences(of: "{{units}}", with: plan.units.rawValue)
                .replacingOccurrences(of: "{{increment}}", with: increment)
                .replacingOccurrences(of: "{{plan}}", with: planListing(plan))
                .replacingOccurrences(of: "{{history}}", with: listing.isEmpty ? "" : "\n\nMY HISTORY (most recent last)\n" + listing)
        }
        for count in [6, 3, 1] {
            let text = render(sessionsPerExercise: count)
            if text.count <= progressionBound { return text }
        }
        return render(sessionsPerExercise: 0)
    }

    /// Chat apps turn very long pastes into attachments (COPY_PASTE_NOTES.md); stay well under.
    static let progressionBound = 9_000


    /// "Push:\n- Barbell Bench Press: 4 × 6–8 · 80 kg · rest 150 s" — what the chatbot needs to
    /// know about the plan, without the JSON's weight.
    static func planListing(_ plan: Plan) -> String {
        plan.days.map { day -> String in
            let exercises = day.exercises.map { exercise -> String in
                // D58 (v1.6): the prompt is read by a chatbot, not by a person, and PROMPT.md pins it.
                var parts = [TargetText.summary(exercise, units: plan.units, wording: .compact)]
                if let rest = exercise.sets.first?.restSeconds { parts.append("rest \(rest) s") }
                if exercise.bodyweight { parts.append("bodyweight") }
                if let group = exercise.group { parts.append("superset \(group)") }
                if let notes = exercise.notes?.trimmed, !notes.isEmpty { parts.append(notes) }
                return "- \(exercise.name): " + parts.joined(separator: " · ")
            }
            return "\(day.name):\n" + exercises.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// One line per exercise of the plan that has history: its last sessions, oldest first,
    /// and the advice the most recent one earned.
    static func historyListing(plan: Plan, history: [Session], now: Date, sessionsPerExercise: Int) -> String {
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var seen = Set<String>()
        var lines: [String] = []
        for exercise in plan.days.flatMap(\.exercises) where seen.insert(normalized(exercise.name)).inserted {
            let sessions = history
                .filter { $0.endedAt != nil && $0.units == plan.units && $0.startedAt >= cutoff
                    && $0.exercises.contains { normalized($0.name) == normalized(exercise.name) } }
                .sorted { $0.startedAt < $1.startedAt }
                .suffix(sessionsPerExercise)
            guard !sessions.isEmpty else { continue }
            let entries = sessions.compactMap { session -> String? in
                let steps = ExerciseHistory.steps(name: exercise.name, session: session).filter { $0.status == .logged }
                guard !steps.isEmpty else { return nil }
                let results = steps.compactMap(\.result)
                let weights = results.map(\.weight)
                let same = weights.allSatisfy { $0 == weights.first ?? nil }
                let sets = results.map { result -> String in
                    if let seconds = result.seconds { return "\(seconds)s" }
                    let reps = result.reps.map(String.init) ?? "?"
                    if !same, let weight = result.weight { return "\(reps)@\(TargetText.number(weight))" }
                    return reps
                }.joined(separator: ",")
                var text = "\(formatter.string(from: session.startedAt)) \(sets)"
                if same, let weight = weights.first ?? nil { text += " @ \(TargetText.number(weight)) \(plan.units.rawValue)" }
                // D51 (v1.5): the sets were not to failure, and the chatbot should know.
                if let done = session.exercises.first(where: { normalized($0.name) == normalized(exercise.name) }) {
                    let reserves = Set(steps.map { done.targets[safe: $0.setIndex]?.inReserve })
                    if reserves.count == 1, let n = reserves.first ?? nil { text += " · \(TargetText.reserve(n, wording: .compact))" }
                }
                return text
            }
            var line = "- \(exercise.name): " + entries.joined(separator: "; ")
            if let last = sessions.last,
               let done = last.exercises.first(where: { normalized($0.name) == normalized(exercise.name) }),
               let advice = done.advice, let range = done.repRange {
                let logged = ExerciseHistory.steps(name: exercise.name, session: last).filter { $0.status == .logged }
                line += " (advice: " + ProgressionAdvice.message(advice, range: range, loggedSets: logged.count,
                                                                  currentWeight: logged.first?.result?.weight,
                                                                  units: plan.units) + ")"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
    static func render(errors: [Issue]) -> String {
        let errors = errors.filter { $0.severity == .error }
        var lines = errors.prefix(20).map { "- \($0.path): \($0.message)" }
        if errors.count > 20 { lines.append("- …and \(errors.count - 20) more") }
        return fixTemplate.replacingOccurrences(of: "{{errorLines}}", with: lines.joined(separator: "\n"))
    }
}
