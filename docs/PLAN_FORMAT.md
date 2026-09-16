# Plan format (schemaVersion 1)

This is the JSON the app imports. A chatbot writes it from the prompt in `docs/PROMPT.md`; humans may hand-edit it. The strict shape is in `schema/plan.schema.json`. This document adds the leniency rules (what the app accepts beyond the strict shape) and the validation rules with their codes. Test fixtures for every rule are in `examples/` with expected outcomes in `examples/manifest.json`.

## 1. Canonical example

```json
{
  "schemaVersion": 1,
  "name": "Push Pull Legs",
  "units": "kg",
  "defaultRestSeconds": 90,
  "restBetweenExercises": 120,
  "schedule": "rotation",
  "cycle": ["Push", "rest"],
  "days": [
    {
      "name": "Push",
      "defaultRestSeconds": 120,
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
```

## 2. Fields

### Plan (top level)
| Field | Type | Required | Notes |
|---|---|---|---|
| `schemaVersion` | int | no | Missing → 1. Greater than the app supports → `E_SCHEMA_VERSION`. |
| `name` | string | no | Missing/blank → "Imported plan <yyyy-MM-dd>" + `W_DEFAULT_NAME`. Max 100 chars (truncate + `W_NAME_TRUNCATED`). |
| `units` | "kg" \| "lb" | no | Case-insensitive; "kgs", "lbs", "pounds", "kilograms" accepted. Missing → user's setting. Other → `E_UNITS_INVALID`. |
| `defaultRestSeconds` | int ≥ 0 | no | Fallback for all days. |
| `restBetweenExercises` | int 0–3600 | no | **v1.10 (D82).** Seconds to walk between exercises — the minimum the Workout screen's ring fills over (SPEC §6.55). Missing → the user's *Between exercises* setting, at the moment of the walk. 0 = straight through. Read as every rest is: `"90"` accepted (§3.7); negative, over 3600 or non-integer → `E_REST_INVALID` at `restBetweenExercises`. |
| `schedule` | "rotation" \| "weekday" | no | Missing → inferred: every day has a weekday → weekday; none has → rotation; mixed → `E_SCHEDULE_MIXED`. Present but conflicting with the days → the days win with `W_SCHEDULE_INFERRED`. |
| `days` | array of Day | yes | 1–31 entries. Empty/missing → `E_NO_DAYS`. Over 31 → `E_LIMIT_EXCEEDED`. |
| `cycle` | array of string | no | The repeating block: day names in order with `"rest"` for rest days, e.g. `["Push","Pull","Legs","rest"]`. See §3.10. |

### Day
| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | no | Missing/blank → "Day N" + `W_DEFAULT_NAME`. Duplicates within a plan → auto-suffix " (2)", " (3)" + `W_DAY_RENAMED`. Max 100 chars. |
| `weekday` | string | weekday schedule only | Case-insensitive full names or 3-letter abbreviations ("Mon", "monday", "MONDAY"). Other → `E_WEEKDAY_INVALID`. Same weekday twice → `E_WEEKDAY_DUPLICATE`. Present in a rotation plan → ignored + `W_WEEKDAY_IGNORED`. |
| `defaultRestSeconds` | int ≥ 0 | no | Fallback for this day's exercises. |
| `exercises` | array of Exercise | yes | 1–50 entries. Empty/missing → `E_NO_EXERCISES`. Over 50 → `E_LIMIT_EXCEEDED`. |

### Exercise
| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Blank after trim → `E_MISSING_NAME`. Max 100 chars. |
| `group` | string | no | Trimmed, uppercased. Blank → treated as absent. See §3.5. |
| `sets` | int **or** array of Set | no | Missing → 1 set built from the exercise-level fields. Int: 1–50, all sets identical, built from exercise-level `reps`/`durationSeconds`/`weight`/`restSeconds`. Array: 1–50 Set objects; exercise-level `reps`/`durationSeconds`/`weight`/`restSeconds` act as defaults for any set that omits them. 0, negative, non-integer (2.5), or over 50 → `E_SETS_INVALID` / `E_LIMIT_EXCEEDED`. `3.0` is accepted as 3. |
| `reps` | int or string | see Set | Exercise-level default for sets. |
| `durationSeconds` | int or string | see Set | Exercise-level default for sets. `"max"` = open duration (§3.12). |
| `warningBeep` | bool or int | no | Warning beep before a fixed-duration set ends (§3.12). Exercise-level default for sets. |
| `bodyweight` | bool | no | `true` = no weight applies to this exercise (§3.13). |
| `weight` | number or string | no | Exercise-level default for sets. |
| `restSeconds` | int ≥ 0 | no | Rest after each set of this exercise. |
| `repRange` | string or int | no | The rep range the working weight should stay in, e.g. `"8-12"`; drives progression advice (SPEC §6.11). See §3.9 for defaults and leniency. |
| `inReserve` | int 0–20 | no | **v1.5 (D51)**: the effort target — reps (or seconds, on a hold) to stop short of failure. `rir` is accepted as an alias. Exercise-level default for sets. Anything else → `E_IN_RESERVE_INVALID`. Missing → none, and nothing is shown. |
| `drops` | array of Drop | no | Drop sets applied to every set of this exercise that doesn't define its own. See §3.11. |
| `notes` | string | no | Max 500 chars (truncate + `W_NOTES_TRUNCATED`). Shown on the step card. |

### Set
| Field | Type | Required | Notes |
|---|---|---|---|
| `reps` | int or string | exactly one of `reps`/`durationSeconds` | See §3.2. |
| `durationSeconds` | int 1–86400 or string | exactly one of `reps`/`durationSeconds` | 0 or negative → `E_DURATION_INVALID`. `"max"`, `"30+"` → open duration (§3.12). |
| `warningBeep` | bool or int | no | Overrides the exercise. Only meaningful on fixed-duration sets (§3.12). |
| `weight` | number ≥ 0 or string | no | See §3.3. Over 10000 → `E_WEIGHT_INVALID`. |
| `restSeconds` | int 0–3600 | no | Overrides the exercise. Negative or over 3600 → `E_REST_INVALID`. Non-integer (90.5) → `E_REST_INVALID`; `90.0` accepted. |
| `inReserve` | int 0–20 | no | Overrides the exercise (v1.5, D51). `rir` accepted. |
| `drops` | array of Drop | no | Overrides the exercise-level drops for this set. See §3.11. |

### Drop
| Field | Type | Required | Notes |
|---|---|---|---|
| `weight` | number or string | no | Same forms as Set weight. Omit to let the app prefill from the previous step. |
| `reps` | int or string | no | Same forms as Set reps. Missing → AMRAP. |

Any field not listed above, at any level, is ignored with `W_UNKNOWN_FIELD` (path + field name). This keeps old app versions tolerant of newer plans and tolerates chatbot inventions like `tempo` or `rpe`.

`null` for any optional field is the same as absent.

## 3. Leniency rules (Normalize stage)

### 3.1 Top-level shape
- Object with `days` → a plan.
- Object with `exercises` but no `days` → wrapped as a plan with one day. Plan name and day name both come from `name` (or defaults). `W_WRAPPED_SINGLE_DAY`.
- Array whose elements look like days (have `exercises`) → plan with those days. `W_WRAPPED_SINGLE_DAY`.
- Array whose elements look like exercises (have `name` and no `exercises`) → plan with one day. `W_WRAPPED_SINGLE_DAY`.
- Anything else (string, number, object with neither) → `E_NOT_A_PLAN` with a message naming what was found.

### 3.2 `reps` values
Accepted forms (whitespace trimmed; strings case-insensitive):

| Input | Result |
|---|---|
| `10` (int), `10.0`, `"10"` | fixed(10) |
| `"8-12"`, `"8 - 12"`, `"8–12"` (en dash), `"8—12"` (em dash), `"8 to 12"`, `"8/12"` | range(8, 12) |
| `"12-8"` | range(8, 12) + `W_RANGE_SWAPPED` |
| `"8-8"` | fixed(8) |
| `"AMRAP"`, `"amrap"`, `"max"`, `"failure"`, `"to failure"`, `"as many as possible"` | amrap(min: nil) |
| `"10+"`, `"10 +"` | amrap(min: 10) |
| `"8-12 reps"`, `"10 reps"` | trailing word "reps"/"rep" stripped, then as above |
| `0`, negative, `10.5`, `"ten"`, `""`, `"8-"`, `"-12"`, `"8-12-15"`, `true`, `{}` | `E_REPS_INVALID` |
| any number over 1000 (either bound) | `E_REPS_INVALID` |

### 3.3 `weight` values
| Input | Result |
|---|---|
| `60`, `62.5`, `"60"`, `"62,5"` | 60 / 62.5 |
| `"60kg"`, `"60 kg"`, `"135lb"`, `"135 lbs"` | number part; if the unit word disagrees with the plan's units → `W_WEIGHT_UNIT_IGNORED` |
| `"bw"`, `"bodyweight"`, `"body weight"`, `"BW"` | no weight, and the exercise becomes bodyweight (§3.13) |
| `"none"`, `""`, `null` | no weight |
| `"+10kg"`, `"+10"` | 10 (added load) |
| negative, `"heavy"`, `true`, `{}` | `E_WEIGHT_INVALID` |
| over 10000 | `E_WEIGHT_INVALID` |
Weights keep one decimal place (62.5 stays; 62.55 → 62.6 with `W_WEIGHT_ROUNDED`).

### 3.4 Sets shorthand expansion
`"sets": 3` + exercise-level `reps: "8-12"`, `weight: 60`, `restSeconds: 90` → three identical Set Targets. If neither `reps` nor `durationSeconds` is given at the exercise level → `E_TARGET_MISSING` at path `…exercises[i]`. If both → `E_TARGET_CONFLICT`.

`"sets": [ {...}, {...} ]`: each set object takes its own fields; missing `reps`/`durationSeconds`/`weight`/`restSeconds` are filled from the exercise level. A set that ends up with neither target → `E_TARGET_MISSING` at `…sets[k]`; both → `E_TARGET_CONFLICT`. A set with `reps` while the exercise-level has `durationSeconds` (or vice versa): the set's own field wins and the exercise-level one is not applied to that set (no error).

### 3.5 Groups
- Normalize: trim, uppercase. Blank → absent.
- Consecutive exercises with the same group → one block (SPEC §6.2).
- A group tag that appears on only one exercise → treated as ungrouped + `W_GROUP_SINGLE`.
- A group tag that re-appears after a different exercise (A, B, A) → the later run is a separate block, renamed "A2" + `W_GROUP_SPLIT`.
- Members with different set counts → rounds = max, shorter members drop out of later rounds + `W_GROUP_SET_MISMATCH`.

### 3.6 Rest fallback chain
Per set: `set.restSeconds → exercise.restSeconds → day.defaultRestSeconds → plan.defaultRestSeconds → user default (at import)`. Resolved values are stored on every Set Target. Missing everywhere → user default and no warning.

Between exercises (v1.10, D82): `plan.restBetweenExercises → user's Between exercises setting (at the walk)`. Not a set's rest, and not resolved into the Set Targets: the plan keeps the value as written (nil when absent), and the walk reads it when a block ends (SPEC §6.3). A set's own `restSeconds` is never used for the walk.

### 3.7 Numbers given as strings
Any integer field accepts a string of digits (`"3"`, `"90"`). Any number field accepts a numeric string with `.` or `,` as the decimal separator. Anything else → the field's `E_*_INVALID`.

### 3.8 Names
Trimmed. Internal whitespace collapsed for matching only (display keeps the original). Unicode allowed. Over 100 chars → truncated + `W_NAME_TRUNCATED`.

### 3.9 `repRange`
- Accepts the range forms of §3.2 (`"8-12"`, `"8 to 12"`, `"8–12"`, `"12-8"` swapped with `W_RANGE_SWAPPED`) and a single whole number `n` (or `"n"`), meaning `n-n`.
- `"AMRAP"`, `"10+"`, words, 0, negatives, fractions, anything over 1000 → `E_REPRANGE_INVALID` at `…exercises[i].repRange`.
- Missing: if the exercise-level `reps` is a range, `repRange` = that range. Otherwise no range (no progression advice for this exercise). Per-set rep ranges are not used for the default.
- Given on an exercise whose exercise-level target is `durationSeconds` → ignored + `W_REPRANGE_IGNORED`.
- Given with an exercise-level fixed `reps` n outside the range → kept + `W_REPRANGE_OUTSIDE` (the range wins for advice; the target stays n).

### 3.10 `cycle` (the repeat block)
- Rotation plans: if present, a non-empty list of 1–31 strings. Each entry is a day name (matched by normalized name, §3.8) or `"rest"` (case-insensitive; `"off"` also accepted). Unknown name → `E_CYCLE_UNKNOWN_DAY` at `cycle[i]`. Not a list, empty, over 31, or a non-string entry → `E_CYCLE_INVALID` at `cycle`. A day that never appears in the cycle → `W_CYCLE_MISSING_DAY` at `cycle` (once). Missing `cycle` → the days in listed order, no rest days.
- Weekday plans: the cycle is always derived as Monday…Sunday from the days' weekdays, with rest for unlisted weekdays. An explicit `cycle` → `W_CYCLE_IGNORED`.

### 3.11 `drops`
- A list of 1–5 Drop objects; each Drop is an object with optional `weight` and `reps`. Empty list, over 5, non-list, or non-object entry → `E_DROPS_INVALID` at the field's path. Weight/reps values follow §3.2 / §3.3 and report `E_WEIGHT_INVALID` / `E_REPS_INVALID` at `…drops[j].weight` / `…drops[j].reps`.
- Exercise-level `drops` apply to every set; a set's own `drops` replace them for that set (`"drops": []` at set level is `E_DROPS_INVALID`, not "no drops").
- Drops on a timed set → dropped with `W_DROPS_IGNORED`.
- Unknown fields inside a Drop → `W_UNKNOWN_FIELD`.

### 3.12 Timed sets: fixed, open, and beeps
- `durationSeconds` integer (or numeric string) 1–86400 → **fixed duration**: countdown, alert at the end.
- `durationSeconds` `"max"`, `"open"`, `"AMSAP"`, `"as long as possible"`, `"to failure"` (case-insensitive) → **open duration**: a stopwatch the user stops; the seconds held are logged. `"30+"` → open duration with a 30 s minimum shown as the target.
- Any other string, 0, negatives, fractions, over 86400 → `E_DURATION_INVALID`.
- Every fixed-duration set ends with a **final beep**. Before it, an optional **warning beep**, controlled by `warningBeep`:
  - missing or `true` → 10 % of the duration before the end, rounded half up to whole seconds, minimum 1 s; no warning at all for durations under 10 s.
  - `false` → no warning beep.
  - a whole number `n` (1–86399) → `n` seconds before the end. `n ≥ duration` → dropped with `W_WARNING_BEEP_IGNORED`.
  - anything else (`0`, negatives, fractions, strings) → `E_WARNING_BEEP_INVALID`.
  - given explicitly on a rep-based or open-duration set (or exercise) → dropped with `W_WARNING_BEEP_IGNORED`. A missing field on those never warns.
  The resolved offset is stored per set as `warningBeepSeconds` (nil = off).
- Open-duration sets with a minimum (`"30+"`) beep once when the minimum is reached. Open sets without a minimum never beep.

### 3.13 Bodyweight exercises
- `"bodyweight": true` on an exercise → the app never asks for a weight on it. Non-boolean → `E_BODYWEIGHT_INVALID`.
- A `weight` string of `"bw"`, `"bodyweight"`, `"body weight"` at exercise or set level also sets the flag (so chatbots that write `"weight": "bodyweight"` still work).
- A numeric `weight` (exercise, set, or drop level) on a bodyweight exercise → dropped with `W_BODYWEIGHT_WEIGHT_IGNORED`. For weighted calisthenics (dips +10 kg) don't set the flag; give the added load as the weight.
- An exercise with neither a weight nor the flag simply shows an empty weight field.

## 4. Validation rules (Validate stage) — full code list

Errors block import. Warnings are shown in Preview and saved on the plan. `path` uses JSON-pointer-like notation: `days[1].exercises[3].sets[0].reps`.

| Code | Severity | When |
|---|---|---|
| `E_EMPTY` | error | Nothing to parse after extraction |
| `E_TOO_LARGE` | error | Input over 1,048,576 bytes |
| `E_PROMPT_PASTED` | error | Input contains the prompt marker and no fenced code block (checked before anything else except size/empty) |
| `E_MULTIPLE_OBJECTS` | error | More than one top-level JSON value |
| `E_NOT_JSON` | error | No `{` or `[` found in the text, or strict decode failed (message includes the decoder error and, when available, line/column). A bare `null`, number, or string at top level lands here too |
| `E_NOT_A_PLAN` | error | JSON parsed but no recognizable shape (§3.1) |
| `E_SCHEMA_VERSION` | error | `schemaVersion` > supported |
| `E_UNITS_INVALID` | error | `units` not kg/lb |
| `E_SCHEDULE_MIXED` | error | Some days have weekdays, some don't, and no explicit schedule |
| `E_NO_DAYS` | error | `days` missing or empty |
| `E_NO_EXERCISES` | error | A day has no exercises |
| `E_MISSING_NAME` | error | Exercise name missing or blank |
| `E_SETS_INVALID` | error | `sets` is 0, negative, non-integer, or not int/array |
| `E_REPS_INVALID` | error | §3.2 rejected forms |
| `E_REPRANGE_INVALID` | error | §3.9 rejected forms |
| `E_DROPS_INVALID` | error | §3.11 rejected forms |
| `E_CYCLE_INVALID` | error | §3.10: not a list, empty, over 31, non-string entry |
| `E_CYCLE_UNKNOWN_DAY` | error | §3.10: cycle entry names no day |
| `E_DURATION_INVALID` | error | `durationSeconds` ≤ 0, > 86400, non-integer, or an unrecognized string (§3.12) |
| `E_WARNING_BEEP_INVALID` | error | `warningBeep` not a boolean or a whole number 1–86399 |
| `E_BODYWEIGHT_INVALID` | error | `bodyweight` not a boolean |
| `E_IN_RESERVE_INVALID` | error | `inReserve` / `rir` not a whole number from 0 to 20 (v1.5, D51) |
| `E_TARGET_MISSING` | error | A set has neither reps nor duration |
| `E_TARGET_CONFLICT` | error | A set has both reps and duration |
| `E_WEIGHT_INVALID` | error | §3.3 rejected forms |
| `E_REST_INVALID` | error | Rest negative, > 3600, or non-integer (any level, and `restBetweenExercises` since v1.10) |
| `E_WEEKDAY_INVALID` | error | Unrecognized weekday string |
| `E_WEEKDAY_DUPLICATE` | error | Two days share a weekday |
| `E_WEEKDAY_MISSING` | error | Explicit `schedule: "weekday"` and a day lacks `weekday` |
| `E_LIMIT_EXCEEDED` | error | > 31 days, > 50 exercises in a day, > 50 sets in an exercise |
| `W_SURROUNDING_TEXT` | warning | Prose/fences were stripped |
| `W_CURLY_QUOTES_FIXED` | warning | Decode succeeded only after replacing curly quotes |
| `W_WRAPPED_SINGLE_DAY` | warning | Top level was a day or array and was wrapped |
| `W_DEFAULT_NAME` | warning | Plan or day name defaulted |
| `W_NAME_TRUNCATED` | warning | Name over 100 chars |
| `W_NOTES_TRUNCATED` | warning | Notes over 500 chars |
| `W_DAY_RENAMED` | warning | Duplicate day name suffixed |
| `W_UNKNOWN_FIELD` | warning | Field ignored |
| `W_RANGE_SWAPPED` | warning | `"12-8"` read as 8–12 (reps or repRange) |
| `W_REPRANGE_IGNORED` | warning | `repRange` on a timed exercise |
| `W_REPRANGE_OUTSIDE` | warning | Fixed `reps` target outside `repRange` |
| `W_DROPS_IGNORED` | warning | `drops` on a timed set |
| `W_WARNING_BEEP_IGNORED` | warning | `warningBeep` on a rep-based or open-duration set, or not before the end |
| `W_BODYWEIGHT_WEIGHT_IGNORED` | warning | A weight given on a bodyweight exercise |
| `W_CYCLE_MISSING_DAY` | warning | A day never appears in the cycle |
| `W_CYCLE_IGNORED` | warning | `cycle` given on a weekday plan |
| `W_WEIGHT_UNIT_IGNORED` | warning | Weight string carried a unit that differs from the plan's |
| `W_WEIGHT_ROUNDED` | warning | Weight rounded to one decimal |
| `W_GROUP_SINGLE` | warning | Group with a single member |
| `W_GROUP_SPLIT` | warning | Non-consecutive reuse of a group tag |
| `W_GROUP_SET_MISMATCH` | warning | Group members have different set counts |
| `W_WEEKDAY_IGNORED` | warning | Weekday given on a rotation plan |
| `W_SCHEDULE_INFERRED` | warning | Explicit schedule contradicted the days |

Every error message is a full sentence a non-programmer can act on, and names the accepted forms. Example: `days[0].exercises[2].reps: "ten" is not a valid reps value. Use a whole number, a range like "8-12", "AMRAP", or "10+".`

## 5. Things the format deliberately does not have
- Rest days as Day entries (rest days live in `cycle` for rotation plans, and are the unlisted weekdays for weekday plans).
- Tempo, RPE, equipment fields (put them in `notes`). *Reps in reserve joined the format in v1.5 as `inReserve` (D51), because it changes how a set is done rather than describing it.*
- Warm-up flags (list warm-ups as their own exercises if wanted).
- Per-set notes.
