# Chatbot prompts

The app copies these texts to the clipboard. Placeholders in `{{ }}` are filled from Settings at copy time. The line `JIMMSBRO-PLAN-PROMPT-V1` is the **prompt marker**. Rule: if the pasted text contains the marker and **no fenced code block** (three backticks), the app reports `E_PROMPT_PASTED` ("That's the prompt. Paste the chatbot's JSON reply instead."). A chatbot reply always has a fence, and the prompt itself must never contain three backticks, which is why the prompts below say "code block tagged json" instead of writing the fence. The prompt does contain an example JSON object, so a plain "marker and no JSON" check would import the example by mistake.

## 1. Plan prompt (Import → Copy prompt)

```
JIMMSBRO-PLAN-PROMPT-V1
Convert my workout plan to JSON for a workout-tracking app. Reply with ONE complete JSON object in a single code block tagged json, with no other text.

FORMAT (schemaVersion 1):
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
- inReserve: how many reps (or seconds, for holds) short of failure each set should stop, e.g. 2. Omit when I do not say.
- Put tempo, cues and "each side" in notes.
- Return ALL JSON, never abbreviate with "...".

My plan:
```

The user types or pastes their description after "My plan:".

Rendered length: 3,510 characters with kg and rest 90. Keep it under 4,000. Chat apps may handle longer pastes differently; see `COPY_PASTE_NOTES.md`. 

## 2. Fix-it prompt (Import error → Copy fix-it prompt)

```
JIMMSBRO-PLAN-PROMPT-V1
The workout app rejected the JSON with these errors:
{{errorLines}}

Fix them and reply with the complete corrected JSON only, in one code block tagged json, keeping the same format and rules as before. Do not change anything else.
```

`{{errorLines}}` is one line per error: `- <path>: <message>`. Include at most 20 errors; if more, add `- …and N more`. Include the original decoder message for `E_NOT_JSON` (e.g. "Unexpected end of file" tells the chatbot its output was cut off).

## 3. Progression prompt (History → Progression → Copy prompt)

**v1.5 (D53).** The progression is a ladder of *steps*; `{{cadence}}` says what a step is — in performance mode (the default) one workout's targets, earned by hitting them; in calendar mode one calendar week, as in v1.3. `{{steps}}` is the number chosen on the screen. The reply's `weeks` key is still read, as an alias. `{{goals}}` (D54) is the plan's unreached goals as a MY GOALS block, or nothing.

The line `JIMMSBRO-PROGRESSION-PROMPT-V1` is this prompt's marker, with the same rule as §1: the marker and no fenced code block means the prompt itself was pasted (`E_PROMPT_PASTED`). `{{weeks}}` is the period the owner picked (4, 6, 8 or 12), `{{units}}` and `{{increment}}` come from the plan and Settings, `{{plan}}` is the plan as a compact listing — one line per exercise, not its JSON — and `{{history}}` is empty or a block headed `MY HISTORY (most recent last)` with one line per exercise: its last sessions (up to six, within 90 days) and the advice the most recent one earned. The history is shortened first, never the plan, to stay under 9,000 characters (`COPY_PASTE_NOTES.md`).

```
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
{{plan}}{{goals}}{{history}}

```

The reply format is `docs/PROGRESSION_FORMAT.md`.

## 4. Outline prompt (Add plan → Build it day by day → Copy outline prompt)

**v1.5 (D52).** A plan built in several pastes, for long plans and free chatbot tiers. The outline first: the header, the day names and the repeat block, no exercises. It carries the plan prompt's marker, so pasting it into the app is refused the same way.

```
JIMMSBRO-PLAN-PROMPT-V1
I am building my workout plan for a workout-tracking app one day at a time. First, reply with ONE JSON object holding only the plan's OUTLINE, in a single code block tagged json, with no other text.

FORMAT (schemaVersion 1):
{
  "schemaVersion": 1,
  "name": "Push Pull Legs",
  "units": "{{units}}",
  "defaultRestSeconds": {{defaultRest}},
  "schedule": "rotation",
  "cycle": ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "rest"],
  "days": [ { "name": "Push" }, { "name": "Pull" }, { "name": "Legs" } ]
}

RULES
- days: training days in order, each with a name only — NO exercises yet. Do not list rest days as days.
- schedule: rotation = repeat days in order. Use weekday only for a fixed weekly schedule; give every day a weekday (monday…sunday) and omit cycle.
- cycle: rotation's full repeating block, using day names and "rest", including rest days. This drives the calendar.
- Keep the day names short and distinct; I will ask for each day's exercises separately, one per message.
- Return ALL JSON, never abbreviate with "...".

My plan:
```

## 5. Day prompt (Add plan → Build it day by day → Copy day prompt)

**v1.5 (D52).** One per day of the outline. `{{day}}` is the day's name, `{{outline}}` the outline as a listing (`Prompts.outlineListing`), `{{units}}` the outline's units. The rules are the plan prompt's minus the three the outline settled (days, schedule, cycle), computed from the same text in the app so they cannot drift.

```
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
- inReserve: how many reps (or seconds, for holds) short of failure each set should stop, e.g. 2. Omit when I do not say.
- Put tempo, cues and "each side" in notes.
- Return ALL JSON, never abbreviate with "...".
```

## 6. Behavior notes for the app
- All five prompts are plain strings in `Core/Prompts.swift` with a `render(settings:)` / `render(errors:)` function, unit-tested (placeholders substituted, marker present, length bound).
- After **Copy prompt**, show a toast for 3 s. Don't navigate away.
- The prompt marker line must never appear in the JSON example, or a chatbot might echo it inside the plan.
- The example JSON inside the plan prompt is also exposed as `Prompts.exampleJSON` so a test can import it (TEST_CASES M4). `examples/valid/prompt-example.txt` is that same text; `examples/invalid/prompt-pasted-full.txt` preserves the original full prompt as an unchanged regression fixture; the shortened prompt has its own automated marker test.
- Never put three backticks anywhere in either prompt (see the marker rule above).
