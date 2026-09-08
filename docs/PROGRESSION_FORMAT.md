# Jimm's Bro+ — the progression reply (D44, v1.3)

What the chatbot sends back to the prompt in `PROMPT.md` §3, and how the app reads it. It is
deliberately small: the plan's structure never changes, a progression is *attached* to the
plan you have, and only the week-by-week targets travel.

## 1. Canonical example

```json
{
  "weeks": 4,
  "exercises": [
    { "day": "Push", "name": "Barbell Bench Press",
      "weeks": [ { "weight": 80, "reps": "6-8" }, { "weight": 82.5 }, {}, { "weight": 85, "reps": "5-7" } ] },
    { "day": "Push", "name": "Plank",
      "weeks": [ { "durationSeconds": 45 }, { "durationSeconds": 50 }, {}, { "durationSeconds": 60 } ] },
    { "day": "Pull", "name": "Barbell Row",
      "weeks": [ { "sets": [ { "weight": 60, "reps": 10 }, { "weight": 65, "reps": 8 } ] }, {}, {}, {} ] }
  ]
}
```

## 2. Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `weeks` | int 1–52 | no | The period. Missing → the longest entry's length. Anything else → `E_PROGRESSION_WEEKS_INVALID`. |
| `exercises` | array of Entry | yes | Empty or missing → `E_PROGRESSION_INVALID`. A bare top-level array is read as this list. The whole object may also sit under a `progression` key. |

### Entry
| Field | Type | Required | Notes |
|---|---|---|---|
| `day` | string | no | Matched to a plan day by name (SPEC §6.9). Missing → every day that has the exercise gets the same weeks (`W_PROGRESSION_DAY_ASSUMED` when that is more than one). |
| `name` | string | yes | Matched to a plan exercise by name. Blank or missing → `E_PROGRESSION_EXERCISE_INVALID`. Not in the plan (on that day) → `W_PROGRESSION_UNMATCHED`, the entry is left out. |
| `weeks` | array of Week | yes | Week 1 first. Missing → `E_PROGRESSION_WEEKS_INVALID`. Longer than `weeks` → truncated (`W_PROGRESSION_LONG`); shorter → `W_PROGRESSION_SHORT`, and the plan's own targets apply after the last one. |

### Week
`null` or `{}` is "no change from the plan that week".

| Field | Type | Notes |
|---|---|---|
| `weight` | number or string | For every set that week, in the plan's units. `"62.5 kg"` is accepted; `"bw"` / `"bodyweight"` / `"none"` mean no weight. Snapped to the smallest loadable change (D35, `W_PROGRESSION_ROUNDED`). Ignored on a bodyweight exercise (`W_PROGRESSION_WEIGHT_IGNORED`). Over 10000 or negative → `E_WEIGHT_INVALID`. |
| `reps` | int or string | For every set that week: `8`, `"8-12"`, `"8 to 12"`, `"AMRAP"`, `"10+"`, `"max"`. A range also becomes the rep range advice judges by. Else `E_REPS_INVALID`. |
| `durationSeconds` | int or string | For timed exercises: seconds, `"max"`, `"30+"`. With `reps` as well → `E_TARGET_CONFLICT`. |
| `sets` | array of { `weight`, `reps` / `durationSeconds` } | Per-set values instead of `weight`/`reps`; set *n* of the plan's exercise takes entry *n*; extra entries are ignored. 1–50 objects, else `E_SETS_INVALID`. |

Any other field, at any level, is ignored with `W_UNKNOWN_FIELD`. Anything that is not an object where a Week is expected → `E_PROGRESSION_WEEK_INVALID`; where an Entry is expected → `E_PROGRESSION_EXERCISE_INVALID`. A reply in which no entry matched the plan → `E_PROGRESSION_EMPTY`.

## 3. Leniency

The reply goes through the same extract and decode stages as a plan (PLAN_FORMAT §3): a fenced block with prose around it, curly quotes, numbers as strings. The marker rule applies to *this* prompt's marker.

## 4. How the app uses it

- **Week 1 starts the day the progression is saved** (`Progression.startDate`, midnight local), and weeks are calendar weeks from there. On the day after the last week the plan's own targets and advice are back, and Home offers to plan the next one.
- **Starting a day** in one of its weeks writes that week's targets into the session's snapshot (D7): every set's weight and/or work from the entry, per set when `sets` was given. An exercise, week or set the progression says nothing about keeps the plan's own target. The exercise and the session record the week.
- **Prefill** shows the week's weight and reps even when last time was different (SPEC §6.5, rule 0); the suggestion chip's reason reads "Week 3 of 8 of your progression".
- **Plan edits** (D29, D43) keep the progression; entries match by name, so a renamed exercise simply stops matching. **Edit JSON** / Replace of the whole plan drops it — that is a new plan.

## 5. Codes

Errors: `E_PROMPT_PASTED`, `E_NOT_JSON`, `E_MULTIPLE_OBJECTS`, `E_EMPTY`, `E_TOO_LARGE` (as for a plan); `E_PROGRESSION_INVALID`, `E_PROGRESSION_WEEKS_INVALID`, `E_PROGRESSION_EXERCISE_INVALID`, `E_PROGRESSION_WEEK_INVALID`, `E_PROGRESSION_EMPTY`, `E_REPS_INVALID`, `E_DURATION_INVALID`, `E_TARGET_CONFLICT`, `E_WEIGHT_INVALID`, `E_SETS_INVALID`.

Warnings, **material** (shown on the review): `W_PROGRESSION_UNMATCHED`, `W_PROGRESSION_SHORT`, `W_PROGRESSION_WEIGHT_IGNORED`. **Cleanup** (behind Details): `W_PROGRESSION_ROUNDED`, `W_PROGRESSION_LONG`, `W_PROGRESSION_DAY_ASSUMED`, `W_UNKNOWN_FIELD`, `W_SURROUNDING_TEXT`, `W_CURLY_QUOTES_FIXED`.
