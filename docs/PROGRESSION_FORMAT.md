# Jimm's Bro+ — the progression reply (D44, v1.3; steps since D53, v1.5)

What the chatbot sends back to the prompt in `PROMPT.md` §3, and how the app reads it. It is
deliberately small: the plan's structure never changes, a progression is *attached* to the
plan you have, and only the step-by-step targets travel.

**v1.5 (D53).** A progression is a ladder of **steps** per exercise. In **performance mode**
(the default) an exercise moves to its next step when a workout achieves the current one, and
the calendar plays no part; in **calendar mode** (v1.3's behaviour, kept) one step is one
calendar week from the day the progression is saved. The mode is chosen on the screen, not in
the reply. The reply's word is `steps`; `weeks`, v1.3's word, is read as the same thing.

## 1. Canonical example

```json
{
  "steps": 4,
  "exercises": [
    { "day": "Push", "name": "Barbell Bench Press",
      "steps": [ { "weight": 80, "reps": "6-8" }, { "weight": 82.5 }, {}, { "weight": 85, "reps": "5-7" } ] },
    { "day": "Push", "name": "Plank",
      "steps": [ { "durationSeconds": 45 }, { "durationSeconds": 50 }, {}, { "durationSeconds": 60 } ] },
    { "day": "Pull", "name": "Barbell Row",
      "steps": [ { "sets": [ { "weight": 60, "reps": 10 }, { "weight": 65, "reps": 8 } ] }, {}, {}, {} ] }
  ]
}
```

## 2. Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `steps` | int 1–52 | no | The number of steps. Missing → the longest entry's length. Anything else → `E_PROGRESSION_WEEKS_INVALID`. `weeks` is accepted as an alias (`W_PROGRESSION_WEEKS_ALIAS`, cleanup). |
| `exercises` | array of Entry | yes | Empty or missing → `E_PROGRESSION_INVALID`. A bare top-level array is read as this list. The whole object may also sit under a `progression` key. |

### Entry
| Field | Type | Required | Notes |
|---|---|---|---|
| `day` | string | no | Matched to a plan day by name (SPEC §6.9). Missing → every day that has the exercise gets the same steps (`W_PROGRESSION_DAY_ASSUMED` when that is more than one). |
| `name` | string | yes | Matched to a plan exercise by name. Blank or missing → `E_PROGRESSION_EXERCISE_INVALID`. Not in the plan (on that day) → `W_PROGRESSION_UNMATCHED`, the entry is left out. |
| `steps` | array of Step | yes | Step 1 first. Missing → `E_PROGRESSION_WEEKS_INVALID`. Longer than `steps` → truncated (`W_PROGRESSION_LONG`); shorter → `W_PROGRESSION_SHORT`, and the plan's own targets apply after the last one. `weeks` is accepted as an alias. |

### Step
`null` or `{}` is "no change from the plan at this step". In performance mode such a step is
still a step: the workout has to achieve the plan's own targets to move on.

| Field | Type | Notes |
|---|---|---|
| `weight` | number or string | For every set at this step, in the plan's units. `"62.5 kg"` is accepted; `"bw"` / `"bodyweight"` / `"none"` mean no weight. Snapped to the smallest loadable change (D35, `W_PROGRESSION_ROUNDED`). Ignored on a bodyweight exercise (`W_PROGRESSION_WEIGHT_IGNORED`). Over 10000 or negative → `E_WEIGHT_INVALID`. |
| `reps` | int or string | For every set at this step: `8`, `"8-12"`, `"8 to 12"`, `"AMRAP"`, `"10+"`, `"max"`. A range also becomes the rep range advice judges by. Else `E_REPS_INVALID`. |
| `durationSeconds` | int or string | For timed exercises: seconds, `"max"`, `"30+"`. With `reps` as well → `E_TARGET_CONFLICT`. |
| `sets` | array of { `weight`, `reps` / `durationSeconds` } | Per-set values instead of `weight`/`reps`; set *n* of the plan's exercise takes entry *n*; extra entries are ignored. 1–50 objects, else `E_SETS_INVALID`. |

Any other field, at any level, is ignored with `W_UNKNOWN_FIELD`. Anything that is not an object where a Step is expected → `E_PROGRESSION_WEEK_INVALID`; where an Entry is expected → `E_PROGRESSION_EXERCISE_INVALID`. A reply in which no entry matched the plan → `E_PROGRESSION_EMPTY`.

## 3. Leniency

The reply goes through the same extract and decode stages as a plan (PLAN_FORMAT §3): a fenced block with prose around it, curly quotes, numbers as strings. The marker rule applies to *this* prompt's marker.

## 4. How the app uses it

- **Performance mode** (D53): every entry starts at step 1. **Starting a day** writes each entry's *current* step into the session's snapshot (D7) — an entry on a `{}` step keeps the plan's own targets but is still counted — and stamps each exercise with its step; the session's own number is the lowest of its exercises', which is what Home says ("step 3 of 8"). **Finishing the workout** moves every exercise that **achieved** its step to the next one — every main set logged, the reps at or above the target (the top of a range, the minimum of an AMRAP) within one rep across the exercise, every weight at or above the set's, every hold held for its seconds — and counts a try against every exercise that did not. Only the workout that completes moves a step; editing history later never does, and a session started before the step moved, or a substitute (D42), changes nothing. The progression is finished when every entry is past its last step; the day after, Home offers to plan the next one.
- **Calendar mode**: step 1 starts the day the progression is saved (`Progression.startDate`, midnight local), and steps are calendar weeks from there, exactly as v1.3's weeks. On the day after the last week the plan's own targets and advice are back.
- **Prefill** shows the step's weight and reps even when last time was different (SPEC §6.5, rule 0); the suggestion chip's reason reads "Step 3 of 8 of your progression" — or "Week 3 of 8" in calendar mode.
- **Plan edits** (D29, D43) keep the progression; entries match by name, so a renamed exercise simply stops matching. **Edit JSON** / Replace of the whole plan drops it — that is a new plan.

## 5. Codes

Errors: `E_PROMPT_PASTED`, `E_NOT_JSON`, `E_MULTIPLE_OBJECTS`, `E_EMPTY`, `E_TOO_LARGE` (as for a plan); `E_PROGRESSION_INVALID`, `E_PROGRESSION_WEEKS_INVALID` (the steps count or list — the code keeps v1.3's name), `E_PROGRESSION_EXERCISE_INVALID`, `E_PROGRESSION_WEEK_INVALID` (a step that is not an object), `E_PROGRESSION_EMPTY`, `E_REPS_INVALID`, `E_DURATION_INVALID`, `E_TARGET_CONFLICT`, `E_WEIGHT_INVALID`, `E_SETS_INVALID`.

Warnings, **material** (shown on the review): `W_PROGRESSION_UNMATCHED`, `W_PROGRESSION_SHORT`, `W_PROGRESSION_WEIGHT_IGNORED`. **Cleanup** (behind Details): `W_PROGRESSION_ROUNDED`, `W_PROGRESSION_LONG`, `W_PROGRESSION_DAY_ASSUMED`, `W_PROGRESSION_WEEKS_ALIAS`, `W_UNKNOWN_FIELD`, `W_SURROUNDING_TEXT`, `W_CURLY_QUOTES_FIXED`.
