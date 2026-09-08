import Foundation

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
- drops: list on exercise or individual set, e.g. [{"weight":20},{"weight":15}], done immediately after the main set with no rest. Reps default to AMRAP.
- Supersets/circuits: same group letter, consecutive exercises, equal set counts. Rest after each round.
- Names: specific and consistent ("Barbell Back Squat", not "Squats"); reuse spelling across days for history matching.
- Keep execution order. If I supply exercises, use exactly those: no additions, removals, or reordering. If I request a plan, design a sensible one.
- Put tempo, RPE, cues and "each side" in notes.
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
    static func render(errors: [Issue]) -> String {
        let errors = errors.filter { $0.severity == .error }
        var lines = errors.prefix(20).map { "- \($0.path): \($0.message)" }
        if errors.count > 20 { lines.append("- …and \(errors.count - 20) more") }
        return fixTemplate.replacingOccurrences(of: "{{errorLines}}", with: lines.joined(separator: "\n"))
    }
}
