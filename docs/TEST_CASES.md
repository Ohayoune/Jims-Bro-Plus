# Test cases

Type: **unit** = automated test on Core types (required, must pass). **ui** = SwiftUI/XCUITest or simulator check. **manual** = physical-device checklist in BUILD_PLAN. **check** (v1.4) = a script in `tools/` that must exit 0.
Fixtures referenced as `valid/x.json` / `invalid/x.txt` live in `examples/`; `examples/manifest.json` lists the expected codes for each. Tests for A–D should iterate the manifest, plus the specific assertions below. `tools/reference_import.py` passes the whole manifest and is the oracle for any disputed case.

## A. Import — Extract stage
| ID | Type | Case | Expected |
|---|---|---|---|
| A1 | unit | Bare JSON object | Passed through unchanged, no warnings |
| A2 | unit | ```` ```json { … } ``` ```` fence | Inner JSON; `W_SURROUNDING_TEXT` not raised (fence only) |
| A3 | unit | Prose before and after a fence ("Here's your plan: … Let me know!") | Inner JSON; `W_SURROUNDING_TEXT` |
| A4 | unit | Fence tagged ```` ```javascript ```` or untagged ```` ``` ```` | Inner JSON |
| A5 | unit | No fence, prose then `{…}` then prose | From first `{` to its matching `}` (string-aware scan); `W_SURROUNDING_TEXT` |
| A6 | unit | Two fences, each a plan | `E_MULTIPLE_OBJECTS` |
| A7 | unit | Two top-level objects with no fence `{…} {…}` | `E_MULTIPLE_OBJECTS` |
| A8 | unit | Empty string / whitespace only / only newlines | `E_EMPTY` |
| A9 | unit | Leading BOM `\u{FEFF}` and zero-width spaces `\u{200B}` | Stripped; parses |
| A10 | unit | Input of 1,048,577 bytes | `E_TOO_LARGE` before any parsing |
| A11 | unit | The plan prompt itself pasted (`invalid/prompt-pasted-full.txt`: marker, an example JSON object, no fence) | `E_PROMPT_PASTED`, not an import of the example |
| A11b | unit | Marker with plain text and no braces (`invalid/prompt-pasted.txt`) | `E_PROMPT_PASTED` |
| A12 | unit | Marker present AND a valid JSON block | Imports normally (marker in prose ignored) |
| A13 | unit | Top-level array `[ … ]` | Extracted the same way as an object |
| A14 | unit | Braces inside string values (`"notes": "hold {tight}"`) | Matching uses a JSON-aware scan, not naive first/last brace; parses |

## B. Import — Decode stage
| ID | Type | Case | Expected |
|---|---|---|---|
| B1 | unit | Trailing comma `{"days": [],}` | `E_NOT_JSON`; message contains the decoder's description |
| B2 | unit | Comments `// …` in JSON | `E_NOT_JSON` |
| B3 | unit | Curly quotes `“name”: “Push”` | Retry succeeds; `W_CURLY_QUOTES_FIXED` |
| B4 | unit | Curly quotes inside a string value only (`"notes": "“slow”"`) | Strict decode succeeds first try; no warning; value preserved |
| B5 | unit | Truncated JSON (cut mid-array) | `E_NOT_JSON`; message mentions unexpected end so the fix-it prompt is useful |
| B6 | unit | Single-quoted strings `{'days': []}` | `E_NOT_JSON` |
| B7 | unit | `NaN` / `Infinity` literals | `E_NOT_JSON` |
| B8 | unit | Deeply nested unrelated JSON (e.g. a package.json) | Decodes as raw, then `E_NOT_A_PLAN` in Normalize |
| B9 | unit | `null`, a number, or a string at top level (no `{`/`[`) | `E_NOT_JSON` ("No JSON found") |

## C. Import — Normalize stage
### C.1 Top-level shape
| ID | Type | Case | Expected |
|---|---|---|---|
| C1 | unit | Object with `days` | Plan |
| C2 | unit | Object with `exercises`, no `days` (`valid/single-day-bare.json`) | One-day plan; day name = plan name; `W_WRAPPED_SINGLE_DAY` |
| C3 | unit | Array of day objects (`valid/array-of-days.json`) | Plan with those days; `W_WRAPPED_SINGLE_DAY` |
| C4 | unit | Array of exercise objects | One-day plan; `W_WRAPPED_SINGLE_DAY` |
| C5 | unit | Object with neither `days` nor `exercises` | `E_NOT_A_PLAN` |
| C6 | unit | `"days": {}` (object not array) | `E_NO_DAYS` |
| C7 | unit | Missing plan name / `""` / `"   "` | "Imported plan <date>"; `W_DEFAULT_NAME` |
| C8 | unit | `schemaVersion` missing | Treated as 1 |
| C9 | unit | `schemaVersion: 2` | `E_SCHEMA_VERSION` |
| C10 | unit | `schemaVersion: "1"` | Accepted as 1 |
| C11 | unit | `units` "KG", "kgs", "lbs", "Pounds", "kilograms" | kg / kg / lb / lb / kg |
| C12 | unit | `units: "stone"` | `E_UNITS_INVALID` |
| C13 | unit | `units` missing, settings = lb | Plan units lb |

### C.2 Schedule and weekdays
| ID | Type | Case | Expected |
|---|---|---|---|
| C14 | unit | No `schedule`, all days have weekdays | schedule = weekday, no warning |
| C15 | unit | No `schedule`, no weekdays | rotation |
| C16 | unit | No `schedule`, some weekdays | `E_SCHEDULE_MIXED` |
| C17 | unit | `schedule: "weekday"`, one day lacks weekday | `E_WEEKDAY_MISSING` at that day's path |
| C18 | unit | `schedule: "rotation"`, days have weekdays | rotation; `W_WEEKDAY_IGNORED` per day |
| C19 | unit | `schedule: "Weekly"` (unknown value) | Inferred from days + `W_SCHEDULE_INFERRED` |
| C20 | unit | Weekday "Mon", "monday", "MONDAY", "  tue " | monday, monday, monday, tuesday |
| C21 | unit | Weekday "Funday", "M", "Mondays" | `E_WEEKDAY_INVALID` |
| C22 | unit | Two days both "friday" | `E_WEEKDAY_DUPLICATE` on the second |

### C.3 Days and names
| ID | Type | Case | Expected |
|---|---|---|---|
| C23 | unit | Day without name | "Day 1", "Day 2"… by position; `W_DEFAULT_NAME` |
| C24 | unit | Two days named "Push" and "push " (matched after trim + case-fold) | Second becomes "push (2)" (trimmed original + suffix); `W_DAY_RENAMED` |
| C25 | unit | Three days "A", "A", "A" | "A", "A (2)", "A (3)" |
| C26 | unit | Name 150 chars | Truncated to 100; `W_NAME_TRUNCATED` |
| C27 | unit | Name with emoji and CJK "🏋️ 胸" | Preserved |
| C28 | unit | Exercise name missing / `""` / `"  "` / `null` | `E_MISSING_NAME` at `days[i].exercises[j].name` |
| C29 | unit | Exercise name `"  Bench   Press "` | Display "Bench   Press" trimmed; normalized "bench press" |
| C30 | unit | Notes 600 chars | Truncated to 500; `W_NOTES_TRUNCATED` |

### C.4 Sets, reps, duration
| ID | Type | Case | Expected |
|---|---|---|---|
| C31 | unit | `sets: 3, reps: 10` | 3 SetTargets fixed(10) |
| C32 | unit | `sets: 3.0` | 3 sets |
| C33 | unit | `sets: "4"` | 4 sets |
| C34 | unit | `sets: 0` / `-1` / `2.5` / `true` / `"three"` | `E_SETS_INVALID` |
| C35 | unit | `sets: 51` | `E_LIMIT_EXCEEDED` |
| C36 | unit | `sets` missing, `reps: 10` | 1 set |
| C37 | unit | `sets` missing, no `reps`, no `durationSeconds` | `E_TARGET_MISSING` at exercise path |
| C38 | unit | `sets: 3` with both `reps` and `durationSeconds` at exercise level | `E_TARGET_CONFLICT` |
| C39 | unit | `sets: []` | `E_SETS_INVALID` |
| C40 | unit | `sets: [{reps:12},{reps:10},{reps:8}]`, exercise-level `weight: 60` | All three sets weight 60 |
| C41 | unit | `sets: [{reps:12, weight: 50},{reps:10}]`, exercise-level `weight: 60` | 50 then 60 |
| C42 | unit | `sets: [{weight: 60}]`, exercise-level `reps: 10` | fixed(10) @ 60 |
| C43 | unit | `sets: [{}]`, no exercise-level target | `E_TARGET_MISSING` at `…sets[0]` |
| C44 | unit | `sets: [{reps: 10, durationSeconds: 30}]` | `E_TARGET_CONFLICT` at `…sets[0]` |
| C45 | unit | `sets: [{durationSeconds: 30}]`, exercise-level `reps: 10` | Set is duration(30); exercise reps not applied; no error |
| C46 | unit | `sets: [{reps: 10}, {restSeconds: 120}]`, exercise-level `reps: 8`, `restSeconds: 60` | set0 fixed(10) rest 60; set1 fixed(8) rest 120 |
| C47 | unit | reps `10`, `10.0`, `"10"`, `" 10 "` | fixed(10) |
| C48 | unit | reps `"8-12"`, `"8 - 12"`, `"8–12"`, `"8—12"`, `"8 to 12"`, `"8/12"` | range(8,12) |
| C49 | unit | reps `"12-8"` | range(8,12) + `W_RANGE_SWAPPED` |
| C50 | unit | reps `"8-8"` | fixed(8) |
| C51 | unit | reps `"AMRAP"`, `"amrap"`, `"Max"`, `"failure"`, `"to failure"`, `"as many as possible"` | amrap(nil) |
| C52 | unit | reps `"10+"`, `"10 +"` | amrap(min 10) |
| C53 | unit | reps `"8-12 reps"`, `"10 reps"`, `"1 rep"` | range(8,12), fixed(10), fixed(1) |
| C54 | unit | reps `0`, `-5`, `10.5`, `"ten"`, `""`, `"8-"`, `"-12"`, `"8-12-15"`, `true`, `{}`, `[]` | `E_REPS_INVALID` each, message lists accepted forms |
| C55 | unit | reps `1001`, `"5-2000"` | `E_REPS_INVALID` |
| C56 | unit | reps `1000` | fixed(1000) (boundary accepted) |
| C57 | unit | `durationSeconds: 45`, `"45"`, `45.0` | duration(45) |
| C58 | unit | `durationSeconds: 0`, `-1`, `30.5`, `"30s"`, `86401` | `E_DURATION_INVALID` |
| C59 | unit | `durationSeconds: 86400` | Accepted |

### C.5 Weight
| ID | Type | Case | Expected |
|---|---|---|---|
| C60 | unit | `60`, `62.5`, `"60"`, `"62,5"`, `"62.5"` | 60, 62.5, 60, 62.5, 62.5 |
| C61 | unit | `"60kg"`, `"60 kg"`, `"60 KG"` on a kg plan | 60, no warning |
| C62 | unit | `"135lb"`, `"135 lbs"` on a kg plan | 135 + `W_WEIGHT_UNIT_IGNORED` |
| C63 | unit | `"bw"`, `"BW"`, `"bodyweight"`, `"body weight"` | no weight, exercise `bodyweight = true`, no warning |
| C63b | unit | `"none"`, `""`, `null` | no weight, flag unchanged, no warning |
| C64 | unit | `"+10kg"`, `"+10"` | 10 |
| C65 | unit | `-5`, `"heavy"`, `true`, `{}` | `E_WEIGHT_INVALID` |
| C66 | unit | `10001` | `E_WEIGHT_INVALID`; `10000` accepted |
| C67 | unit | `62.55` | 62.6 + `W_WEIGHT_ROUNDED`; `62.5` unchanged, no warning |
| C68 | unit | `0` | weight 0 (kept, not treated as absent) |

### C.6 Rest
| ID | Type | Case | Expected |
|---|---|---|---|
| C69 | unit | Only plan `defaultRestSeconds: 100` | Every set rest 100 |
| C70 | unit | Plan 100, day 80 | 80 for that day's sets; other days 100 |
| C71 | unit | Plan 100, day 80, exercise 70 | 70 |
| C72 | unit | Plan 100, day 80, exercise 70, set 60 | 60 for that set, 70 for the others |
| C73 | unit | Nothing anywhere, settings default 90 | 90 |
| C74 | unit | `restSeconds: 0` | 0 (no rest), not treated as missing |
| C75 | unit | `restSeconds: -1`, `3601`, `90.5`, `"1m30"` | `E_REST_INVALID` at the right path |
| C76 | unit | `restSeconds: "90"`, `90.0`, `3600` | 90, 90, 3600 |

### C.7 Groups
| ID | Type | Case | Expected |
|---|---|---|---|
| C77 | unit | `group: "a"` and `"A"` on consecutive exercises | Same group "A" |
| C78 | unit | `group: " "` | Absent |
| C79 | unit | One exercise with group "A", neighbors ungrouped | Ungrouped + `W_GROUP_SINGLE` |
| C80 | unit | A, A, B, A | Blocks: [A,A], [B], [A2]; `W_GROUP_SPLIT`; the lone A2 also gets `W_GROUP_SINGLE` |
| C81 | unit | A (3 sets), A (2 sets) | `W_GROUP_SET_MISMATCH`; block rounds = 3 |
| C82 | unit | `group: 1` (number) | Accepted as "1" |

### C.8 Unknown fields and nulls
| ID | Type | Case | Expected |
|---|---|---|---|
| C83 | unit | `"tempo": "3010"`, `"rpe": 8` on an exercise | Ignored; `W_UNKNOWN_FIELD` ×2 with path and field name |
| C84 | unit | Unknown top-level field `"author"` | `W_UNKNOWN_FIELD` |
| C85 | unit | `"weight": null`, `"notes": null`, `"group": null` | As absent, no warning |
| C86 | unit | `"days": null` | `E_NO_DAYS` |

### C.9 repRange (`valid/reprange-cases.json`)
| ID | Type | Case | Expected |
|---|---|---|---|
| C87 | unit | `reps: 10, repRange: "8-12"` | RepRange(8,12) |
| C88 | unit | `reps: "8-12"`, no repRange | RepRange(8,12) inherited from reps |
| C89 | unit | `reps: 10`, no repRange | nil (no advice for this exercise) |
| C90 | unit | `reps: 15, repRange: "8-12"` | RepRange(8,12) + `W_REPRANGE_OUTSIDE`; target stays 15 |
| C91 | unit | `durationSeconds: 30, repRange: "8-12"` | nil + `W_REPRANGE_IGNORED` |
| C92 | unit | `repRange: 10` (int) or `"10"` | RepRange(10,10) |
| C93 | unit | `repRange: "12-8"` | RepRange(8,12) + `W_RANGE_SWAPPED` at the repRange path |
| C94 | unit | Per-set reps `[{reps:"8-12"},…]` and no exercise-level reps or repRange | nil (per-set ranges don't set the default) |
| C95 | unit | `repRange: "lots"`, `"AMRAP"`, `"0-5"`, `"10+"`, `2.5`, `true` | `E_REPRANGE_INVALID` at `…exercises[i].repRange` |

### C.10 drops (`valid/drop-sets.json`)
| ID | Type | Case | Expected |
|---|---|---|---|
| C96 | unit | Exercise-level `drops: [{weight:15},{weight:10,reps:"8-10"}]`, 3 sets | Every set has 2 drops: (amrap, 15), (range 8–10, 10) |
| C97 | unit | Set-level `drops` on set 2 only, none at exercise level | Sets 0–1 have 0 drops, set 2 has 1 |
| C98 | unit | Set-level drops when exercise-level drops exist | Set's own list replaces the exercise's |
| C99 | unit | Drop without `reps` | AMRAP |
| C100 | unit | Drop without `weight` | weight nil (prefilled at run time from the previous step) |
| C101 | unit | Drops on a timed set / timed exercise | Removed + `W_DROPS_IGNORED` |
| C102 | unit | `drops: []`, 6 drops, `drops: {…}`, `drops: [5]` | `E_DROPS_INVALID` at the drops path |
| C103 | unit | `drops: [{weight:"heavy"}]`, `[{reps:"ten"}]` | `E_WEIGHT_INVALID` / `E_REPS_INVALID` at `…drops[0].weight` / `.reps` |
| C104 | unit | Unknown field inside a drop | `W_UNKNOWN_FIELD` |

### C.11 cycle (`valid/cycle-cases.json`, `valid/cycle-weekday-ignored.json`)
| ID | Type | Case | Expected |
|---|---|---|---|
| C105 | unit | `cycle: ["upper","REST","Lower","off"]` with days Upper, Lower, Arms | [Upper, rest, Lower, rest]; `W_CYCLE_MISSING_DAY` (Arms) |
| C106 | unit | No cycle, rotation, 3 days | [day 0, day 1, day 2] |
| C107 | unit | Weekday plan with Tue and Sat | [rest, A, rest, rest, rest, B, rest]; an explicit cycle → `W_CYCLE_IGNORED` |
| C108 | unit | `cycle: ["A","Legs"]` where Legs isn't a day | `E_CYCLE_UNKNOWN_DAY` at `cycle[1]` |
| C109 | unit | `cycle: []`, `"A, rest"`, 32 entries, `[1,2]` | `E_CYCLE_INVALID` at `cycle` |
| C110 | unit | Cycle names matched case-insensitively with collapsed whitespace | True |

### C.12 Timed sets, beeps, bodyweight (`valid/timed-sets.json`, `valid/bodyweight.json`)
| ID | Type | Case | Expected |
|---|---|---|---|
| C111 | unit | `durationSeconds: "max"`, `"open"`, `"AMSAP"`, `"as long as possible"`, `"to failure"` | openDuration(min nil) |
| C112 | unit | `durationSeconds: "30+"` | openDuration(min 30) |
| C113 | unit | `durationSeconds: "forever"`, `"0+"`, `"30s"` | `E_DURATION_INVALID` |
| C114 | unit | Set-level `durationSeconds: "AMSAP"` under an exercise-level fixed 60 | That set is open; the others fixed 60 |
| C115 | unit | Fixed 45 s set, `warningBeep` missing or `true` | warningBeepSeconds 5 (10 %, rounded half up) |
| C115b | unit | Fixed 25 s → 3; 30 s → 3; 600 s → 60; 8 s → nil (under 10 s never warns) | As listed |
| C116 | unit | Exercise-level `warningBeep: 15`, set-level `5` on one set | 15 for the others, 5 for that set |
| C116b | unit | `warningBeep: false` | nil |
| C117 | unit | `warningBeep` given on a rep-based or open-duration set/exercise | nil + `W_WARNING_BEEP_IGNORED`; missing on those → nil, no warning |
| C117b | unit | `warningBeep: 45` on a 30 s set | nil + `W_WARNING_BEEP_IGNORED` |
| C118 | unit | `warningBeep: 0`, `-1`, `2.5`, `"soon"`, `86400` | `E_WARNING_BEEP_INVALID` |
| C119 | unit | `bodyweight: true` with no weight | flag true, weights nil |
| C120 | unit | `bodyweight: true` with `weight: 5` (exercise or set level) | weight nil + `W_BODYWEIGHT_WEIGHT_IGNORED` |
| C121 | unit | `bodyweight: true` with weighted drops | drop weights nil + `W_BODYWEIGHT_WEIGHT_IGNORED` |
| C122 | unit | `bodyweight: "yes"`, `1` | `E_BODYWEIGHT_INVALID` |
| C123 | unit | `bodyweight: false` with `weight: 10` | normal weighted exercise |
| C124 | unit | Drops on an open-duration set | `W_DROPS_IGNORED` |

### C.13 Rendering a plan back to JSON (D29, v1.1)
| ID | Type | Case | Expected |
|---|---|---|---|
| C40 | unit | Render every valid fixture with `PlanJSON.render` and import the result | No errors; the re-imported plan renders byte-identically, and its days, exercises, set counts, cycle and schedule all match. This fixpoint is what lets an edit go out through the real import pipeline instead of around it. A `warningBeep` of "off" must be written as an explicit `false`, since an absent field means the 10 % default |

## D. Import — Validate stage (limits, plan-wide)
| ID | Type | Case | Expected |
|---|---|---|---|
| D1 | unit | 32 days | `E_LIMIT_EXCEEDED` at `days` |
| D2 | unit | 31 days | Accepted |
| D3 | unit | 51 exercises in one day | `E_LIMIT_EXCEEDED` at `days[i].exercises` |
| D4 | unit | `days: []` | `E_NO_DAYS` |
| D5 | unit | A day with `exercises: []` | `E_NO_EXERCISES` at `days[i].exercises` |
| D6 | unit | Multiple errors in one plan | All reported, ordered by path; import blocked |
| D7 | unit | Errors and warnings together | Errors returned; warnings also present in the issue list |
| D8 | unit | Every fixture in `valid/` | Zero errors; warnings exactly as manifest says |
| D9 | unit | Every fixture in `invalid/` | The manifest's error code present, at the manifest's path when given |
| D10 | unit | Resulting `Plan` re-encodes and re-decodes to an equal value (round trip) | Equal |
| D11 | unit | Import is deterministic except UUIDs and `importedAt` | Two imports of the same text produce equal plans after zeroing those |

## E. Flattening a Day into Steps
| ID | Type | Case | Expected order (exercise.set) |
|---|---|---|---|
| E1 | unit | One exercise, 3 sets | 0.0, 0.1, 0.2; all isLastInRound |
| E2 | unit | Two ungrouped exercises, 2 sets each | 0.0, 0.1, 1.0, 1.1 |
| E3 | unit | Superset A: ex0 (3 sets), ex1 (3 sets) | 0.0, 1.0, 0.1, 1.1, 0.2, 1.2; isLastInRound only on ex1 steps |
| E4 | unit | Circuit of 3 exercises × 2 rounds | 0.0,1.0,2.0, 0.1,1.1,2.1 |
| E5 | unit | Group with 3/2 sets | 0.0,1.0, 0.1,1.1, 0.2; step 0.2 isLastInRound |
| E6 | unit | Ungrouped, group A ×2, ungrouped | 0.0…, then interleaved 1/2, then 3.x |
| E7 | unit | Empty day (shouldn't happen post-validation) | Returns [] without crashing |
| E8 | unit | Step indices are 0..N−1 contiguous; count = total sets | True for all fixtures |
| E9 | unit | 50 exercises × 50 sets | Completes in < 10 ms |
| E10 | unit | One exercise, 2 sets, 2 drops each | 0.0, 0.0.1, 0.0.2, 0.1, 0.1.1, 0.1.2; isLastInRound only on the .2 drops |
| E11 | unit | Superset A: ex0 (2 sets, 1 drop), ex1 (2 sets) | 0.0, 0.0.1, 1.0, 0.1, 0.1.1, 1.1; isLastInRound on 1.0 and 1.1 |
| E12 | unit | Three blocks | blockIndex 0,1,2 assigned; isLastInBlock true on exactly three steps, the last of each block |
| E13 | unit | Single exercise, single set, no drops | one step: isLastInRound, isLastInBlock both true |
| E14 | unit | Drop steps of a set are contiguous and follow their set | True for all fixtures |

## F. Rest at execution (SPEC §6.3)
| ID | Type | Case | Expected |
|---|---|---|---|
| F1 | unit | Log the last set of the last exercise | No rest; session completes |
| F2 | unit | Log a set not last in round (superset member 1 of 2) | Rest 0 → working(next) immediately |
| F3 | unit | Log last in round of group where member 1 has rest 60, member 2 has none | 60 |
| F4 | unit | Group where only member 2 has explicit rest 45 | 45 |
| F5 | unit | Group with no explicit rests, day default 80 | 80 |
| F6 | unit | Ungrouped set with rest 0 | working(next) immediately, no notification effect |
| F7 | unit | Log last set of exercise 0 while exercise 1 remains | `RestResolution.after` returns `.blockDone` (was called "transition" before v1.1) — see F9 |
| F8 | unit | Log the final pending step while an earlier pending step exists (user jumped ahead) | Rest starts; nextStep = the earlier pending step |
| F9 | unit | Log the last set of exercise 0 while exercise 1 remains | `.blockDone` (v1.1; was `.transition`); **behavior revised in v1.1**: the engine advances straight to `working(next)` instead of a separate phase — see G29/G49; the set's restSeconds unused |
| F10 | unit | Log the last step of a superset block (last round, last member) with another block after | `.blockDone` |
| F11 | unit | Log a main set that has drops | 0 (next step is the drop) |
| F12 | unit | Log the last drop of a set, more sets remain in the exercise | countdown of the set's rest |
| F13 | unit | Log the last step of the last block | session completes (no blockDone) |
| F14 | unit | Jumped ahead: log last step of block 2 while a pending step in block 0 remains | `.blockDone` (next step is in another block) |
| F15 | unit | (v1.1, D14) A block-ending log's effects | No `.transition` phase exists; phase → `working(next)` in the same event; `ActiveSession.blockDone` records `(finishedBlock, startedAt: now)`; no scheduleNotification effect |

## G. Session engine
| ID | Type | Case | Expected |
|---|---|---|---|
| G1 | unit | New session from a Day | steps all pending; phase working(0); effects [persist] |
| G2 | unit | logSet(0, 10 @ 60) | step0 logged with loggedAt=now; phase resting(endsAt=now+rest, next=1); effects contain scheduleNotification(endsAt, body mentions next exercise and "set 2 of") and persist |
| G3 | unit | logSet on an already-logged step | Overwrites result; behaves like a log (starts rest) |
| G4 | unit | editSet on a logged step during rest | Result updated; phase unchanged; no timer effects |
| G5 | unit | skipSet(0) | step0 skipped; phase working(1); no notification effect |
| G6 | unit | skipSet on the last pending step | completed; sessionCompleted effect |
| G7 | unit | skipExercise(e) with 2 pending and 1 logged step in e | The 2 pending → skipped; logged untouched; phase → next pending outside e |
| G8 | unit | jumpTo(5) during rest | cancelNotification; phase working(5); rest state cleared; lastRestEndedAt set |
| G9 | unit | jumpTo a logged step | phase working(that step) (edit mode in UI) |
| G10 | unit | adjustRest(+30) | endsAt += 30; effects cancelNotification then scheduleNotification(new endsAt) |
| G11 | unit | adjustRest(−30) when 20 s remain | endsAt ≤ now → rest ends: phase working(next); cancelNotification; no playAlert |
| G12 | unit | skipRest | cancelNotification; working(next); no playAlert |
| G13 | unit | restElapsed at exactly endsAt while foreground | playAlert; working(next); lastRestEndedAt = endsAt |
| G14 | unit | restElapsed observed 5 min late (foreground after background) | working(next); **no** playAlert; overrun computable as now − endsAt |
| G15 | unit | restElapsed while not resting | No-op, no effects except nothing (idempotent) |
| G16 | unit | logSet on step i where nextStep(after i) wraps to an earlier pending | resting with nextStep = earlier index |
| G17 | unit | nextStep when all pending are after i | First pending > i |
| G18 | unit | nextStep when none pending | nil |
| G19 | unit | finish with 3 pending | They become skipped; completed; endedAt=now; sessionCompleted |
| G20 | unit | finish with 0 logged | Engine reports `loggedCount == 0` so the UI can offer discard; no rotation advance if discarded |
| G21 | unit | renameExercise(1, "DB Bench") | session.exercises[1].name updated; targets and steps untouched; persist |
| G22 | unit | renameExercise to blank | Rejected (no change) |
| G23 | unit | Log timed set with duration result 40 of target 45 | result duration(40); rest starts normally |
| G24 | unit | Any event → last effect is persist | True for every event type |
| G25 | unit | Event sequence for a full 18-step workout | Ends completed, 18 logged, one notification scheduled per rest, one cancel per rest end |
| G26 | unit | Engine is a value type; applying events to a copy doesn't affect the original | True |
| G27 | unit | `elapsed(now)` = now − startedAt regardless of phase | True |
| G28 | unit | Session completed exactly when logging the last pending | endedAt == that loggedAt |
| G29 | unit | logSet on the last step of block 0 | **Revised in v1.1** (was a separate `transition(startedAt, nextStep, finishedBlock)` phase): phase → `working(first step of block 1)` in the same event; `active.blockDone == BlockDone(finishedBlock: 0, startedAt: now)`; `session.steps[nextStep].startedAt == now`; no scheduleNotification; persist |
| G30 | unit | dismissBlockDone (was continueTransition) | Clears `active.blockDone`; phase already `working(nextStep)`, so it is unchanged; no effects but persist |
| G31 | unit | dismissBlockDone when `blockDone` is nil | no-op |
| G32 | unit | jumpTo while `blockDone` is set | working(step); `blockDone` cleared |
| G33 | unit | skipExercise that ends a block with another block remaining | `blockDone` set for the finished block; phase already `working(next)` |
| G34 | unit | skipSet on the last step of a block | `blockDone` set, never a countdown |
| G35 | unit | ActiveSession with `blockDone` persisted and restored | `blockDone.startedAt` preserved; the "moving on" stopwatch continues from it |
| G36 | unit | `adviceForBlockJustFinished` while `blockDone` is set | equals ProgressionAdvice.evaluate for that block's exercise(s); `[]` once `blockDone` is nil |
| G37 | unit | Switch-day: `finishAndStart(day)` | old session completed (pending → skipped), cycle advanced, new session working(0) |
| G38 | unit | Switch-day: `discardAndStart(day)` | old session removed, cycle unchanged, new session working(0) |
| G39 | unit | Phase becomes working(i) for a rep step | `steps[i].startedAt = now` |
| G40 | unit | Phase becomes working(i) for a timed step | `startedAt` stays nil until `startTimer(i)` |
| G41 | unit | `startTimer` on a fixed 45 s set with warning 5 | startedAt = now; effects scheduleNotification("set-end", now+45) and scheduleNotification("set-warning", now+40) |
| G41b | unit | `startTimer` on a fixed set with warning nil | only "set-end" scheduled |
| G41c | unit | `startTimer` on an open set with minimum 30 | only scheduleNotification("set-minimum", now+30) |
| G42 | unit | `timerElapsed` after `startTimer` | logged duration 45, loggedAt = now, then the normal rest/transition rule; cancels "set-end", "set-warning", "set-minimum" |
| G43 | unit | `timerDone` at 30 s | logged duration 30 |
| G44 | unit | `startTimer` on an open set, `stopTimer` at 52.8 s | logged duration 52; no notification was scheduled |
| G45 | unit | `startTimer` on a rep step / `stopTimer` while not running | no-op |
| G46 | unit | Jump back to a logged rep step and re-log | startedAt reset on re-entry; new duration measured from re-entry |
| G47 | unit | Skipped step | startedAt kept, setSeconds nil |
| G48 | unit | Warning moment = endsAt − warningBeepSeconds; `beepDue(now)` reports warning / end / minimum exactly once each | True; nothing reported for moments that passed while backgrounded |
| G49 | unit | (D27, v1.1) editSet on a **skipped** step with a valid result | Result set; status → logged; `loggedAt` set to the edit's `now` (replacing the skip time); no phase change, no timer effects; advice recomputed |
| G50 | unit | editSet on a **pending** step | No-op (unchanged from v1: only logged or skipped steps can be edited) |
| G51 | unit | (D23, v1.1) undoLog on the step named by `active.lastCompletedStep` | Step → pending; result and `loggedAt` cleared; `startedAt` reset to `now`; phase → `working(step)`; `blockDone` cleared; the exercise's `advice` cleared if it now has a pending step |
| G52 | unit | undoLog on any step other than `lastCompletedStep` | No-op |
| G53 | unit | undoLog after the rest that followed the log it undoes has started | Cancels the pending `"rest-timer"` notification; phase → `working` |
| G54 | unit | undoLog on a step logged via `skipSet` | Same as G51 (skip and log are both undoable) |
| G55 | unit | undoLog on a drop step | Same as G51, for a `dropIndex > 0` step |
| G56 | unit | undoLog when the session is `.completed` | No-op (history editing, §4.10, covers correcting a finished session instead) |
| G57 | unit | `canUndo` | True only when `lastCompletedStep` names a non-pending step and the session isn't completed |
| G58 | unit | Log step A, then log step B, then undoLog(A) | No-op — A is no longer `lastCompletedStep` |
| G59 | unit | A v1 `ActiveSession` file whose `phase` is the old `.transition(startedAt, nextStep, finishedBlock)` | Decodes without throwing: `phase == .working(step: nextStep)`; `blockDone == BlockDone(finishedBlock: finishedBlock, startedAt: startedAt)` |

| G61 | unit | (D28, v1.1) Do later on an exercise with sets left | Its whole block's steps move after the day's last pending step; `blockIndex` is unchanged, and the Overview orders blocks by position so the new order shows |
| G62 | unit | (D28, v1.1) Do later on a partly-done exercise | The logged sets move with it and keep their results; the undo target follows its step through the move |
| G63 | unit | (D28, v1.1) Do later during a rest, or with a block-done strip showing | The rest is cancelled (no stale notification) and the strip is cleared; work resumes on the next pending step |
| G64 | unit | (D28, v1.1) Do later when it would change nothing | A no-op: nothing pending in that block, nothing pending outside it, a one-block superset day, or a completed session |

## H. Rest timer, notifications, audio (UI + manual)
| ID | Type | Case | Expected |
|---|---|---|---|
| H1 | ui | Start rest 90 s | Display 1:30 counting down each second |
| H2 | ui | +30 twice, −30 once | Display reflects +30 net; notification rescheduled (assert via a mock notification center in engine tests G10) |
| H3 | manual | Lock phone during 90 s rest | Notification arrives at the right second, with the next exercise in the body |
| H4 | manual | Skip rest while locked-notification pending, then unlock | No stale notification fires later |
| H5 | manual | Background for 3 min mid-rest, return | Step card shows next step with overrun "+1:30" |
| H6 | manual | Kill the app during rest, relaunch, Resume | Rest resumes with correct remaining (or overrun) from `endsAt` |
| H7 | manual | Notification permission denied | Foreground alerts still work; one-time banner shown; Settings row shows "Off · Open Settings" |
| H8 | manual | Phone on silent, sound on, no headphones | Beep is audible (playback category) |
| H9 | manual | Music playing in headphones | Music keeps playing; beep ducks it briefly; music resumes at full volume |
| H10 | manual | Sound off | No audio session activation (music never ducks) |
| H11 | manual | Vibration on, phone face down on bench | Haptic felt at zero |
| H12 | manual | Two rests in a row quickly (log, skip rest, log) | Only one pending notification at any time |
| H13 | manual | Rest of 10 minutes | Notification fires at 10:00, display shows m:ss throughout |
| H14 | manual | Incoming phone call during rest | Notification still delivered as banner |
| H15 | manual | Timed set countdown 45 s, tap Done at 30 s | Logs 30; rest begins |
| H16 | manual | Timed set countdown reaches zero while locked | Notification "Time!"; on return the logged duration is 45 and rest is running/overrun |
| H17 | ui | Low Power Mode | Countdown still accurate (Date-based) |
| H18 | manual | Change device clock forward during rest | Rest ends immediately on next tick; no crash (accepted behavior) |
| H19 | manual | Fixed 45 s plank, default warning | Short quieter beep at 40 s, final beep at 45 s, nothing else |
| H20 | manual | Open-duration dead hang with "30+" | One beep at 30 s; Stop logs the seconds; no beep without a minimum |
| H21 | manual | Lock the phone at 12 s of a 45 s set | "5 s left" notification at 40 s, "Time!" at 45 s; on unlock nothing replays |
| H22 | manual | Sound off, vibration on, timed set | Light haptic at the warning and a stronger one at the end; no audio session activation |
| H23 | manual | Tap Done at 30 s of a 45 s set | Neither the warning nor the end notification fires later |
| H33 | manual | (D24, v1.1) Launch with `-uiReadOnlyStore`, start a workout and log a set | "Couldn't save the workout…" appears **over the workout screen** with Retry — an alert attached only to the view behind the cover would show nothing; the set stays on screen; relaunching without the argument and tapping Retry saves it |
| H24 | manual | (D22, v1.1) Minimize mid-rest, lock the phone, wait past the rest notification, reopen and Resume | The notification fires at the right second; Resume returns to the same step with the strip already reading the overrun, and no stale rest notification fires afterwards |

## I. Prefill and "last time" (SPEC §6.5)
"Last" below = most recent completed session containing the exercise in the same units.
| ID | Type | Case | Expected |
|---|---|---|---|
| I1 | unit | No history, target 8–12 @ 60 | reps 8, weight 60 |
| I2 | unit | No history, fixed 10, no weight | reps 10, weight empty |
| I3 | unit | Last: set k = 10 @ 62.5; target 8–12 @ 60 | weight 62.5, reps 10 (last achieved, weight matches) |
| I4 | unit | Last: set k = 14 @ 60; target 8–12 @ 60 | reps 14 (last achieved wins even above the range) |
| I5 | unit | Last had only 2 sets, current set index 3 | weight = last logged weight of that exercise; reps = last logged reps of it |
| I6 | unit | Current session set 0 logged @ 65; last session set 1 was 10 @ 60; set 1 prefill | weight 65 (current session); reps = target min (weight differs from last's set 1 weight) |
| I7 | unit | Last in lb, current plan kg | history ignored; target values used |
| I8 | unit | A session that is in progress (not completed) | Ignored |
| I9 | unit | Newest session has the exercise fully skipped | Falls through to the older session |
| I10 | unit | "bench press" vs history "Bench  Press" | Matches |
| I11 | unit | AMRAP target, last = 12 @ 0 (bodyweight), prefilled weight empty | reps 12 (nil weights count as equal) |
| I12 | unit | AMRAP target, no history | reps empty; Log set disabled until typed |
| I13 | unit | Timed target 45, last = 40 s | seconds field 40; no history → 45 |
| I14 | removed (v1.1) | **D11 revised**: the v1 dynamic rule ("changing weight before touching reps re-prefills reps from the target; the RepsDraft API this needed is gone") was removed in v1.1 — see I38. Was: "User changes weight 60 → 62.5 before touching reps (last was 10 @ 60, target 8–12)" → "reps re-prefills to 8". |
| I15 | removed (v1.1) | Same removal as I14. Was: "Then changes weight back to 60" → "reps back to 10". |
| I16 | removed (v1.1) | Same removal as I14. Was: "User edits reps to 11, then changes weight" → "reps stays 11". |
| I17 | unit | Tapping "Suggested: 62.5" chip | weight 62.5; reps → target min via I14 |
| I18 | unit | "Last time" line, all weights equal, current set index 1 | "10, **10**, 8 @ 60 kg" (bold marks index 1) |
| I19 | unit | "Last time" line, weights differ | "10@60, **10@60**, 8@65 kg" |
| I20 | unit | "Last time" line, no weights | "10, 10, 8" |
| I21 | unit | "Last time" line, skipped set in the middle, current index 1 | "10, **–**, 8 @ 60 kg" |
| I22 | unit | Current set index 3, last had 3 sets | nothing bold |
| I23 | unit | "Last:" weight line under the weight field | "Last: 60 kg"; absent with no history |
| I24 | unit | Suggested chip appears only when the last session stored advice for this exercise | True; `.increase(to:)` shows the number, `.increaseLoad` shows "Add load" with no chip |
| I25 | unit | Rename exercise mid-session ("Bench" → "DB Bench") | Later sets prefill from "DB Bench" history |
| I26 | unit | Deleted session | No longer used for prefill |
| I27 | unit | Edited past session value | New value used for prefill |
| I28 | unit | Bodyweight exercise, last = 12 reps, no weight | reps 12, weight empty, "Last: –" line hidden |
| I29 | unit | Drop prefill: last session drop (k,1) = 8 @ 15 | weight 15, reps 8 |
| I30 | unit | Drop prefill, no history, drop target weight nil, previous step logged @ 20 | weight 20 (user taps −), reps empty (AMRAP) |
| I31 | unit | "Last time" line with drops: sets 10 (drops 8, 6), 10, 9 | "10↓8↓6, 10, 9 · 60 kg" (per-set weights shown when the drops' weights differ) |
| I32 | unit | Bold in "Last time" for a drop step (k=0, drop 1) | The "8" inside "10↓**8**↓6" is bold |
| I33 | unit | Open-duration set, last session 52, 48 s | No prefill; "Last time: 0:52, **0:48**" |
| I34 | unit | Bodyweight exercise | Weight prefill nil and the weight row is not rendered (view model exposes `showsWeight = false`) |
| I35 | unit | (D11 v1.1) 50 → 60 → 70 kg pyramid (`hasVariedTargets == true`); log set 1 at 50 kg | Set 2 prefills 60 kg, set 3 prefills 70 kg — never 50 |
| I36 | unit | A straight exercise (uniform target weight) | `hasVariedTargets == false`; carry-forward within the session is unchanged from v1 (I2's behavior) |
| I37 | unit | Varied pyramid with last-session history logged at 52.5 / 62.5 / 72.5; log this session's set 1 at 50 kg | Set 2 prefills 62.5 kg (last session's own set 2), set 3 prefills 72.5 kg — not carried from set 1 |
| I38 | unit | (D11 v1.1) Reps are computed once when a step's card loads | No API exists to re-prefill reps from a later weight edit (`RepsDraft`/`Prefill.draft` removed); the suggestion chip (§6.11) is unaffected — see the retained assertion in I39 |
| I39 | unit | Suggestion chip still works after the I14–I16 removal | Last session's `advice` still produces `suggestedWeight` and an unaffected `weight` prefill |
| I40 | unit | (v1.1, D22) `StepCard.progress` | "Exercise 2 of 5 · Set 2 of 3" for a plain exercise; "· drop 1 of 2" appended for a drop; "A · round 2 of 3 · Incline Press" for a superset member |
| I41 | unit | (v1.1, D22) `StepCard.setRows` for a straight exercise | One row per set of that exercise, in order, with `isCurrent` true only on the given step; logged rows show the result, pending rows the target, skipped rows "skipped" |
| I42 | unit | `StepCard.setRows` for a superset member | Only the current round's members (one row per exercise sharing that block and set index), not every round |
| I43 | unit | (v1.1, D14) `StepCard.blockDoneLine` for a finished block with advice | "<exercise> done · <duration>" plus the progression message; `nil` when the block has no identifiable exercise |

## J. Stats (SPEC §6.7)
| ID | Type | Case | Expected |
|---|---|---|---|
| J1 | unit | 3 sets 10@60, 10@60, 8@65 | volume 1720 |
| J2 | unit | Sets without weight | contribute 0 |
| J3 | unit | Timed sets with weight | contribute 0 |
| J4 | unit | Skipped sets | excluded from volume and logged count; included in total |
| J5 | unit | Best set among 100×5, 100×3, 95×8 | 100 × 5 |
| J6 | unit | Best set with no weights | most reps |
| J7 | unit | Best set with only timed sets | none (nil) |
| J8 | unit | Duration | endedAt − startedAt; a session crossing midnight still grouped under start date |
| J9 | unit | Summary comparison when exercise has no prior session | `ExerciseComparison(headline: "First time", rows: [])`. **Rewritten in v1.1's R4**: it used to return one raw string, "10, 8@60 · last 10, 9@60 · kg", which printed both sessions and left the reader to subtract |
| J10 | unit | History list per-session volume in lb and kg sessions | Each shows its own unit; no cross-unit totals anywhere |
| J11 | unit | Exercise duration, first block: session started 10:00:00, its last step logged 10:09:40 | 9:40 |
| J12 | unit | Exercise duration, second block: previous block's last log 10:09:40, this block's last step 10:17:00 | 7:20 (rest before the block counts toward it) |
| J13 | unit | Block durations across a completed session | Sum to session duration (±1 s rounding) |
| J14 | unit | Block with pending steps | Duration nil (not finished) |
| J15 | unit | Block whose steps were all skipped | Duration nil; skipped steps still carry `loggedAt` |
| J16 | unit | Superset block A/B, 3 rounds | One duration for the block, not per exercise |
| J17 | unit | `ExerciseHistory.series("Bench Press")` over 3 sessions (one lb, two kg), units kg | 2 points, oldest first, each with sets, topWeight, topSetReps, volume |
| J18 | unit | series point for session with sets 10@60, 8@65, 6@65 | topWeight 65, topSetReps 8, volume 1510 |
| J19 | unit | series on 1000 sessions | < 50 ms |
| J20 | unit | series for an exercise with only timed sets | Points exist; topWeight nil; volume 0; topSeconds = longest set |
| J21 | unit | Set seconds: startedAt 10:00:00, loggedAt 10:00:34.9 | 34 |
| J22 | unit | Set seconds for a step with no startedAt (old data) | nil, rendered as "–" |
| J23 | unit | Average set time on Summary | Mean of non-nil set seconds over logged steps |
| J24 | unit | series point `setSeconds` | One entry per set in order, nil for skipped |

| J25 | unit | (v1.1) `SessionStats.comparison` for the comparable, non-comparable, varied-weight and first-time cases | Same weight → "2 more reps at the same weight"; a moved weight → "+2.5 kg", plus ", 1 fewer rep" when the reps moved too; identical → "Same as last time"; bodyweight → reps alone; timed → "5 s longer held"; weights that varied within the session → a volume headline and one "10 @ 60 → 10 @ 62.5" row per set; no prior session → "First time" |

| J26 | unit | (D30, v1.1) `SessionStats.personalRecords` | A set that beats every earlier logged set of that exercise is a record; equalling it is not; a session that sets two records marks both; the first session ever sets none |
| J27 | unit | (D30, v1.1) Records across units and statuses | A session in other units is not history for the comparison (D10); a skipped set is never a record; bodyweight compares reps and timed work compares seconds held |
| J28 | unit | (D30, v1.1) History's exercise search, and the chart's data | Search matches on normalized name, most recently trained first, de-duplicated; the chart plots only points that have a weight, so a bodyweight exercise gets no chart rather than a flat line at zero |

## P. Progression advice (SPEC §6.11)
weightStep = 2.5 unless stated. Range 8–12, 3 sets, all @ 60 unless stated.
| ID | Type | Case | Expected |
|---|---|---|---|
| P1 | unit | 12, 12, 12 | `.increase(to: 62.5)` |
| P2 | unit | 12, 12, 11 (one rep short overall) | `.increase(to: 62.5)` (tolerance 1) |
| P3 | unit | 12, 11, 11 (two short) | nil |
| P4 | unit | 8, 8, 8 (floor exactly) | nil |
| P5 | unit | 8, 8, 7 (below floor by one) | `.decrease(to: 57.5)` |
| P6 | unit | 5, 5, 5 | `.decrease(to: 57.5)` |
| P7 | unit | 12, 12, 5 (total 29 ≥ floor 24) | nil |
| P8 | unit | Weights differ: 12@60, 12@60, 12@65 | nil (no single working weight) |
| P9 | unit | Bodyweight, 12, 12, 12 | `.increaseLoad` |
| P10 | unit | Bodyweight, 6, 6, 6 | `.decreaseLoad` |
| P11 | unit | No repRange | nil |
| P12 | unit | Timed sets | nil |
| P13 | unit | 12, 12, skipped | Evaluates on 2 sets: achieved 24 ≥ 24−1 → `.increase(to: 62.5)` |
| P14 | unit | All sets skipped | nil |
| P15 | unit | One set, 12 | `.increase` |
| P16 | unit | One set, 7 | `.decrease` |
| P17 | unit | Weight 2 with step 2.5, below floor | `.decrease(to: 0)` (clamped) |
| P18 | unit | Weight step 5 (lb plan) | `.increase(to: 65)` from 60 |
| P19 | unit | Advice is stored on the completed session's exercise | Present after completion; nil when none |
| P20 | unit | Editing a past session's reps re-evaluates advice | Updated |
| P21 | unit | Advice evaluated when the exercise's last step is logged mid-session | Rest overlay text includes it; engine exposes `adviceForBlockJustFinished` |
| P22 | unit | Message text for increase, kg | "All sets hit the top of 8–12. Try 62.5 kg next time." |
| P23 | unit | Message text for decrease | "Below 8–12 across 3 sets. Try 57.5 kg next time, or keep 60 kg and build up." |
| P24 | unit | Range 10–10 (single number), 10, 10, 10 | `.increase` |
| P25 | unit | Main sets 12, 12, 12 with drops 8, 6 each | `.increase` (drops ignored) |

## S. Home sparkline — **removed in v1.1's R3**

The sparkline, `HomeMetric` and SPEC §6.13 went together: a chart whose metric changed on an
undocumented tap was undiscoverable rather than quiet, and `HomeActivity.line` (O66) replaced it.
These rows are kept as the record of what was tested and then deleted; **none of them is a `unit`
case any more**, and nothing implements them.

| ID | Type | Case | Expected |
|---|---|---|---|
| S1 | removed | duration, sessions on 3 of the last 7 days | 7 values; 4 nil; minutes for the rest |
| S2 | removed | Two sessions on one day, duration | summed |
| S3 | removed | volume with a lb session in a kg window | lb session excluded |
| S4 | removed | avgWeight | mean over weighted rep-based steps of that day's sessions |
| S5 | removed | avgReps over rep-based steps including drops | mean |
| S6 | removed | exercises = blocks with ≥ 1 logged step | count |
| S7 | removed | Caption for duration, avg 52 | "Workout length · last 7 days · avg 52 min" |
| S8 | removed | Caption for volume | "Volume · last 7 days · total 12,400 kg" |
| S9 | removed | No sessions in the window | all nil; caption "No workouts in the last 7 days" |
| S10 | removed | Window is the last 7 calendar days ending today (injected), local time zone | Sessions 8 days ago excluded; today included |
| S11 | removed | Tap cycles metrics in enum order and wraps; persisted in Settings | True |
| S12 | removed | A session crossing midnight counts on its start day | True |

## Q. v1.2 — the code-health defects (V1)

Each row is a defect the 2026-09-07 review found, with the test that would have caught it.
`JimmsBroTests/DefectFixesTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q1 | unit | (v1.2) A no-op rename of a superset member, applied through `PlanEdit` | The between-round rest is unchanged; `groupRestSeconds` survives the render/re-import that every edit is |
| Q2 | unit | (v1.2) Every `PlanEdit.Operation` applied to a plan with a superset | None of them changes the round rest |
| Q3 | unit | (v1.2) `setRest` on a superset member | Changes the round rest the whole group shares — the value rest resolution actually reads — not only the per-set value nothing in a group reads |
| Q4 | unit | (v1.2) `PlanJSON.render` for an ungrouped exercise | No exercise-level `restSeconds`; only a group member carries the round rest there |
| Q5 | unit | (v1.2) `setWorkWeight` | Takes effect but emits no `.persist`; the next log carries it to disk. Typing "62.5" is no longer four writes of `active-session.json` |
| Q6 | unit | (v1.2) Decoding a `Phase` payload this version does not know | Throws, so the file is set aside as corrupt rather than silently read as a completed workout; `working` and v1's `transition` still decode |
| Q7 | unit | (v1.2) `exportData` / `readBackup` / `restore` over a store holding an undecodable file | The file is reported but **not** renamed aside; a real `load` still sets it aside and names it |
| Q8 | unit | (D24, v1.2) Retry after the alert's dismissal has cleared `saveFailure` | The captured failure is retried and the value actually reaches disk |
| Q9 | unit | (D31, v1.2) The restore failure message | **Replace all** says what it had already cleared; only **Merge** may say nothing you had was changed |
| Q10 | ui | (v1.2) Hold − or + on the reps or weight stepper | The value keeps changing while the finger is down, and stops when it lifts |
| Q11 | manual | (v1.2) `swift test` from a clean checkout | Compiles and runs the Core suite |

### V2 — schema durability and one definition per rule

`JimmsBroTests/StoreMigrationTests.swift`. The frozen files live in `examples/store/v1/` and are
what v1.1 actually wrote; they are never regenerated to make a test pass.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q12 | unit | (v1.2) Decode `examples/store/v1/settings.json` | Every setting v1.1 held comes back |
| Q13 | unit | (v1.2) Decode `examples/store/v1/plans.json` | The plan, its active id, its superset's `groupRestSeconds`, and it still flattens into a runnable session |
| Q14 | unit | (v1.2) Decode `examples/store/v1/session.json` | Logged and skipped sets, results and set durations |
| Q15 | unit | (G59, v1.2) Decode `examples/store/v1/active-session.json` | Resumes mid-rest with its next step, work weight and undoable step |
| Q16 | unit | (v1.2) A file missing every defaulted key, and one missing an identity key | The first decodes to defaults (a plan with no cycle repeats its days in order); the second throws, so §8.3 still sets it aside |
| Q17 | unit | (v1.2) `fileVersion` 0, 1 and 2 | A reader reads its own version and older; only a newer file is refused |
| Q18 | unit | (v1.2) A whole store of v1.1 files through `Store.load` | Loads with `corruptFiles` empty |
| Q19 | unit | (v1.2) `AlertIdentifier` | Each id carries its own title and sound; only the warning uses the bundled sound; the engine can no longer spell one wrong |
| Q20 | unit | (v1.2) `SessionBlocks` | One grouping rule for the Overview and Session detail: blocks ordered by where their steps sit, names de-duplicated by §6.9's matching, rows named only in a superset |
| M9 | unit | (v1.2) `Prompts.planTemplate` and `fixTemplate` | Equal, character for character, to the fenced blocks of `docs/PROMPT.md`; the example JSON appears once in the source and still imports cleanly |

### V3 — warm-up, the walk between exercises, and the stage

`JimmsBroTests/WarmUpAndTransitionTests.swift`. Every row came from the owner using v1.1 on the
phone: the workout did not say where in it you were, there was no warm-up, and the gap between
two exercises was given no time at all.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q21 | unit | (D32, v1.2) Start a session with `warmUpSeconds = 300` | Phase is `resting(kind: .warmUp, nextStep: 0)`, ending 5 min out, with its own scheduled alert |
| Q22 | unit | (D32, v1.2) −30 / Skip / log during a warm-up | Adjusting keeps the kind; Skip goes to the first set; logging out of it logs the set, exactly as any other rest |
| Q23 | unit | (D32, v1.2) A warm-up that runs out | Becomes the first set, alerts at zero, and logs nothing — a warm-up is not a set |
| Q24 | unit | (D32, v1.2) `warmUpSeconds = 0` | Starts on the first set with nothing to schedule: v1.1 exactly |
| Q25 | unit | (D33, v1.2) Log a block's last set | A `betweenExercises` rest of `transitionRestSeconds`, with the next exercise already on screen, −30 / +30 / Skip, and the finished block's line on the strip. *(v1.10, D82: the strip counts up — 0:05 — beside a ring of 120, names the next exercise, keeps the block's line as its title, and has no −30 / +30 / Skip; TP20)* |
| Q26 | unit | (D33, v1.2) **Skip** a block's last set | Still gets the walk; a skipped set mid-block still gets no rest |
| Q27 | unit | (D33, v1.2) `transitionRestSeconds = 0` | The v1.1 block-done strip with its count-up, and no countdown. *(v1.10, D82: the count-up is the strip's figure, 0:42, and the ring is full; the model is given the engine's `walk`)* |
| Q28 | unit | (D33, v1.2) A rest between sets | Still resolved from the set (§6.3), not from the new setting |
| Q29 | unit | (D34, v1.2) `WorkoutStage` through a whole session | Warm-up → Exercise 1 of 2 · Set 1 of 3 → Resting → Between exercises, each named, and each break flagged as one |
| Q30 | unit | (D34, v1.2) `WorkoutStage.progress` | Counts logged **and** skipped sets over the day's sets, so the bar moves within a long exercise |
| Q31 | unit | (v1.2) A v1.1 `RestState` with no `kind` | Decodes as `betweenSets`, which is the only thing it could have been |
| Q32 | ui | (v1.2) The workout header | Names the stage above a progress bar; the stage is accented while you are in a break and reads in the reserved green while you are working |
| Q33 | ui | (v1.2) Settings | **Warm-up** and **Between exercises** rows read in minutes and say "Off" at 0; **Smallest change** says what suggestions are rounded to |

### V4 — a weight you can actually load, and a suggestion per set

`JimmsBroTests/SuggestionTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q34 | unit | (D35, v1.2) `WeightRounding.snap` | 134 → 135 on a 5 lb grid, 61 → 60 on 2.5 kg, never below zero, and unchanged when the increment is 0 ("the equipment can make anything") |
| Q35 | unit | (D35, v1.2) `heavier`/`lighter` | Always move: 132 + 2.5 rounds *down* to 130 on a 5 lb grid, so it goes to 135 instead. Never past zero |
| Q36 | unit | (D35, v1.2) Three sets of 8 at 132 lb, top of 6–8, 5 lb grid | `.increase(to: 135)` — never 134. And 61 kg below the range gives `.decrease(to: 57.5)` |
| Q37 | unit | (D35, v1.2) − and + | From a loadable weight, one step, rounded onto the grid; from an off-grid weight (134 lb), the first tap lands on the grid — 135, not 140 |
| Q38 | unit | (D36, v1.2) A set with no history | "Try 8 × 60 kg", reason "The plan's target" |
| Q39 | unit | (D36, v1.2) A set done before, no advice | Repeats last time's weight and says "Last time 10 × 70 kg" |
| Q40 | unit | (D36, v1.2) A set whose exercise earned advice | Advice wins, and the reason names the rule: "You hit the top of 8–12 last time" |
| Q41 | unit | (D35/D36, v1.2) Stored advice of 61 kg on a 2.5 kg grid | Snapped to 60 on the way out — a suggestion stored by another version or another setting is still made loadable |
| Q42 | unit | (D36, v1.2) A timed set | Suggested in seconds, with no reps and no weight |
| Q43 | ui | (D36, v1.2) The suggestion chip | Reads "Try 8 × 62.5 kg" with its reason beneath; one tap fills in **both** numbers |

### V5 — an anchored rotation, and a calendar you can read

`JimmsBroTests/ScheduleAnchorTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q44 | unit | (D37, v1.2) `PlanSchedule.entry` around its anchor | The anchor day is the one that was done; the cycle runs forward and backward from it |
| Q45 | unit | (D37, v1.2) **Miss three days in a row** | Every other day says exactly what it said before — the compounding is gone |
| Q46 | unit | (D37, v1.2) Finish a workout | Re-anchors, once, to the day it was actually done; the following days follow from there |
| Q47 | unit | (D37, v1.2) `PlanSchedule.next` | The next training day at or after today, never the one just done, and it says which date |
| Q48 | unit | (D37, v1.2) Home's card and the month grid | Both read `PlanSchedule.next`, so the day named on the card is the day ringed on the grid |
| Q49 | unit | (D37, v1.2) A training day with no session on it | Reported as "Pull was due Monday"; nothing is reported when you trained that day |
| Q50 | unit | (D37, v1.2) A plan that predates anchors | Anchored to the day of its most recent completed session — or today when it has none — once, and never again |
| Q51 | unit | (D38, v1.2) `CalendarText.label` | Names the day, cut to fit a cell; a rest day has no label, which is what makes the gap visible |
| Q52 | unit | (D38, v1.2) `CalendarText.spoken` | One sentence per cell: "Monday 7 September. Planned: Pull" |
| Q53 | ui | (D38, v1.2) The week strip | Finished days filled in the reserved green with what was done, planned days outlined with what is coming, rest days a dash |
| Q54 | ui | (D37, v1.2) A rotation whose next day is not today | The card reads "Rest day", "Push is next, Tue" and **Start Push early**, matching the grid |

### V6 — what a workout was, and what a run of them adds up to

`JimmsBroTests/MetricsTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q55 | unit | (D39, v1.2) `SessionMetrics.of` a 30-minute session | Duration, working and resting time with their share, sets, volume, reps, heaviest set, average set |
| Q56 | unit | (D39, v1.2) A session with a skipped set | "2 of 3" with "1 skipped", and the volume counts only what was logged |
| Q57 | unit | (D39, v1.2) A bodyweight, timed session | No volume and no reps at all — not "0 kg" — and time under tension instead |
| Q58 | unit | (D39, v1.2) A session that beat its history | A personal-record count, naming the exercises that set them |
| Q59 | unit | (D39, v1.2) `TrendMetrics.summary` over 30 days | Workouts and workouts-a-week, time trained and average length, volume, sets, most trained, all-time count; nothing at all reports nothing |
| Q60 | unit | (D39, v1.2) `TrendMetrics.streakWeeks` | Consecutive calendar weeks with at least one workout; a gap ends it; a week with none is zero |
| Q61 | ui | (D39, v1.2) Session detail | Leads with the Metrics section; every value has a label and, where it needs one, a note |
| Q62 | ui | (D39, v1.2) History → **Metrics** | 7 / 30 / 90 day windows, the numbers, and the workouts that produced them |
| Q63 | ui | (D39, v1.2) Home's calendar | Tapping a finished day shows its line; the line itself opens the workout |

### V7 — the Lock Screen and the Dynamic Island

`JimmsBroTests/ActivityTests.swift`. ActivityKit is behind `ActivityPresenting`, so all of this
is testable without a phone; Q71–Q73 need the device and live in `DEVICE_CHECKLIST.md`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q64 | unit | (D40, v1.2) A warm-up | The activity is a countdown titled "Warm-up", with the first exercise named under it |
| Q65 | unit | (D40, v1.2) Working, then resting | Working shows the exercise and no timer; logging turns it into a countdown and moves the progress |
| Q66 | unit | (D40, v1.2) A running timed set | Counts up from `startedAt`; a fixed duration also carries its end, an open hold does not |
| Q67 | unit | (D40, v1.2) A finished session | No activity at all |
| Q68 | unit | (D40, v1.2) Start a workout, then finish it | One activity started; ended exactly once when the workout ends |
| Q69 | unit | (D40, v1.2) Five seconds of ticks with nothing changing | Nothing pushed — the system draws the countdown itself |
| Q70 | unit | (D40, v1.2) Discard a workout | The activity ends; a countdown for a workout that no longer exists is worse than none |
| Q71 | manual | (D40, v1.2) Lock the phone mid-rest | The countdown is on the Lock Screen and stays right without opening the app |
| Q72 | manual | (D40, v1.2) The Dynamic Island | Compact, expanded and minimal all show the timer; the expanded view shows the set line and progress |
| Q73 | manual | (D40, v1.2) Live Activities turned off in iOS Settings | The app is unaffected and shows nothing on the Lock Screen |






## W. v1.3 — the Island, changing an exercise, JSON edits, history as CSV, Progression

`docs/ITERATION_4_PLAN.md` is the plan; one subsection per milestone, added as it lands.

### X1 — a narrower Dynamic Island (D41)

`JimmsBroTests/ActivityTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W1 | unit | (D41, v1.3) `timerRange` for a rest, now and two minutes after it ended | Counts down from now to the end; once the end has passed it is a one-second range, never an inverted one |
| W2 | unit | (D41, v1.3) `timerRange` for a running open hold, and for a working state | Counts up from `startedAt` and is cut at 59:59 rather than running to the end of time; a working state has no range at all |
| W3 | manual | (D41, v1.3) The compact Dynamic Island during a rest and during a timed set | One symbol on the left, the timer on the right, no wider than a phone's own Timer; the expanded view is unchanged |

### X2 — changing an exercise mid-workout (D42)

`JimmsBroTests/ChangeExerciseTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W4 | unit | (D42, v1.3) Change an exercise before any of its sets, with a weight | Renamed in place: same exercise count, same step order and blocks, `substitutedFor` set, every target at the new weight, the card's prefill re-read |
| W5 | unit | (D42, v1.3) Change it after one set was logged, mid-rest | A second `SessionExercise` with `replaces` pointing back; the logged step keeps the old name, the pending steps take the new one; the rest is untouched; the rows show both, named |
| W6 | unit | (D42, v1.3) The substitute has its own history | Prefill, the card's weight, "last time" and the suggestion all read the substitute's last session, not the original's and not the plan's target |
| W7 | unit | (D42, v1.3) The header after a split | Still "Exercise 1 of 3 · Set 2 of 2"; the exercise's line ends "· was Bench Press"; no row repeats it. *(v1.10, D81: the Workout screen's ? leads with "was Bench Press"; `StepCard.targetLine`, the Overview's, still ends with it)* |
| W8 | unit | (D42, v1.3) Finishing the substitute at the top of the range | The substitute earns the increase; the original, with one set, earns nothing; the block-done line names the substitute |
| W9 | unit | (D42, v1.3) A superset member | Substituted alone; the group and the round are unchanged; the round's rows name all three |
| W10 | unit | (D42, v1.3) A blank name, an unknown index, a bad weight, the same name with no weight, nothing pending, a finished session | Each refused with no effects; the same name *with* a weight changes the remaining targets' weight and nothing else |
| W11 | unit | (D42, v1.3) The active session through the store's coder; a session exercise written before v1.3 | Round-trips with both new fields; the old one decodes with both nil |
| W12 | manual | (D42, v1.3) "···" → Change exercise during a rest | The sheet opens over the running rest; after Change, the card shows the new exercise with its own last time, and the rest is still counting |

### X3 — JSON edits at every size (D43)

`JimmsBroTests/JSONEditTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W13 | unit | (D43, v1.3) Every day and every exercise of every valid fixture, rendered as a fragment and spliced back over itself | The plan renders identically — the fragment renderer and the splice are exact inverses |
| W14 | unit | (D43, v1.3) One exercise replaced from compact JSON (`"sets": 5, "reps": 5`) | Five identical sets; neighbours, days, id, import date, cycle position and anchor unchanged; the plan's text is the canonical rendering |
| W15 | unit | (D43, v1.3) An exercise whose second set differs (`sets` as a list) | The sets keep their own weight and rest, and survive the structured editor's round trip |
| W16 | unit | (D43, v1.3) A fragment with `"reps": "eight"`; not JSON; `[1, 2]`; two exercises where one goes; a day with no exercises; an index off the end | Refused with `E_REPS_INVALID` at `days[0].exercises[1].sets[0].reps` ("Day 1, exercise 2, set 1"); `E_NOT_JSON`; `E_NOT_A_PLAN`; `E_EDIT_INVALID`; `E_NO_EXERCISES`; `E_EDIT_INVALID` — and the plan untouched |
| W17 | unit | (D43, v1.3) Add exercises: one at the end, two at the start from a fenced list with prose, a day pasted as exercises, an empty list, the blank template | Added where asked; a day adds its exercises and no day; `[]` refused; the template's blank name refused with "Every exercise needs a name" |
| W18 | unit | (D43, v1.3) Add days: a bare day; a whole plan holding two days, one unnamed; to a weekday plan without a weekday, then with a free one | Appended and added to the rotation's repeat block, named "Day N" if unnamed, the pasted plan's name ignored; `E_WEEKDAY_MISSING` at `days[n].weekday`; placed on its weekday in the derived cycle |
| W19 | unit | (D43, v1.3) Replace a day renamed, and unnamed | The renamed day keeps its place in the repeat block; the unnamed one keeps its old name, with no default-name warning |
| W20 | unit | (D37, v1.3) `cycleAnchor` through a plan edit and through Replace | Kept — v1.2 dropped it in both, and the next launch re-anchored the rotation to that day |
| W21 | manual | (D43, v1.3) Plan → exercise → **Edit as JSON**, make the second set heavier, Save; then day menu → **Add exercise**, Save with the blank name | The sets show "24 / 26 / 24 kg"; the blank name is refused with a sentence and the text stays in the sheet |

### X4 — history as a file another app can read (D45)

`JimmsBroTests/HistoryCSVTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W22 | unit | (D45, v1.3) `render` over three sessions: straight sets, one skipped set and a comma in the name, timed work | The exact header; one row per logged set, oldest first; the skipped set absent and the set order closed up; the name quoted; seconds and no reps for timed work; the unit last; "1h 5m" |
| W23 | unit | (D45, v1.3) `parse(render(history))` | The same workouts: names, starts to the second, units, every result, exercise order, duration to the minute, bodyweight where no set had a weight; and `ExerciseHistory.last` finds them |
| W24 | unit | (D45, v1.3) A Strong export, newer (comma, no unit) and older (semicolon, `Weight Unit`, `Workout Duration`) | Both read; the newer one's unit is the setting and is reported; 0 kg is no weight; "52m" and "1h 5m" become the duration |
| W25 | unit | (D45, v1.3) A Hevy export (`weight_kg`, "12 Jan 2024, 07:30", `end_time`, `set_type`, `superset_id`) | Reads in kg from the header; the duration from the end time; warm-up sets kept; columns this app has no use for ignored |
| W26 | unit | (D45, v1.3) No usable columns; an empty file; a file whose rows have a bad date, no exercise, no reps | `E_CSV_COLUMNS`; `E_EMPTY`; the good rows read and each bad one named by line (`W_CSV_ROW_SKIPPED`); a file with only bad rows is `E_CSV_NO_ROWS` |
| W27 | unit | (D45, v1.3) `new(_:against:)` and the summary | The same file twice adds nothing; the same minute with another name is new; the summary counts only what would be added |
| W28 | unit | (D45, v1.3) `Summary.text` | "2 workouts (6 sets) from Nov 12 to Nov 14 · 1 already here · weights read as kg"; one workout on one day says "on" |
| W29 | unit | (D45, v1.3) `AppModel.read(csv:)` then `importHistory` | Reading writes nothing; importing writes one file per session and no `saveFailure`; a second import adds nothing; the workout screen's prefill reads an imported session as last time; a non-history file fails with a sentence; `exportHistoryCSV` yields a file |
| W30 | manual | (D45, v1.3) Settings → **Export history (CSV)**, AirDrop it to the Mac and open it; then delete a workout in History and **Import history (CSV)** with that file | A spreadsheet shows one row per set with the columns named; the dialog says "1 workout … · N already here"; Import brings only the deleted one back |

### X5 — Progression (D44)

`JimmsBroTests/ProgressionTests.swift`; the prompt pin is in `PromptPinningTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W31 | unit | (D44, v1.3) `weekIndex` on the start day, day 6, day 7, day 27, day 28 and the day before the start | 0, 0, 1, 3, nil, nil; `isFinished` flips on day 28; the status reads "Week 2 of 4" then "Finished" |
| W32 | unit | (D44, v1.3) `apply` for a weight-and-range week, a weight-only week, `{}`, a per-set week, and a day with no entry | Only what the week says changes; a range also sets the rep range; a bodyweight exercise takes reps and no weight; `{}` touches nothing; the per-set week leaves the third set as the plan had it |
| W33 | unit | (D44, v1.3) `Session.start` in week 2, after the last week, and for a plan without one | Week 2's targets in the snapshot and the week stamped on the exercises it touched; the plan's own targets after the last week; nothing stamped without one |
| W34 | unit | (D44, v1.3) Prefill in week 2 when last time was heavier; after the last week; a bodyweight exercise in its week | The week's weight and reps, with "Last 70 kg" still said, and the chip "Try 8 × 62.5 kg — Week 2 of 4 of your progression"; last time wins again afterwards; nothing invented for a bodyweight AMRAP |
| W35 | unit | (D44, v1.3) A fenced reply with prose, a name the plan does not have, a lower-cased match, a weight on a bodyweight exercise, an unloadable 52 kg, a short list, `null`, an unknown field and per-set values | Three entries under the plan's own names; 52 → 52.5; the material warnings are exactly unmatched, weight-ignored and short; rounding, surrounding text and the unknown field are cleanup |
| W36 | unit | (D44, v1.3) Words; the prompt itself; `weeks: 0`; nothing matching; an entry with no name; `"reps": "eight"`; reps and a duration; a bare list of numbers; a number where a week goes | `E_NOT_JSON`, `E_PROMPT_PASTED`, `E_PROGRESSION_WEEKS_INVALID`, `E_PROGRESSION_EMPTY`, `E_PROGRESSION_EXERCISE_INVALID`, `E_REPS_INVALID` at `exercises[0].weeks[0].reps` ("exercise 1, week 1"), `E_TARGET_CONFLICT`, `E_PROGRESSION_EXERCISE_INVALID`, `E_PROGRESSION_WEEK_INVALID`; and the wrapper key, an inferred period, "55 kg" and "bw" are all read |
| W37 | unit | (D44, v1.3) The prompt for a plan with one session of history, with and without history | The marker, the period three ways, the increment, every exercise of every day as one line, the history block with the sets and the advice; no fence anywhere; under the bound; no history block when off; pinned to PROMPT.md §3 |
| W38 | unit | (D44, v1.3) A plan with a progression through the store's coder; the frozen v1.2 plans file; a session with a week; a structured edit; a JSON edit; Replace | Round-trips; the old file has none; the week survives; both edits keep it; Replace drops it |
| W39 | unit | (D44, v1.3) Home in week 2, after the last week, and with no progression | "· week 2 of 4" in the subtitle — the ···'s line "Week 2 of 4" in v1.8 (D69), and since v1.9 (D75) History's Progression row's (`ProgressionText.status`), "Finished" after the last week; `progressionFinished` afterwards; neither without one |
| W40 | manual | (D44, v1.3) Plans → a plan → **Progression**, pick 4 weeks, Copy prompt, paste it into a chatbot, paste its reply, Save; then start today's workout | The review shows every exercise's four weeks; Plan detail reads "Week 1 of 4"; Home's subtitle ends "week 1 of 4"; the first set's card shows the week's weight with the chip's reason naming the week |

## Y. v1.4 — a tap before its side effects, built-in plans, the introduction, the store

`docs/ITERATION_5_PLAN.md` is the plan; one subsection per milestone, added as it lands.

### Y1 — a tap's result before its side effects (D48)

`JimmsBroTests/ResponsivenessTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Y1 | unit | (D48, v1.4) `startDay` against a scheduler that never returns | While the first notification is still being held, the engine exists, `hasActiveSession` is true and `startedWorkouts` is already 1; releasing the scheduler finishes the start with the count unchanged |
| Y2 | unit | (D48, v1.4) A start refused mid-session; a switch; a session restored at launch | The refusal leaves the count alone; the switch counts; `load` with an active session on disk resumes it with the count at 0 |
| Y3 | manual | (D48, v1.4) Tap **Start** on the phone | The workout screen is up before the notification prompt or the Island appears; nothing waits on them |

### Y2 — built-in plans (D46)

`JimmsBroTests/BuiltInPlanTests.swift`, reading the files that ship from `JimmsBro/Resources`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Y4 | unit | (D46, v1.4) Every built-in plan through `PlanImport.run`, in kg and in lb | No errors and no warnings of either kind; the catalogue's four ids in order; each plan's name is the catalogue's; the plan takes the setting's unit; the build-your-own sentence names **Create with a chatbot** |
| Y5 | unit | (D46, v1.4) The repeat blocks | Whole weeks; training days per week equal the catalogue's; every day is in the block; Full Body and At Home run A B A then B A B over 14 days; Upper Lower is four days on seven; Push Pull Legs is Push Pull Legs twice on seven |
| Y6 | unit | (D46, v1.4) Every exercise of every plan | One kind of set per exercise; every rep exercise has a rep range and every set is that range; every hold is a fixed duration with the warning beep on and is bodyweight; no weight and no drops anywhere; At Home is entirely bodyweight; the gym plans flag only the plank, the pull-up and the knee raise |
| Y7 | unit | (D46, v1.4) The shape of every day | Five to seven exercises, 15–22 sets, rest never climbing through the day, the day opening on a big lift's rest, every rest 30–180 s, a note on every exercise under 500 characters, and the first note of every plan explaining the empty weight field |
| Y8 | unit | (D46, v1.4) Every exercise name across the four plans and the practice plan | One spelling per movement (compared with punctuation and case stripped), and more than thirty movements in all |
| Y9 | unit | (D46, v1.4) `Session.start` on every day, and `estimatedMinutes` | Every day flattens to one step per set; every day estimates between 35 and 65 minutes with the default settings; the plan's typical day is to the nearest five minutes and heads the summary line; v1.1's settings take exactly the warm-up and the walks off; an index off the end is nil |
| Y10 | unit | (D46, v1.4) `AppModel.loadBuiltInPlan` and `save(_:conflict:makeActive:)` | An unknown id is `E_NO_BUILT_IN` with a sentence; the empty card reads "Choose a built-in plan, or get one from a chatbot."; loading saves nothing; saving makes it active; saving again keeps both as "Full Body" and "Full Body (2)" without taking over; the card then reads "Full Body A" / **Start Full Body A**; a relaunch reads both plans back |
| Y11 | manual | (D46, v1.4) Home → **Choose a built-in plan** → At Home → Save plan → Start | The picker's rows show days, minutes and equipment; the review opens on the paragraph; Home names At Home A; the first card asks for reps only; the plan's minutes are about what the day took |

### Y3 — the introduction (D47)

`JimmsBroTests/IntroductionTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Y12 | unit | (D47, v1.4) `Introduction.pages` | Four pages in order, each with a symbol, a line and a paragraph of 80–400 characters; every name in `namedControls` appears in the copy; the three button titles |
| Y13 | unit | (D47, v1.4) Every control the intro names exists by that name | "Add plan" and "Start Push" (since v1.8, **Start Today's Push**) are the card's buttons; "Log set" is the workout's primary action; "Create with a chatbot", "History", "Progression" and "Choose a built-in plan" are read from the views' own source on the host routes (skipped on the simulator, like the prompt pins) |
| Y14 | unit | (D47, v1.4) `isDue` and `AppModel.introDue` | Due with no plans and not seen; not with a plan; not once seen; false before `load`; true on a fresh store; false after `markIntroSeen` and still false on relaunch; never true on a store with plans; true again after Delete all data |
| Y15 | unit | (D47, v1.4) `introSeen` on disk | Written and read back; the frozen v1.1 settings file decodes with it false and everything else intact; a file that says true reads true |
| Y16 | manual | (D47, v1.4) Delete the app, install, launch; then Settings → About → **How the app works** | The intro covers the tabs; swiping reaches four pages; **Choose a plan** lands on the built-in picker; after Cancel, Home is the empty card and the intro does not return on relaunch; the Settings row reopens it with **Done** |

### Y4 — ready for the store (D49)

Type **check** = a script in `tools/` that must exit 0; it runs on the host with no Xcode.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Y17 | check | (D49, v1.4) `python3 tools/check_release.py` | Exit 0: the icon is a 1024 × 1024 PNG of colour type 2 (no alpha); every `MARKETING_VERSION` is 1.4 and every `CURRENT_PROJECT_VERSION` is 1, and `docs/APP_STORE.md` says the same; `ITSAppUsesNonExemptEncryption = NO` is on both app configurations; the extension's Info.plist hard-codes no version; `docs/PRIVACY.md` carries an effective date and `docs/APP_STORE.md` exists; every catalogue id has `JimmsBro/Resources/<id>.json` and the project copies it |
| Y18 | check | (D49, v1.4) `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'` | Builds: nothing outside `#if DEBUG` refers to the screenshot hooks, the read-only store or the seeded launch arguments |
| Y19 | manual | (D49, v1.4) The TestFlight build on the phone | Installs from TestFlight; the icon is the barbell; Settings → About reads 1.4 (1); the device checklist is run against this build rather than a cable install |

## Z. v1.5 — clearer buttons, an effort target, a plan in several pastes, steps you earn, goals

`docs/ITERATION_6_PLAN.md` is the plan; one subsection per milestone, added as it lands.

### Z1 — clearer, not louder (D50)

`JimmsBroTests/ClarityTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Z1 | unit | (D50, v1.5) `PromptText` | Three sentences — four until v1.9, when the link's name went with the link (D75) — none empty; the step names the prompt and the reply, the footer says the app never talks to the chatbot, the row line names the chatbot and lifting |
| Z2 | removed | (D50, v1.5) `HomeStart.offersProgression` — removed with Today's offer in v1.9 (Q3, D75): History's Progression row is the way, and TQ22 pins the offer's absence | False with no plan, with a plan whose day has an exercise never logged, with a progression attached, and while a workout is running; true once every exercise on the day has a logged session; a second day's history does not count for the first |
| Z3 | unit | (D50, v1.5) The views that show the sentences | Add plan's and Progression's source reference `PromptText.copyStep` and `.mechanism`, History's `.progressionRow` (Plan detail's until D67), and Today's ··· draws Core's `alternative.title` — until v1.9 Home referenced `.planProgression` and Core's one list of ··· items offered it while D50 did, which D75 took out (TQ22) — read from the checkout on the host routes, skipped on the simulator |
| Z4 | manual | (D50, v1.5) Add plan and Plan detail on the phone | Copy prompt is the filled accent button beside the sentence; the footer is under the steps; the Progression row has its line and an accent chevron; Home shows **Plan a progression** only on a day whose every exercise has history, and not once one is attached (since v1.9, D75, not on Today at all: History's Progression row is the way) |

### Z2 — the effort target (D51)

`JimmsBroTests/InReserveTests.swift`; the four fixtures `valid/in-reserve.json`, `valid/in-reserve-alias.json`, `invalid/in-reserve-word.json` and `invalid/in-reserve-too-many.json` run through the manifest in `ImportTests`, with the `inReservePerSet` check.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Z5 | unit | (D51, v1.5) `inReserve` at exercise level, overridden on one set; `rir`; on a hold; a word; 25 | Sets carry 2, 2, 1; the alias reads; a hold takes seconds; the word and the number over 20 are `E_IN_RESERVE_INVALID` at the field's own path, with a sentence that says 0 to 20; a plan that says nothing has nil everywhere and shows nothing |
| Z6 | unit | (D51, v1.5) The card, its spoken form, the next line and the summary | "6–8 · 80 kg · 2 in reserve"; the spoken card says "2 in reserve"; "Next: … · 2 in reserve"; the summary says it once when every set agrees and not at all when they differ; a drop's target has none |
| Z7 | unit | (D51, v1.5) On disk | A set with `inReserve` round-trips through the store's coder; the frozen v1 plans and session decode with nil; a session started from the plan carries it in its snapshot |
| Z8 | unit | (D51, v1.5) `PlanEdit.setInReserve` | Every set takes the value and the plan re-imports; nil clears it; 21 is refused with `E_EDIT_INVALID`; the rendered JSON carries `"inReserve"` per set and imports back identically |
| Z9 | unit | (D51, v1.5) The prompts | The plan prompt carries the `inReserve` rule and no longer sends RPE to notes; the progression prompt's history line ends "· 2 in reserve" when every logged set of the exercise had it, and says nothing when the plan did not |
| Z10 | manual | (D51, v1.5) A plan with `"inReserve": 2` on the phone | The card reads "… · 2 in reserve" under the exercise, the review and Plan detail say it once per exercise, and the edit sheet's In reserve field changes it |

### Z3 — a plan in several pastes (D52)

`JimmsBroTests/DraftPlanTests.swift`, and the two new pins in `PromptPinningTests`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Z11 | unit | (D52, v1.5) `PlanDrafting.outline` on an outline, a whole plan, the prompt, not JSON, no days, an unknown cycle day | Three empty slots with the outline's name, days and block; a whole plan arrives with every slot filled; `E_PROMPT_PASTED`, `E_NOT_JSON`, `E_NO_DAYS`, `E_CYCLE_UNKNOWN_DAY`; and the ordinary importer still refuses an empty day |
| Z12 | unit | (D52, v1.5) `PlanDrafting.day` with a day, a renamed day, a whole plan, a list of exercises, an invalid exercise, two days, an index off the end, nothing | The slot fills; the slot's name wins; the day named like the slot is taken from the plan; the list becomes the day; the error carries `days[2].exercises[0].reps` and "Day 3, exercise 1", and the draft is unchanged; `E_EDIT_INVALID` at `days[2]`; `E_EDIT_INVALID`; `E_EMPTY` |
| Z13 | unit | (D52, v1.5) `PlanDrafting.assemble` | Incomplete is `E_DRAFT_INCOMPLETE` saying how many are left; complete gives the outline's name, units, block and days with every exercise, no issues, the canonical text, and a plan the importer takes again; a weekday outline lends its weekdays |
| Z14 | unit | (D52, v1.5) `draft.json` | Written on the outline and after each paste; read back on relaunch with the fragments as pasted; a file without slots decodes with empty ones; a corrupt one is set aside and named; Discard and Delete all data remove it |
| Z15 | unit | (D52, v1.5) The model end to end | No draft refuses a paste and an assembly; outline, three pastes (one refused), assemble without saving, `saveDraftPlan` saves it active and the draft goes; a cancelled name conflict keeps the draft and Keep both resolves it; Home's card is the saved plan's |
| Z16 | unit | (D52, v1.5) The prompts | Both carry the marker and no placeholder; the outline prompt says NO exercises; the day prompt names the day, lists the outline, uses the outline's units and drops the days/schedule/cycle rules (and, since v1.10, the `restBetweenExercises` rule — TP18); every rule line of the day prompt is a line of the plan prompt; both refused if pasted back; a seven-day outline's day prompt is under 4,000 characters; §4 and §5 of PROMPT.md match the code |
| Z17 | manual | (D52, v1.5) Add plan → Create with a chatbot → **Build it day by day**, with a free ChatGPT tab | The outline pastes into slots; each day prompt fits one reply; a slot refused says which day and why; leave the app and come back to "Continue · 2 of 3 days pasted"; Review plan, Save plan; the plan is on Home and the draft is gone |

### Z4 — progression by performance (D53)

`JimmsBroTests/StepProgressionTests.swift`; W31–W39 keep passing for the calendar mode.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Z18 | unit | (D53, v1.5) `stepIndex`, `currentStep`, `isFinished`, `status` in performance mode | The same on any date; a day's step is the lowest among its exercises still climbing; an entry past its last step is nil; finished only when every entry is; "Step 1 of 4" / "Finished"; the calendar mode answers as in v1.3 |
| Z19 | unit | (D53, v1.5) `apply(to:on:)` and `Session.start` | Each entry's own step applied; a `{}` step keeps the plan's targets and still counts; each exercise stamped with its step, the session with the lowest and the mode; in calendar mode a `{}` week touches nothing; past the last step nothing is stamped |
| Z20 | unit | (D53, v1.5) `ProgressionSteps.achieved` | All sets at the top: yes; one rep short across the exercise: yes; two: no; a lighter weight: no; a heavier one: yes; a skipped set: no; a hold short of its seconds: no; an AMRAP's minimum met: yes; nothing done: no |
| Z21 | unit | (D53, v1.5) A workout completed through the model | The exercise that hit its step moves on with tries reset; the one that missed stays with a try counted; an untrained day's entry is untouched; the plan is on disk with the new steps; a session stamped at a step already left, or of a substitute, changes nothing; the calendar mode never moves by performance |
| Z22 | unit | (D53, v1.5) The reply and the words | `steps` read with the mode from the screen; `weeks` read as the alias with a cleanup warning; paths say `steps[…]` and locations "step 1"; "Step 2 of 4 of your progression"; "Step 1 of 4 · 2 tries" and "Done"; the ladder with ▸ on the current step; the chip's reason; Home's "step 1 of 4" (the ···'s "Step 1 of 4" in v1.8, D69; since v1.9 History's row's, D75) and the offer when every exercise is done |
| Z23 | unit | (D53, v1.5) On disk | A v1.3 progression (no mode, step or tries) reads as calendar at step 0; the performance fields round-trip; a session's mode round-trips and a frozen v1 session has none |
| Z24 | unit | (D53, v1.5) The prompt | "as 8 steps", `"steps": 8`, the performance cadence sentence, the calendar one in calendar mode, no placeholder left, under the bound; §3 of PROMPT.md matches the code (W37) |
| Z25 | manual | (D53, v1.5) Plan a progression with **When I hit the target**, run a day hitting one exercise and missing another | The chip reads "Step 1 of 4 of your progression"; after Finish, the Progression screen shows the first exercise at step 2 and the other at "Step 1 of 4 · 1 try" with ▸ on its ladder; Home reads "step 1 of 4" (in v1.8 the last line of Today's ···, D69; since v1.9 History's Progression row, D75) until every exercise of the day moves |

### Z5 — goals (D54) — removed in v1.7 (D68)

*Goals went before v1.7 shipped (SPEC §6.42), and `GoalTests.swift` with them: the rows below are marked removed and kept for the record. T30 is what remains.*

`JimmsBroTests/GoalTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Z26 | removed | (D54, v1.5) `Goals.progress` and `meets` | Nothing logged is nil at 0; the best set at or above the goal's reps counts and a heavier set for fewer reps does not; the fraction and reached; other units and other exercises never count; a hold's longest and reps' most |
| Z27 | removed | (D54, v1.5) A workout that meets a goal, through the model | The goal is marked with that workout and the Summary can name it; a far goal and a goal in the other unit are untouched; reached stays reached and a later workout is not credited; the file is written, read back, a goal removed, and Delete all data removes the file |
| Z28 | removed | (D54, v1.5) The decoder and the backup | A file with only the identity decodes with defaults; a full goal round-trips; the backup carries the goals; Merge adds only what is new and the same backup twice adds nothing; Replace all takes the backup's; a backup without goals restores with none |
| Z29 | removed | (D54, v1.5) The progression prompt | Carries the plan's unreached goals as MY GOALS after the plan, in the plan's units; not a reached one, not another exercise's; nothing when there are none |
| Z30 | unit | (D54, v1.5) The words | "100 kg × 5", "1:30", "1 rep"; the line with best and by, with nothing logged yet, and with reached; the prompt's line with and without a date |
| Z31 | removed | (D54, v1.5) History → **Set a goal** for an exercise you do, then a workout that meets it | The Goals section shows the line and the bar climbing; the Summary says "Goal reached: …" in green; the goal reads "reached" with the date; Progression's prompt has MY GOALS |

## U. v1.6 — nothing untrue, nothing unreachable, the first five minutes, hierarchy

`docs/ITERATION_7_PLAN.md` is the plan and `docs/UX_REVIEW_2026-09-09.md` the review it answers; one subsection per milestone, added as it lands.

### U1 — nothing untrue (D55)

`JimmsBroTests/UsabilityTests.swift`; Q38, Q39 and W6 were rewritten for the chip rule.

| ID | Kind | Case | Expected |
|---|---|---|---|
| U1 | unit | (D55, v1.6) `PlanSchedule.missed` | Nil for a plan with no anchor, however old; nil for a day before the import day or on or before the anchor day; Pull on the 8th when Push was done on the 7th and today is the 9th; nil after a completion re-anchors the pattern over the 8th; nil a fortnight away; Home's `missed` agrees |
| U2 | unit | (D55, v1.6) `SessionStats.comparison` | "Nothing logged" for an exercise with nothing logged today, with and without history; "First time" only for a first time that happened |
| U3 | unit | (D55, v1.6) `CalendarText.short(_:among:)` and `label` | Push/Pull/Legs unchanged; Full Body A/B → FBA/FBB; Upper A/Lower A/Upper B/Lower B → UA/LA/UB/LB; Day 1/2/3 → D1/D2/D3; names whose initials collide → their numbers; a name the plan lacks, or a one-day plan, keeps the plain rule; a projected cell and a completed session of the same plan read the same; the spoken cell says the whole name |
| U4 | unit | (D55, v1.6) The chip | "Do that again" is "10 × 100 kg · Last time 10 × 100 kg", never "5 × 100 kg"; with the fields prefilled to last time no chip is drawn; advice ("Try 5 × 102.5 kg") is; the first set of a weightless plan has none; a held set keeps its "60 s" chip |
| U5 | unit | (D55, v1.6) `IssueText.friendly` for `E_NOT_JSON` | A plan in words → "This is a plan in words. Send it to a chatbot with the prompt and paste back what it writes."; JSON cut short → the "looks cut off" sentence |
| U6 | unit | (D55, v1.6) `StepCard.targetLine(notes: false)` | The set's target without the exercise's note, which the overview's rows now render |
| U7 | check | (v1.6) `tools/check_release.py` | Version 1.5, build 1, on every target and in `docs/APP_STORE.md` |

### U2 — nothing unreachable (D56)

`JimmsBroTests/UsabilityTests.swift` for the one Core rule; the rest are the simulator screens in `build/u2-*.png`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| U8 | unit | (D56, v1.6) `WorkoutScreenModel.progressLine` | Nil while working (the stage title already says "Exercise 1 of 5 · Set 1 of 3"); "Exercise 1 of 5 · Set 2 of 3" while resting; a superset member's "A · round 1 of 3 · …" while working |
| U9 | ui | (D56, v1.6) ··· → Finish workout with sets left; ··· → Finish with nothing logged; Plan detail ··· → Delete; Session detail ··· → Delete workout; Build it day by day ··· → Discard draft; Progression ··· → Remove | Each is an alert with two buttons — Finish workout / Keep going, Discard / Keep going, Delete / Cancel, Discard / Keep it, Remove / Cancel — and Finish is not red |
| U10 | ui | (D56, v1.6) Tap the weight field | The keyboard rises with no system toolbar; the strip's trailing slot reads **Done**; nothing overlaps Log set; Done closes the keyboard and the rest controls return |
| U11 | ui | (D56, v1.6) Add plan, Build it day by day and Progression before anything is pasted | No white rectangle at the bottom; the button appears once there is text |
| U12 | ui | (D56, v1.6) The first set of a built-in plan | The weight field reads *tap to type* inside a soft outline; both go once a number is typed |
| U13 | ui | (D56, v1.6) Accessibility XL text on the workout | The header without its elapsed line, the target line cut to one, the current set row only, the strip without its next-set and set-time lines; the reps and weight rows and Log set on screen without scrolling (`build/u2-ax-2.png`); Exercises still lists every set |
| U14 | ui | (D56, v1.6) The header while working | "Exercise 1 of 5 · Set 1 of 3" once, over the bar; the small line reads the elapsed time alone; resting, it reads "Resting" over "Exercise 1 of 5 · Set 2 of 3" |

### U3 — the first five minutes (D57)

`JimmsBroTests/UsabilityTests.swift`; O63 (HomeAndAddPlanTests), Y1 (ResponsivenessTests) and Q21–Q30's settings (WarmUpAndTransitionTests) were rewritten for the new defaults and wording.

| ID | Kind | Case | Expected |
|---|---|---|---|
| U15 | unit | (D57, v1.6) The warm-up default | `Settings().warmUpSeconds` is 0; a settings file with no `warmUpSeconds` decodes to 300; one that says 0 means 0; the walk between exercises is unchanged |
| U16 | unit | (D57, v1.6) `WorkoutScreen.primary` | "Start first set" (`.startSet`) during a warm-up for a rep set and a hold; "Log set" between sets and between exercises; through the model, a warm-up's card offers `.startSet` and, after `skipRest`, Log set |
| U17 | unit | (D57, v1.6) `InputDefaults.weightHint` | Set on the first set of a plan without weights and no history; nil once a weight is typed and carried to the next set, nil with a history, nil for a bodyweight exercise |
| U18 | unit | (D57, v1.6) `ImportResult.unitsStated` | True for a plan that names `units`; false for one that took the setting's; true for a refusal |
| U19 | unit | (D57, v1.6) The picker's recommendation and sentence | `recommendedId` is Full Body and in the catalogue; `buildYourOwn` names Add plan, Copy prompt and Create with a chatbot |
| U20 | unit | (D57, v1.6) `HomeStart` on a rest day | A rotation resting on the 8th titles "Push", offers "Start Push" (since v1.8, **Start Tomorrow's Push**), says "Planned for Wed · PPL" (since v1.8 nothing — the button says when, D69), and reports nothing missed; the weekday case (O63) titles "Lower" with "Planned for Thu · Upper Lower" — *since v1.8's S3 (D71)*: the 8th titles **Rest** with **No exercise Today**, and Push is the strip's next square, **Start Tomorrow's Push** (`testARestDaySaysRestAndTheWorkoutIsOneTapAway`); the weekday case titles Rest, and its Thursday square Lower |
| U21 | unit | (D57, v1.6) `SummaryText.next` | "Next: Pull, tomorrow" after Push on a Wednesday; "Next: Pull, Friday" with a rest day between; "Next: Push, on …" a week away; "Next: Lower, Thursday" for a weekday plan done Monday; nil for a deleted plan or an imported session |
| U22 | ui | (D57, v1.6) A clean install, through the first workout | The picker shows **Start here** on Full Body; the review asks kg / lb above the days; Home titles the day and offers **Start Full Body A**; Start opens the first card with no warm-up and no permission alert; the empty weight reads *tap to type* with the hint under it; the first Log set raises the permission alert over a counting rest; the Summary ends with "Next: Full Body B, …" (`build/u3-*.png`) |
| U23 | ui | (D57, v1.6) A phone with the warm-up on | The card opens in the warm-up with **Start first set**; tapping it shows the first set with **Log set** |

### U5 — hierarchy (D59)

`JimmsBroTests/UsabilityTests.swift` for the Core rules; the rest are the simulator screens in `build/u5-*.png`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| U24 | unit | (D59, v1.6) `WorkoutScreenModel.undoStep` | Nil before anything is logged; the step just logged afterwards; nil again after `undoLast` |
| U25 | unit | (D59, v1.6) `WorkoutScreen.idleLine` and the idle strip | "Rest 1:30 starts when you log" on a set with rest after it; "Then on to <exercise>" on a block's last set; nil on the day's last set; the working strip's title carries it |
| U26 | unit | (D59, v1.6) `ExerciseText.summary` | Minutes, sets, and "… kg lifted"; no clock-time duration |
| U27 | ui | (D59, v1.6) Home | Start above the tab bar; "This week" in ink; Preview / Another day as small bordered buttons; planned days as labels without boxes, today outlined |
| U28 | ui | (D59, v1.6) The workout | ↺ on the row just logged; the strip's Undo only at accessibility sizes; the idle strip reads "Rest … starts when you log". *(v1.10, D81: the rows are dots and Undo is the strip's at every size, during the rest — TP13, TP15)* |
| U29 | ui | (D59, v1.6) Plan detail and the review | "kg · repeats every 7 days"; chips wrapping onto a second line; an Add exercise row and a bordered Start per day; **Use this plan** in the menu and on the review's toggle; a check on the plan in use in the list |
| U30 | ui | (D59, v1.6) History and Settings | "28 min · 16 sets · 13,920 kg lifted" rows; a Find an exercise row that lists every exercise; preset buttons under the three duration rows, the current one tinted; the rewritten footers |
| U31 | unit | (D60, v1.6) A launch with no workout | `AppModel.load` calls `end()` once even though it has shown nothing — an activity left by a run that was killed is not the app's to remember, and it is the app's to clear |
| U32 | unit | (D60, v1.6) A launch mid-workout | The resumed state is pushed exactly once, `end()` is not called, and `shownActivity` is the state of the session on disk; an unchanged tick after it pushes nothing |
| U33 | device | (D60, v1.6) The real activity on the phone | Start a workout, force-quit the app mid-rest, reopen: one activity, still counting, not two. Finish it — the Island and the Lock Screen clear. Force-quit mid-rest, then open the app on a day with no workout: the leftover activity goes within a second |
| U34 | unit | (D58, v1.6) The plain grammar | `TargetText.target` reads "Aim 4–6 reps · 100 kg" (and the same for a fixed 5 inside 4–6), "As many reps as you can", "Aim at least 10 reps", "For 45 seconds", "For at least 30 seconds", "… · stop 2 short of failure"; `summary` reads "3 sets of 8–12 reps · 60 kg" and "… · then lighter, as many as you can"; `setLine` reads "Set 1 of 2 · paired with <partner>" and "lighter set 1 of 1"; a row that names its exercise carries no pairing; the current row's second line is "Last time 9 × 60 kg" and no row contains "@" |
| U35 | unit | (D58, v1.6) Compact notation | `Settings().wording == .plain`; with `compactNotation` on, the same screen reads "8–12 · 60 kg" and "last 9 @ 60" (since v1.10, D81: `StepCard.targetLine` and `setRows` read them, and the Workout screen's card and dots are the same either way); the setting round-trips through the store, and a file written before v1.6 reads as off |
| U36 | unit | (D58, v1.6) What the setting must not reach | `Prompts.render` is byte-identical with the switch on and off |
| U37 | ui | (D58, v1.6) Settings → Compact notation | The toggle sits under Keep screen awake; its footer quotes the forms in force; turning it on changes the workout card, the set rows, Plan detail, the review, the Overview, Session detail and the Summary together |

## T. v1.7 — Today as one card, fewer tabs, earned controls, a colour per day

`docs/ITERATION_8_PLAN.md` is the plan; one subsection per milestone, added as it lands. The plan's proposed ids are kept where they were free.

### T1 — Today is one card (D61)

`JimmsBroTests/TodayTests.swift`; O63's empty-card row, Y11's subtitle and Y13's pins were rewritten for the new button.

| ID | Kind | Case | Expected |
|---|---|---|---|
| T1 | unit | (D61, v1.7) `HomeStart.message` | Nil with no plan and on an ordinary day; `.notificationsOff` when the permission was declined; `.progressionFinished` outranks it; `.missed` outranks both; with the missed workout dismissed the next in the order speaks; never two. Each reads as it read in v1.6: "… was due …" · Do it now · Dismiss; "Your progression has run its course." · Plan the next one; the notifications sentence with no actions |
| T2 | unit | (D61, v1.7) `HomeStart.alternatives` | Empty with no plan; since v1.9 (D75) Change plan with the plan's cycle, then Change *day*'s exercises with the shown day's name and colour (TQ21); while a session is open Change plan, Discard workout — ending with Discard; the titles are Change plan, Change Wednesday's exercises, Discard workout. (Until v1.8 the list began with Another day — since S2, D70, the strip is the way to another day and the item is gone, TS9; until v1.9 Plan a progression joined last while D50 offered it, D75.) |
| T3 | unit | (D61, v1.7) The exercise block is the preview | `exerciseLabel` reads "Exercises: Bench Press, Incline Press, Lateral Raise, Tricep Pushdown, Plank, and 2 more", and "Exercises: Squat" with fewer than five — each ended "Opens Push", "Opens Legs" until v1.9, when D75 made the block the preview and nothing more; in progress the block comes from the session with the same label, the clock reads "23 min" *so far* (v1.7: the subtitle "In progress · 0 of 7 sets · 23 min"; D69) and `planId` stays nil |
| T4 | unit | (D61, v1.7) The empty card | "No plan yet"; "Choose a built-in plan to start today, or have a chatbot write yours."; **Choose a plan** — `Introduction.choosePlan`, the same words as the intro's button — and the one link **Try a short practice workout**; no ···, no message, no exercises; the link is on no other card |
| T5 | ui | (D61, v1.7) Today at accessibility XL | On the smallest supported iPhone, in every state — a workout day, a rest day, mid-workout, the empty card — the name, the subtitle and Start stay visible without scrolling, and the exercise list is what scrolls (device; `DEVICE_CHECKLIST.md` T5) |
| T6 | ui | (D61, v1.7) The screenshot hook | `tools/shot.sh build/today.png -uiScreen today` shows Today: the name, the subtitle, the exercise block with its chevron, the ··· top-right, Start in the bottom slot; no calendar, no week line, no small buttons under the names |

### T2 — How many tabs (D62)

`JimmsBroTests/TodayTests.swift` (T7) and `JimmsBroTests/IntroductionTests.swift` (T8 is Y13, whose History pin moved from `RootView.swift`'s literal to `AppTab`).

| ID | Kind | Case | Expected |
|---|---|---|---|
| T7 | unit | (D62, v1.7) The tab bar is SPEC's list | `AppTab.allCases` is Today, History, in that order, and equals the bold list on SPEC §4.0's "Tab bar with" line; `RootView.swift` draws `ForEach(AppTab.allCases` and has one `.tabItem`, so no tab is drawn outside the list (the SPEC and source reads run on the host routes and skip on the simulator) |
| T8 | unit | (D62, v1.7) The intro's controls still exist (Y13, re-run) | Every `Introduction.namedControls` entry exists by that name: **Choose a plan** and **Start …** on Today's cards, **Log set** on the workout, **History** as `AppTab.history.title`, and the view literals — Create with a chatbot, Progression, built-in plan, and **Add plan** on the Plans list, which Today now pushes |
| T9 | ui | (D62, v1.7) Plans and Settings from Today | With a plan: Plans is two taps from Today (··· → Change plan) and a plan's detail one more; Settings is one (the gear, top-left); the gear sits in the same place on Today and History; back returns to the tab it left; the tab bar shows Today and History and nothing else (device; `DEVICE_CHECKLIST.md` T9) |

### T3 — The calendar lives in History (D63)

`JimmsBroTests/HistoryTests.swift`; O66's test moved there from `HomeAndAddPlanTests.swift` as T10, its cases unchanged. O65 (the week strip is the month grid's projection) stands where it is.

| ID | Kind | Case | Expected |
|---|---|---|---|
| T10 | unit | (D63, v1.7) The week's line, re-homed (O66) | `HomeActivity.line` reads "2 workouts this week · 1 h 32 min" for the calendar week containing today, "1 workout this week · 48 min" for one, "No workouts yet this week" for none; a workout still running does not count |
| T11 | unit | (D63, v1.7) The tapped-day line | `CalendarText.line` for today's planned day ends "· Upper · planned" and opens nothing (no **Start this**); a finished day's ends "· Push · 48 min" and opens its sessions; a rest day's ends "· Rest day" and opens nothing; a day the plan says nothing about, or a planned day whose plan is gone, has no line; no line says "projected" |
| T12 | unit | (D63, v1.7) The plan's week before the first workout | With no sessions, `CalendarProjection.week` for a weekday plan (Upper on Monday, Lower on Thursday) lists Upper and Lower as planned, in that order, and the other five days as rest, and every day has a line — what History's strip draws above "No workouts yet" |
| T13 | ui | (D63, v1.7) History's calendar by hand | History opens with the strip and the week's line; **Month** and **Week** switch; a done day tapped once shows its line, tapped again lands on the session pushed onto History, and back returns to History; today's planned day shows "… · planned" with no button; a fresh install with a plan shows the plan's week above "No workouts yet" and **Import from another app** (device; `DEVICE_CHECKLIST.md` T13) |

### T4 — Controls are earned (D64)

`JimmsBroTests/GatesTests.swift`. T2's ··· cases in `TodayTests` now run through `Gates`, unchanged. The plan's T14–T21 kept their ids; SPEC's table is §6.40, not the plan's §6.39, which T3 took.

| ID | Kind | Case | Expected |
|---|---|---|---|
| T14 | unit | (D64, v1.7) `Gates.month` | False with no workouts; true on a Monday for a workout six days old (last Tuesday); on a Sunday, the same age (last Monday) is false when the week starts on Monday — it is this week, the strip's first day — and true when it starts on Sunday; still true a day and a month later; a workout still running earns nothing |
| T15 | unit | (D64, v1.7) `Gates.metricsAndFind` | False with no workouts, true with one, false with only a running one |
| T16 | removed | (D64, v1.7) `Gates.goals` — removed with goals (D68) | False with no workouts, true with one, false with only a running one |
| T17 | removed | (D64, v1.7) `Gates.anotherDay` — removed with the chooser in v1.8 (S2, D70): the strip's tap is not earned, and TS9 pins the gate's absence | Showing a day: true for a two-day plan, false for a one-day plan; with nothing scheduled: true for a one-day plan, false for a plan with no days |
| T18 | unit | (D64, v1.7) `Gates.changePlan` | False with no plans, true with one |
| T19 | removed | (D64, v1.7) `Gates.planProgression` — removed with Today's Plan a progression in v1.9 (Q3, D75); TQ22 pins it gone | False with no sessions, or with a session of another exercise only; true once every exercise on the day has one; false again once the plan carries a progression; false for an index past the plan's days |
| T20 | unit | (D64, v1.7) `Gates.notificationsOff` | False before the first Log set whatever the answer would be; after it, true when refused and false when allowed; through `AppModel`, Start leaves the line off and the first Log set with the permission refused turns it on |
| T21 | unit | (D64, v1.7) The table is SPEC's | Every `static func` in `Core/Gates.swift` is named in a row of SPEC §6.40's table, every row names one, and there are as many rows as functions — four since v1.9 (five in v1.8, until D75 took Plan a progression's) — except the rows whose Core cell is `—` — the strip's (S2, D70) and, since v1.9, the swap's marks' (Q2, D74) — which the table records as deliberately ungated and the test counts as such (the SPEC and source reads run on the host routes and skip on the simulator) |

### T5 — A colour per day (D65)

`JimmsBroTests/DayColourTests.swift`. The plan's T22–T24 kept their ids; T25 is new, so that T24 on the phone checks the drawing rather than the arithmetic. SPEC's section is §6.41, after T4's §6.40.

| ID | Kind | Case | Expected |
|---|---|---|---|
| T22 | unit | (D65, v1.7) `DayColour.index(dayIndex:)` | Six days take positions 0–5 — green, orange, purple, pink, teal, indigo — and the seventh wraps to green; the fourteenth is orange; a negative index is still in range |
| T23 | unit | (D65, v1.7) The palette is not the accent, red or yellow | `DayColour.allCases` is the plan's six and no name contains accent, blue, red or yellow; `DaySquare.swift` draws each as the system colour of its own name and names no `accentColor`, `.red`, `.yellow`, `.blue`, `.tint` or `Color.done` (the source read runs on the host routes and skips on the simulator) |
| T24 | ui | (D65, v1.7) One day, one colour, on the phone | The same day is the same colour on Today, in the calendar, on its History rows, in the workout header and on the Lock Screen, in light and in dark, and nothing else took a colour (device; `DEVICE_CHECKLIST.md` T24) |
| T25 | unit | (D65, v1.7) One day, one colour, in Core | `HomeStart.dayColour` is the colour of the day the card names, the running session's mid-workout (Legs: purple), and nil on the empty card; `DayEntry.dayColour` is the day's for a planned day and the first workout's for a finished one, nil for a rest day and an empty one; `DayColour.of(session:plans:)` finds the day by the plan's id and the normalized name, is nil when the plan is gone or the day renamed, and follows the day when the days are reordered; `WorkoutActivityState.of(…, plans:)` carries the day's colour working and resting, and none without the plans |

### T6 — Docs, checklist, bundle, screenshots, 1.7

No app code beyond the version; the check is the script's, as U7 was for v1.6.

| ID | Kind | Case | Expected |
|---|---|---|---|
| T26 | check | (v1.7) `tools/check_release.py` | Version 1.7, build 1, on every target and in `docs/APP_STORE.md` |

### T7 — The owner's review before the push (D66–D68)

What the owner asked for on 2026-09-13, after walking T0–T6 and before v1.7 went to `main` (SPEC §6.42). The pins read source files, so, like T21, they run on the host routes.

| ID | Kind | Case | Expected |
|---|---|---|---|
| T27 | unit | (D66, v1.7) One way to find an exercise | `HistoryView.swift` draws no `.searchable` field and keeps the **Find an exercise** row |
| T28 | unit | (D67, v1.7) Progression is History's | `HistoryView.swift` has the row — `Text("Progression")`, `PromptText.progressionRow` — and opens `ProgressionView`; `PlanDetailView.swift` has neither; Today's **Plan the next one** sets the Progression sheet, not the plan preview. Z3's and Y13's pins point at `HistoryView.swift` |
| T29 | ui | (D66–D68, v1.7) History's block on the phone | As DEVICE_CHECKLIST T29: no search field; Metrics, Find an exercise and Progression in one block from the first workout; Progression opens the active plan's screen; Plan detail has no Progression row; no Goals section and no **Set a goal** |
| T30 | unit | (D68, v1.7) What goals left behind is harmless | A store holding a `goals.json` loads with nothing set aside and the file untouched; a backup that carries `goals` reads and restores its plans and sessions by Replace all and by Merge; the progression template has no `{{goals}}` and the prompt no MY GOALS |

## TS. v1.8 — No words without a cue, the week as a strip, a rest day that says rest

`docs/ITERATION_9_PLAN.md` is the plan; one subsection per milestone, added as it lands. Every single letter is taken, so the prefix is **TS**; the plan's proposed ids are kept where they were free.

### S1 — Nothing without a cue (D69)

`JimmsBroTests/TodayTests.swift`. The rows that read v1.7's subtitle were rewritten for the clock, the rows and the step line, each noting the change: T3, O64, U20, W39, Z22, Z25 and Y13 (the ready card's button is **Start Today's Push**); T4's sentence is `HomeStart.sentence`, and `BuiltInPlanTests`' card follows.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TS1 | unit | (D69, v1.8) A day's card carries no sentence | `HomeStart` has no `subtitle` (a `Mirror` of it names none); on a workout day with last time's workout, on a weekday plan's rest day and mid-session, `sentence` is nil and nothing the card shows — title, button, clock, message, row names — contains "Planned for", the plan's name or "exercises", nor does the block's spoken label contain the first two; the clock reads "2 min" *last time*; the rest day's button reads **No exercise Today** (since S3, D71; **Start Thursday's Lower** until then), and the Thursday square tapped from it — held to the same rules — reads **Start Thursday's Lower** |
| TS2 | unit | (D69, v1.8) The rows and their sets | Six exercises of 4, 3, 2 (one of them a drop set), 1, 5 and 2 sets: `rows` are the first five with 4, 3, 2, 1 and 5 — the drop set one block — `more` is 1, the spoken label ends "and 1 more" ("and 1 more. Opens Full" until D75), and nothing is logged before a session |
| TS3 | unit | (D69, v1.8) Mid-session, the filled blocks are the engine's | Two exercises of two drop sets each; with Bench Press's first set and its drop logged through the engine, the rows read Bench Press 2 sets, 1 logged, and Row 2 sets, 0 logged — the engine's count of logged first steps — and the clock "2 min" *so far* |
| TS4 | removed | (D69, v1.8) The step line — removed in v1.9 (Q3, D75): where a progression is, is History's Progression row's, and TQ22 pins `stepLine` gone | Nil without a progression; "Week 2 of 4" by the calendar in week 2, with a ··· there to hold it; "Step 1 of 4" by performance; nil once the progression has run its course, when the message says so instead |
| TS5 | ui | (D69, v1.8) Today at accessibility XL | On the smallest supported iPhone: the name, the meta row, the list and Start on screen, the list scrolling (U13's rule), and the set blocks grown with the text (device; `DEVICE_CHECKLIST.md`'s v1.8 rows, written with S4) |

### S2 — The week is the strip (D70)

`JimmsBroTests/TodayTests.swift` (TS6–TS10) and `GatesTests` (T21 counts the strip's ungated row; T17 went with `Gates.anotherDay`). T2 lost Another day, and Z3's pin follows the ··· list into `HomeStart.alternatives(plans:offersProgression:running:)`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TS6 | unit | (D70, v1.8) Seven squares, today first, on a weekday plan | Mon Push, Wed Pull, Fri Legs from a Monday: `WeekStrip.days` is Push rest Pull rest Legs rest rest — offsets 0–6, day indices 0 · nil · 1 · nil · 2 · nil · nil, colours green · nil · orange · nil · purple · nil · nil, *when* Today, Tomorrow, Wednesday … Sunday, spoken "Today, Push" / "Tomorrow, rest"; from a Thursday the week wraps (rest Legs rest rest Push rest Pull); the card's `strip` is the same with `shownOffset` 0; the empty card has no strip and no button mark; a plan whose days have no weekday is Nothing scheduled with seven grey squares, **No exercise Today** under a moon and disabled, Change plan in the ···, and its sentence kept |
| TS7 | unit | (D70, v1.8) The strip agrees with the calendar | On a rotation anchored on the 7th, from the 9th and from the 28th: `CalendarProjection.next(days:from:)` hands seven days whose entries equal the month grid's for the same dates, and each square's index, name and colour are the entry's (`.projected`) or nil (`.rest`); the 9th reads Legs rest Push Pull Legs rest Push and the 28th, across the month's end, Pull Legs rest Push Pull Legs rest; with Push done on the 9th, today's square is Push, green, and the other six unchanged |
| TS8 | unit | (D70, v1.8) The button names when, and a tap shows that day | `WeekStrip.buttonTitle`: **Start Today's Push**, **Start Tomorrow's Pull**, **Start Friday's Legs**; for a rest square **No exercise Today** / **Tomorrow** / **Friday**. Through the card on a Monday with a two-minute Pull behind it, showing 2: Pull, orange, Row's one block, the clock "2 min" *last time*, **Start Wednesday's Pull** with the play mark and enabled, the plan and day 1 as target and preview, no sentence, not a rest, Change plan alone; showing 1: **Rest**, `isRest`, no colour, no rows, no clock, no sentence, **No exercise Tomorrow** with the moon and disabled, no target, Change plan alone, the same strip; showing 0 equals the card with nothing shown (Push, **Start Today's Push**); 9 clamps to 6 and −1 to 0; with a session open the first square is the Resume card and a tapped square is that day's card with its Start and Change plan, Discard workout |
| TS9 | unit | (D70, v1.8) Another day left the ··· | No card — a rotation, a weekday plan on a workout day and a rest day, nothing scheduled, a tapped square — lists an item titled Another day; the rotation's and nothing-scheduled's ··· is Change plan alone; `HomeCard.swift` has no `case anotherDay`, `Gates.swift` no `func anotherDay`, and Today no "Which day?" chooser but a `WeekStripView` (the source reads run on the host routes) |
| TS10 | unit | (D70, v1.8) The shown day is not stored | `examples/store/v1/settings.json` decodes with its rest of 90 s and round-trips equal; no field of `Settings` and no key the decoder in `Core/Persistence.swift` reads (thirteen, unchanged) contains *shown*, *strip*, *offset* or *week*, and every key it reads is a field; `HomeStart` does carry `shownOffset` |
| TS11 | ui | (D70, v1.8) The strip at accessibility XL | The strip wraps nothing and stays one row beside the clock (device; `DEVICE_CHECKLIST.md`'s v1.8 rows, written with S4) |
| TS12 | ui | (D70, v1.8) The shown day dies with the process | Tap Pull on a Tuesday, background the app, return: the card still shows Pull; kill and relaunch: it shows Tuesday (device; the checklist's v1.8 rows) |

### S3 — A rest day says rest (D71)

`JimmsBroTests/TodayTests.swift` (TS13–TS15, TS17). TS1, O63 and U20 were rewritten, each noting the change: their rest days say rest, and the workout they used to headline is the strip's tapped square. TS17 is the owner's reading of a case the plan did not name — the rest of a day whose workout is done.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TS13 | unit | (D71, v1.8) A rest day says rest | A weekday plan (Mon Push, Wed Pull, Fri Legs) on Tuesday the 15th, with Pull done on the 9th: **Rest**, `isRest`, no colour, no rows and no spoken label, no target or preview, no clock (not Pull's), no sentence or step line, **No exercise Today** under the moon and disabled, Change plan alone, the strip rest Pull rest Legs rest rest Push with its first square grey; `StartCard` is still `.restDay` naming Wednesday's Pull; a rotation's rest entry (Legs done on the 9th, on the 10th) is the same card, with nothing missed and no message |
| TS14 | unit | (D71, v1.8) The next workout is one tap away | The same Tuesday showing 1: Pull, orange, the plan and day 1 as target, Row's one block, "2 min" *last time*, **Start Tomorrow's Pull** with the play mark and enabled; showing 3: Legs, Squat, **Start Friday's Legs**; showing 4: a rest card, **No exercise Saturday**; the rotation's rest day showing 1: Push, day 0, five rows and 2 more, **Start Tomorrow's Push** |
| TS15 | unit | (D71, D37, v1.8) A missed workout still speaks on a rest day | A rotation anchored on the 7th with a progression that has run its course, on the 10th: the rest card, **No exercise Today**, no target; the missed day is Legs, index 2, on the 9th, "Legs was due …", as the message with Do it now · Dismiss; dismissed, the progression that has run its course speaks — on today's rest card and on a tapped grey square (showing 4) |
| TS16 | ui | (D71, v1.8) The rest card drawn | The z's and the moon in light and dark; VoiceOver reads "Rest", the seven days ("Today, rest", "Tomorrow, Pull", …), then "No exercise Today", dimmed (device; the checklist's v1.8 rows) |
| TS17 | unit | (D71, v1.8, the owner's reading) Done Today | A rotation whose Push was finished on the 9th: `StartCard` is `.restDay` naming Thursday's Pull; the card is **Rest** with **Done Today** (`HomeStart.doneTitle`) under a check, disabled, with no target, rows or clock, a grey square before the title and today's strip square Push, green; showing 1 is **Start Tomorrow's Pull**; showing 3 is **No exercise Saturday** under the moon; a weekday plan's Tuesday with Wednesday's Pull done early is **Done Today** too, its first square Pull; and a weekday plan's own Monday after its Push — `StartCard` still `.today` — is **Done Today** with no target and no rows, its first square Push, green, and Wednesday's Pull one tap away (**Start Wednesday's Pull**), while the next Monday is an ordinary **Start Today's Push** |

## TQ. v1.9 — A day swapped, not a plan changed

`docs/ITERATION_10_PLAN.md` is the plan; one subsection per milestone that landed a decision, Q1–Q6 (Q7 is documents and adds no case). Every single letter is taken and TS was v1.8's, so the prefix is **TQ**; the plan's proposed ids were kept as they landed, so none was renumbered. The device cases (TQ18–TQ20, TQ24, TQ29, TQ33, TQ38, TQ39) are the **v1.9 rows** of `DEVICE_CHECKLIST.md`.

### Q1 — A day swapped, not a plan changed (D72), and Slide (D73)

`JimmsBroTests/SwapTests.swift`, on the plan's example: Push · Pull · Legs · Rest · Push · Pull · Legs, anchored so Monday 14 September 2026 is Push; Legs finished on Monday. `CalendarProjection`'s three functions, `WeekStrip.days` and `PlanSchedule.missed` took `swaps:` with no default, so every test that called them names `swaps: []`; `PlanSchedule.next(_:today:)` became `nextInPattern` (the repeat block's), and the swap-aware `next(_:today:swaps:)` is Today's; `missed` returns a `MissedDay` whose index is optional. L7 was rewritten for D72.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TQ1 | unit | (D72, v1.9) Legs on a Monday expecting Push | Two swaps: Monday's, original Push, replacement Legs, no `askedOn`, answered; Wednesday's — the next date the pattern projects Legs — original Legs, replacement Push (the default, today's day), `askedOn` Monday, unanswered; `cyclePosition` and `cycleAnchor` unchanged; nothing on Tuesday |
| TQ2 | unit | (D72, v1.9) The projection reads the swaps | Monday…Sunday: Legs (completed), Pull, Push, rest, Push, Pull, Legs; the strip's Monday is purple with a green dot, its Wednesday green with a purple dot and an asking ring, spoken "Wednesday, Push, question", Tuesday plain; today's card is **Done Today** with no question, Tuesday's `StartCard` is Pull, and the Wednesday square's card reads **Start Wednesday's Push** with a question whose options are Rest, Push (default), Legs, Slide, chosen Push, unanswered; the month grid names Wednesday Push in green |
| TQ3 | unit | (D72, v1.9) The same workout on a Thursday rest day | Thursday's original is rest, replacement Legs; Sunday's — the next Legs — original Legs, replacement rest, asked on Thursday; the options are Rest (default), Legs, Slide; Thursday's square is purple with a grey dot, Sunday's grey with a purple dot and the ring, spoken "Sunday, rest, question" |
| TQ4 | unit | (D72, v1.9, the owner's 8) Push already done Monday, then Legs | The expected Push re-anchors to Monday and writes no swap; Legs then writes only Wednesday's, replacement rest, options Rest (default), Legs, Slide; Monday's square is Push with no dot; today's card is **Done Today** |
| TQ5 | unit | (D72, v1.9) Each answer's projection | Rest: Wednesday is rest, its ring answered, a purple dot, spoken "Wednesday, rest", the question answered and chosen rest, and no missed message on Tuesday; Push: Wednesday is Push, ring answered; Legs (keep): Wednesday is Legs with no dot and an answered ring, the swap kept, no missed message; every answer leaves the position and anchor alone |
| TQ6 | unit | (D73, v1.9) Slide | Re-anchors exactly as `advance` would have for Legs on Monday — position 2, anchor Monday — `slideUndo` holds 0 and the 7th, the swap reads `.slide` answered, Tuesday…Friday are rest, Push, Pull, Legs, and neither Wednesday nor Monday carries a dot; answering Push afterwards restores the position and anchor, clears `slideUndo`, and Wednesday is Push again |
| TQ7 | unit | (D72, v1.9) What the date said is no swap | Push on Wednesday after the swap leaves the plan and the swaps as they were, with a second session; Push on Monday, as expected, writes no swap and re-anchors to Monday at the projected entry — position 0, not `advance`'s 4 — so the week's grid is unchanged though Push is twice in the cycle |
| TQ8 | unit | (D72, v1.9, the owner's 8) Another plan, a discard, nothing logged | A session of a second, inactive plan writes no swap and leaves the active plan; a started then discarded Legs writes nothing and leaves the anchor; a finished session with nothing logged writes nothing |
| TQ9 | unit | (D72, v1.9) Missed reads the swaps | Nothing missed on Tuesday and no message; on Thursday, "Push was due Wednesday" — date Wednesday, name Push, index 0 for Do it now — on the card too; after answering Rest, Wednesday is never missed and Thursday reports Tuesday's Pull |
| TQ10 | unit | (D72, v1.9) Swaps on disk | A fresh store has none and no file; saved swaps load back equal, the file carries `fileVersion` and a slot as a `kind`; an unreadable file loads as none, is listed as `swaps.json` and set aside as `swaps.json.corrupt-…`; `examples/store/v1/swaps.json` decodes to the two swaps of TQ1; a swap missing its optional keys decodes, one missing its identity or with an unknown kind throws; `backup-1.7.json` (with goals, no swaps) restores with none and `backup-1.9.json` with its two, Merge adds only by id, the export carries them, and merging the old backup takes none away; deleting the plan deletes its swaps |
| TQ11 | unit | (D72, v1.9) A weekday plan | Legs on Monday (a Push day): Monday's original Push, replacement Legs; Friday's original Legs, replacement Push, asked on Monday, options Rest, Push, Legs and no Slide; the week reads Legs (done), rest, Pull, rest, Push, rest, rest; Friday's `StartCard` is `.today` Push with **Start Today's Push**, its square ringed; Slide asked for anyway changes nothing |
| TQ12 | unit | (D72, v1.9, pin) The swaps have no default | The declarations of `CalendarProjection.entries`, `next(days:)`, `week(containing:)`, `WeekStrip.days` and `PlanSchedule.missed` each contain `swaps: [DaySwap],` and none `swaps: [DaySwap] =` (skipped in the simulator's sandbox, run on the host routes) |
| TQ13 | unit | (D72, v1.9) A day whose name left the plan, and the past | A swap naming a day the plan does not have projects `.none` — the square unnamed, uncoloured, still dotted; with Push renamed Upper, Wednesday's Push projects `.none`, the question still says Push was chosen and offers today's day as Upper; a swap on a past date is history — `.none` with no session, `.completed` with one; another plan's swap does not touch this plan's Tuesday |

### Q2 — Today shows it (D74)

`JimmsBroTests/SwapTests.swift`, on the same example. `HomeStart.current` took `reopened:` (default false) beside `showing:`; `SwapQuestion` gained `heading`, `slide`, and each option's `colour` and `isChosen`; `WeekStrip.Square` gained `was` and `hold`. T21 counts two ungated rows in §6.40's table, the strip's and the swap's marks'.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TQ14 | unit | (D74, v1.9) The strip's marks | After TQ1: Monday dotted green, "was Push", no ring, a long press shows what it was; Wednesday ringed `.asking`, "was Legs", a long press reopens; Tuesday and Thursday–Sunday plain — no dot, no ring, no words, a long press is a tap; answered, Wednesday's ring is `.answered` and a long press still reopens; on Thursday nothing is marked; with Wednesday's Push done and the question open, Wednesday has no ring and its card no question, and keeps its dot ("was Legs") |
| TQ15 | unit | (D74, v1.9) The block's words and squares | Wednesday's: "Wednesday's Legs is done. Make Wednesday:", squares Rest · Push · Legs in grey, green and purple, Push checked and Slide not; the Slide row green, orange, purple — the strip's own Wednesday–Friday once Slide is answered — read "Slide: Push, Pull, Legs", and previewing moves nothing; reopened after the slide, still Rest · Push · Legs, none checked, Slide checked, the preview unchanged. Sunday's after a Thursday rest-day workout: "Sunday's Legs is done. Make Sunday:", Rest · Legs, Rest checked, the preview the slid strip's Sunday–Tuesday. A weekday plan's Friday: Rest · Push · Legs and no Slide row |
| TQ16 | unit | (D74, v1.9) The card follows the choice | Wednesday's card while it asks: the block, title Push in green, **Start Wednesday's Push**, enabled. Each answer — Rest: **Rest** and **No exercise Wednesday** under the moon, disabled; Push: **Start Wednesday's Push**; Legs: **Start Wednesday's Legs**; Slide: **Start Wednesday's Push** — closes the block, and reopened it stands again with the choice checked and the button unchanged. Tuesday's card has no block, reopened or not; on Wednesday the block is on today's card with **Start Today's Push**; with a session open it is not on the session's card, and the ring still asks |
| TQ17 | unit | (D74, v1.9) What VoiceOver reads | "Wednesday, Push, question" while it asks and "Wednesday, Push" once answered; "Today, Legs" with the value "was Push"; after a Thursday rest-day workout, Thursday's value "was rest", and Sunday "Sunday, rest, question" with "was Legs" |
| TQ18 | device | (D74, v1.9) The ring on the phone | The ring breathes, about 2.4 s a breath, while the question asks; with Reduce Motion on it holds still at full strength; once answered it is faint and still |
| TQ19 | device | (D74, v1.9) The long press | After an off-day workout, a long press on today's square shows the callout — the pattern's square and "was Push" — and a tap elsewhere dismisses it; a long press on an answered, ringed square shows its day with the block back and the choice checked; a quick tap on any square is still a tap |
| TQ20 | device | (D74, v1.9) The block at accessibility XL | The block keeps its four options on screen — the squares wrap rather than leave it, and the block scrolls if it must — with the name, the strip and the button in the bottom slot held |

### Q3 — The ··· speaks in squares (D75)

`JimmsBroTests/TodayTests.swift` (TQ21–TQ22) and `DayColourTests` (TQ23). `HomeStart.Alternative` carries what its symbol draws — `.changePlan(cycle:)`, `.changeExercises(dayName:colour:)`, `.discardWorkout` — and `HomeStart` lost `stepLine`, `offersProgression` and `previewPlanId`; `Gates.planProgression` and `PromptText.planProgression` went with the item. Rewritten for it, each noting the change: T2, T3, T21 (four functions), TS2, W39, Z1, Z3, Z22 and Z25; removed: T19, TS4 and Z2.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TQ21 | unit | (D75, v1.9) The ···'s two items | On Legs today (Push Pull Legs Rest, anchored): Change plan with the cycle green, orange, purple, grey, then Change Today's exercises in purple; a tapped rest square gives Change Tomorrow's exercises with no colour, and Friday's Push Change Friday's exercises in green; a weekday plan's tapped Pull, Change Wednesday's exercises in orange, and today's rest, Change Today's exercises with no colour; a one-day plan's card is the same two, before and after every exercise has history; once today's workout is done, Change plan alone; Nothing scheduled, Change plan alone; with a session open, Change plan and Discard workout, on the session's card and on a tapped square's; the titles "Change plan", "Change Wednesday's exercises", "Discard workout" |
| TQ22 | unit | (D75, v1.9, pin) The progression left Today | A `Mirror` of `HomeStart` names no `stepLine`, `offersProgression` or `previewPlanId`; a plan whose day has history for every exercise and a plan mid-progression both list only Change plan and Change Today's exercises, with no message; `HomeCard.swift` has no `case planProgression`, `Gates.swift` no `func planProgression`, `Prompts.swift` no `planProgression`, and `HomeView.swift` no step line and no tap from the rows into Plan detail (the source reads run on the host routes); T21 counts four gates |
| TQ23 | unit | (D75, v1.9) The cycle as a symbol | `DayColour.cycle(of:)`: a rotation's repeat block as written — green, orange, purple, grey, green, orange, purple — an entry naming no day grey, and a weekday plan Monday to Sunday (green, grey, orange, grey, purple, grey, grey); `CycleGlyph`: seven and fourteen drawn whole, thirty-one as its first fourteen in order and a trailing mark; `CycleSymbol` cuts through `CycleGlyph` and Change plan draws it (source reads on the host routes) |
| TQ24 | device | (D75, v1.9) The menu's symbols | On the phone, the ··· shows the plan's cycle in its colours beside Change plan and the shown day's square beside Change *day*'s exercises, in light and in dark, and the squares read as squares at the menu's size |

### Q4 — Change *day*'s exercises (D76)

`JimmsBroTests/SwapTests.swift` (TQ25–TQ28). The picker is Core's — `DayChoices` from `PlanLibrary.dayChoices(for:now:)`, written by `choose(_:for:now:)`, a pasted day read by `ownDay(_:named:units:settings:now:)` (`Core/ChangeDay.swift`) — and `ChangeDayView` draws it. `CalendarProjection`'s three functions and `WeekStrip.days` take `plans:`; `StartCard.own`, `HomeStart.ownDay` and `.isOutlined`, `MissedWorkout.planId` and `.own`, `WeekStrip.Square.planId` and `.own`, and `PlanLibrary.startOwnDay` and `.isBorrowed` join them. No earlier case changed.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TQ25 | unit | (D76, v1.9) The picker's sections | Wednesday from Monday: "Change Wednesday's exercises" and "For Wednesday 16 September only. The plan does not change."; one section, "Push Pull Legs · this plan" — Push, Pull, Legs in green, orange and purple, filled, Legs checked — and no others section with one plan; the own row "Write a day just for Wednesday", the name "Wednesday's own day", Save "Use for Wednesday". With Upper Lower and a plan of no days: a second section, "Upper Lower" — Upper and Lower in green and orange, outlined, Lower's slot borrowed from it — and none for the plan of no days. Today's: "Change Today's exercises", "For Monday 14 September…", "Write a day just for Today", "Monday's own day", "Use for Today"; tomorrow's title says Tomorrow; no plan, no picker |
| TQ26 | unit | (D76, v1.9) Choosing a day of this plan | Pull on Wednesday writes original Legs, replacement Pull, no `askedOn`, answered, and moves nothing in the plan; the square orange with a purple dot, no ring, filled; the card **Start Wednesday's Pull**; the picker checks Pull. Choosing Legs, the pattern's own, deletes the swap, and the square is purple with no dot. After Legs on Monday, choosing Pull for Wednesday answers the question: the same swap, replacement Pull, answered, still asked on Monday, its ring faint |
| TQ27 | unit | (D76, v1.9) A day of another plan | Lower from Upper Lower on Wednesday: the swap is borrowed; the projection reads `.projected(Upper Lower, 1)`, orange, labelled Lower; the square named Lower, orange, outlined, with the other plan's id and a purple dot; the card Lower, orange, outlined, Deadlift, **Start Wednesday's Lower**, Upper Lower's day 1. Not done by Thursday: missed as Lower on Wednesday, with Upper Lower's id and index for Do it now. Finished on Wednesday: the session is Upper Lower's and orange in History; neither plan's position or anchor moves — Upper Lower's first workout does not anchor it — and no swap is written; the square stays orange and outlined, and the card says **Done Today**. Chosen for today: `StartCard` is `.nextUp` Upper of Upper Lower, and the card Upper, green, outlined, **Start Today's Upper** |
| TQ28 | unit | (D76, v1.9) A day just for the date | `valid/fenced-with-prose.txt` is accepted as day A (Row), with no weekday; a nameless day is named "Wednesday's own day"; a day with no exercises is refused with the importer's own codes and sentences; `valid/array-of-days.json`, two days, is refused. Chosen for Wednesday: the swap holds the `Day`, the plan still has three days, and the picker's own is it; the square named A, no colour, outlined, carrying the day; the card A, no colour, outlined, Row, **Start Wednesday's A**, `ownDay` set and no `dayIndex`; missed on Thursday it carries the day for Do it now; a nameless one's button is **Start Wednesday's own day**. Chosen for today: `StartCard.own` and **Start Today's A**. Started on Wednesday: the active plan's session named A, with Row; finished, the plan does not move, no swap is written, and the session has no colour |
| TQ29 | device | (D76, v1.9) The outline on the phone | An outlined square beside filled ones on the strip reads as a square at the strip's size, shown and not, in light and in dark — a borrowed day's in its plan's colour, an own day's in ink — and so does Today's square before the name |

### Q5 — The JSON sheet, redone (D77)

`JimmsBroTests/JSONEditTests.swift` (TQ30–TQ32). `JSONPoint` (`Core/JSONPoint.swift`) — the kind, title, place, template, Save and hint, `operation(_:)` and `marks(for:in:)` — is built by `FragmentTarget.point(_:)` in Plan detail and by `dayChoices` for the own day (`DayChoices.point`, in place of Q4's `ownFooter` and `saveTitle`); `JSONLocator` (`Core/JSONLocator.swift`) finds a path's line; `PlanEdit.located(_:as:)` is `fragment(_:as:)` keeping where each value was read. TQ25 now reads Save from `DayChoices.point` and checks its title and place; W17's message no longer speaks of the template's blank name. No other earlier case changed.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TQ30 | unit | (D77, v1.9) Every point opens on text it can save | On Push Pull Legs and `valid/weekly-weekday.json`: the exercise's and the day's own text, saved over themselves, change nothing; Exercises to add saved as it opens adds a Push-up of 3 × 8-12; A day to add adds the next "Day N" holding it, with a free weekday on the weekday plan; the own day's example is read by the importer as "Wednesday's own day" with a Push-up, and has no plan operation; the date's own day opens on itself |
| TQ31 | unit | (D77, v1.9) Titles, places and Save | On Push Pull Legs: One exercise · "Bench Press, exercise 3 of 5 in Push" · Replace Bench Press; One day · "Push, day 1 of 3 in Push Pull Legs" · Replace Push; Exercises to add · "Added at the end of Push" · Add to Push; A day to add · "Added at the end of Push Pull Legs" · Add to Push Pull Legs; A day just for Wednesday · "For Wednesday 16 September. Not saved to Push Pull Legs." · Use for Wednesday. Edits open on the part's own rendering and additions on the example (a rotation's new day without a weekday, the own day nameless); each Save is D43's operation on the right part; a point past the plan's end is nil |
| TQ32 | unit | (D77, v1.9) The error at its line, or nowhere | `JSONLocator`: `days[0].exercises[1].sets[0].reps` in a rendered plan is the line `"reps": 11,`; in a written exercise, a member's key line (not its value's) and an element's first line, CRLF counted as lines; nil for the empty path, a missing key, an index past the end, a path through a scalar, an unclosed index, a fenced fragment with prose, a trailing comma, curly quotes and a key written twice. Through a point: a day's bad reps at `days[1].exercises[1].sets[0].reps` marks line 5 of the day with "The reps need to be a number, a range like 8-12, or AMRAP."; an exercise's bad weight, the second of two exercises to add, a day inside a pasted plan and an own day's `exercises[0].reps` each mark their own line; prose around the day, two exercises where one goes, a day gathered from loose exercises and `cycle[2]` mark nothing and keep the sentence, with its place, under the box |
| TQ33 | device | (D77, v1.9) The marked line on the phone | Edit a day as JSON, break a number and Save: the line is tinted with a red bar at its edge, the sentence beneath it pushes the lines below down rather than covering them, the box scrolls to it, and typing unmarks it — at the default size and at accessibility XL, in light and in dark |

### Q6 — Plans speak in squares (D78)

`JimmsBroTests/PlansTests.swift` (TQ34–TQ37). `PlanText` — `howOften(_:)`, `toUse(marked:activePlanId:plans:)` and `useTitle(_:)` — `RepeatBlock.squares(_:today:calendar:)` and `PlanPage.rows(_:)` are Core's (`Core/PlanPage.swift`); `PlansView` draws the rows with their circles and the button, and `PlanDetailView` the squares and the rows. Y13's Add plan pin now reads the list's top-right button (`Button("Add plan") { addPlan = .plan }`), the bottom slot being Use's. No other earlier case changed.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TQ34 | unit | (D78, v1.9) How often, and the button | `howOften`: "6 days a week" (Push Pull Legs, a seven-entry rotation), "4 days a week" (a weekday plan of four), "3 days every 10", "Every day" (a cycle of one, and seven workouts in seven), "1 day a week" (a weekday plan of one, and one workout in seven), "1 day every 2" for an entry naming no day beside one that does, nil for no days and for nothing but rest. `toUse`: nil with nothing tapped and with the active plan's own circle marked, the marked plan otherwise — with no plan active too — and nil for a plan deleted since; `useTitle` is "Use Upper Lower" |
| TQ35 | unit | (D78, v1.9) The cycle as squares | Push Pull Legs on Monday 14 September: Push, Pull, Legs, Rest, Push, Pull, Legs in green, orange, purple, grey, green, orange, purple — `DayColour.cycle(of:)` exactly — with no weekdays and the first marked; on Thursday's rest the fifth, Friday's Push, is marked. A weekday plan: Mon…Sun above; Upper A, Lower A, Rest, Upper B, Lower B, Rest, Rest beneath; green, orange, grey, purple, pink, grey, grey; none marked |
| TQ36 | unit | (D78, v1.9) The page's rows | Push Pull Legs: Push, Pull, Legs, Rest, Push, Pull, Legs, opening days 0, 1, 2, none, 0, 1, 2, with ids 0–6; the third and seventh open the same exercises and the rest opens nothing. A weekday plan: Monday…Sunday, each with its day or Rest. A rotation whose cycle names a missing day and never reaches Arms: …, Rest, Rest, Arms (pink, day 3); a plan with no cycle opens every day; no days, no rows |
| TQ37 | unit | (D78, v1.9, pin) The circle is the one way | `PlanDetailView` has no "Use this plan" and no `setActivePlan`, and draws `RepeatBlock.squares(plan)` and `PlanPage.rows(plan)` and no `RepeatBlock.chips(`; `PlansView` draws `CycleSymbol(cycle: DayColour.cycle(of: plan))`, `PlanText.howOften(plan)`, both circles, `PlanText.toUse(` and `PrimaryButton(title: PlanText.useTitle(`, calls `setActivePlan`, and has no `NavigationLink(` (source reads on the host routes) |
| TQ38 | device | (D78, v1.9) The page and the list at accessibility XL | The squares row wraps with every name legible, an open day keeps its Start reachable, and a list row's symbol stands above its name — in light and in dark |
| TQ39 | device | (D78, v1.9) A mark left unconfirmed | Mark another plan's circle and see **Use *name***; go back to Today without tapping it and return to Plans: the active plan's circle is filled, there is no button, and Today runs the plan it ran |

## TP. v1.10 — The Workout screen in symbols

`docs/ITERATION_11_PLAN.md` is the plan; one subsection per milestone that lands a decision. TQ was v1.9's, so the prefix is **TP**. The plan's proposed ids are kept where they land as proposed; where one changed, the subsection says so.

### P1 — Three states, three colours (D79), and the header is the bar (D80)

`JimmsBroTests/SymbolsTests.swift` (TP1–TP6), on the plan's example: Push Pull Legs, Push's Barbell Bench Press 4 × 6–8 at 80 kg, Incline Dumbbell Press 3 × 8–10 at 26 kg, Lateral Raise 3 × 12–15 at 10 kg, Tricep Pushdown 3 × 10–12 at 30 kg and Plank 3 × 30+ s; Bench logged, Incline's first set logged at 10, and the rest before its second running. `MarkState` is `Core/WorkoutMarks.swift`'s, `MarkState.of(step:session:)` and `WorkoutBar` are `Core/WorkoutBar.swift`'s, `ActiveSession.currentStep` is the one "step the workout is on" (the engine's and `AppModel`'s read it), `SetRow` gained `mark`, and `WorkoutScreenModel` gained `bar` and `spokenHeader`. Two earlier cases changed: **T21** counts three ungated rows of §6.40's table — the bar's tap joins the strip and the swap's marks — and **T23** reads the `DayColour` mapping of `DaySquare.swift` alone, since the same file now maps a mark's state and *now* is the accent there (TP2). **TP6** was proposed as a ui case; it landed as a source pin, run on the host routes, with the drawing looked at on the simulator (BUILD_STATUS). TP3's "thirteen todo" in the plan was a miscount: sixteen sets less five done and one now is ten.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TP1 | unit | (D79, v1.10) One rule for every step | On the example: Bench's and Incline's logged steps `done`; step 5, the one the rest leads to, `now`; the steps ahead and a step that does not exist `todo`. Skip step 5: it is `todo` and step 6, the working step, `now`. Give step 5 a result: `done`, and step 6 still `now`. One step is `now` among all sixteen; the states are `done`, `now`, `todo`; Incline's rows carry `done`, `done`, `now` |
| TP2 | unit | (D79, v1.10, pin; extends T23) Three state colours | `DaySquare.swift`'s `MarkState` mapping has three cases — done `day?.color ?? DaySquare.noColour`, now `.accentColor`, todo `Color(.secondarySystemFill)` — and names no red, yellow, orange, amber or green; `noColour` is `Color.secondary.opacity(0.4)`, the grey History draws; the Lock Screen's bar tints `MarkState.done.color(day: state.dayColour)` and names neither the accent nor green (source reads on the host routes) |
| TP3 | unit | (D80, v1.10) The bar on the example | Five segments with 4, 3, 3, 3, 3 marks and the same weights, block indices 0–4 — the model's bar is `WorkoutBar.of`'s; Bench done ×4, Incline done, now, todo; five done, one now, ten todo; the caret under Incline alone. `showing: 3` moves the caret to Tricep Pushdown and changes no mark; Do later on Lateral Raise orders the segments 0, 1, 3, 4, 2 |
| TP4 | unit | (D80, v1.10) A skipped set fills but draws not yet | Skipping Incline's second set moves the day's completion from 5/16 to 6/16, and Incline's marks read done, todo, now — still five done on the bar |
| TP5 | unit | (D80, v1.10; extends O50) The header speaks the stage | In the warm-up, working, resting, between exercises and a running timed set: the five zones in order, five segments, one caret and one `now`, and `spokenHeader` is `stage.title` — "Warm-up", "Exercise 1 of 5 · Set 1 of 4", "Resting", "Between exercises"; the walk's caret is under the exercise it leads to, the timed set's under Plank |
| TP6 | unit | (D80, D79, v1.10, pin) No words in zone 1 but the elapsed time | Zone 1 of `WorkoutView.swift`, comments aside, has one `Text(` — `Text(screen.elapsed)` — and no `stage.title`, `progressLine`, "Exercises", `ProgressView` or percentage; it draws `BarView(bar: screen.bar, day: dayColour)`, the day's square, ⌄ and ···, speaks `screen.spokenHeader`, and sets `showOverview = true`. The screen's `PrimaryButton` is `ink: true`, the screen is tinted `.primary`, and the bar is a `Canvas` (source reads on the host routes) |
| TP7 | device | (D80, v1.10) The bar at sixteen sets on a 6.1-inch screen | Ticks visible, gaps visible, the blue mark findable at arm's length — in light and in dark |

### P2 — The exercise in symbols (D81)

`JimmsBroTests/SymbolsTests.swift` (TP8–TP15), on the same example, with last week's Push — Incline 10, 9, 8 — as history where last time matters. `RepCells` is `Core/RepCells.swift`'s; `SetDot`, `SetCard` and `WorkoutScreen.notes` are `Core/WorkoutScreen.swift`'s; `MarkState.of(exercise:session:)` is beside `of(step:)`. `WorkoutScreenModel` lost `targetLine` and `rows` and gained `exerciseMark`, `notes`, `dots`, `card` and `editing`; `SetRow` lost P1's `mark`, which nothing sets now. Five earlier cases changed, each keeping its assertions: **O57** and **U34** read `StepCard.setRows` directly rather than through the screen, **U35** reads `targetLine` and `setRows` for the two notations and checks the card and dots are the same under both, **W7** reads the ? and the Overview's line, and **TP1** reads Incline's dots where it read its rows. **TP13** also carries the strip's Undo — during the rest the set started, not after — which the plan left unnumbered. **TP15** was proposed as a ui case and landed as a source pin, as TP6 did.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TP8 | unit | (D81, v1.10) `RepCells.target` | 8–10 at 10 reps: ten cells, eight solid, two faint, the caret under the tenth, groups 0 × 5 then 1 × 5, none yellow, no line. At 12: twelve cells, the eleventh and twelfth yellow and faint, the caret under the twelfth. At 6: ten cells and the caret under the sixth; no number, no caret. 8 alone: eight solid. A minimum of 10 with no top: ten solid; at 13, three faint and none yellow. Last time 11 on 8–10: eleven cells, the line over the eleventh. 999 reps: sixty cells. `Bounds.of`: a fixed 10 in 8–12 is 8–12; a fixed 5 is 5–5; AMRAP is 0 with no top; 45 s is 45–45; an open hold of 30 is 30 with no top. `SetCard.range`: "8–10", "8", "10+", "max" |
| TP9 | unit | (D81, v1.10) `RepCells.logged` | 12 on 8–10: twelve cells, ten solid and two yellow solid, no caret; 6: ten cells, six solid, four faint, none yellow |
| TP10 | unit | (D81, v1.10) `RepCells.timed` | Five seconds a cell. 30–45 s: nine cells, six solid, three faint, no caret; 50 s logged: ten solid, the tenth yellow; 32 s: seven cells; last time 41 s: the line over the ninth |
| TP11 | unit | (D81, v1.10) The card and last time | On the example with last week: range "8–10", weight "26 kg", no unit, colour `now`, `lastTime` 9 and the line over the ninth cell, the caret under the cell of the number in the field; `showing(field: 7)` moves the caret to the seventh and keeps the line and ten cells. With no history: no `lastTime`, no line. Plank's card: "30+", "sec", no weight, six cells, no caret |
| TP12 | unit | (D81, v1.10) The dots | Bench with three logged: done, done, done, now. The example: Incline's steps 4, 5, 6 as done, now, todo, spoken "Set 1 of 3, done", "Set 2 of 3, now", "Set 3 of 3, not yet"; the exercise's dot `now`, Bench's `done`, Lateral Raise's `todo`. Skip step 5: todo slashed between done and now, "Set 2 of 3, skipped"; skip Incline: its dot `todo`. Two sets with a lighter set each: four dots. A superset of two × two, one logged: steps 0–3 as done, now, todo, todo, and the name is Row |
| TP13 | unit | (D81, v1.10) Changing a logged set in place | Resting after Incline's first set: no `editing`, Log set, "Set logged · Undo". `editing: 4`: Save (`.save`), the inputs "10" and "26" with the weight shown, no seconds, no chip; the card `done` with ten solid cells, twelve in the field draws two yellow; the step still 5, the dots and zones unchanged. `editing` 6 (pending), 0 (Bench's) and 99: ignored, Log set. `.editSet` to 9 × 26: the result changes, the card is `now` on step 5 with Log set, and the rest still runs. Skip the rest: `canUndo` still, and no Undo in the strip. A logged 40 s hold: `editing: 0` takes "40" as seconds, no weight, no timer, a "sec" card of eight cells — without `editing` the timer is back; undo the hold and `editing: 0` is ignored |
| TP14 | unit | (D81, v1.10) The ? | Incline with no notes and no change: nil. Notes "  Bench at 30°.  ": "Bench at 30°."; whitespace alone: nil; a change from Barbell Row: "was Barbell Row", with notes after it on the next line; a plan's Bench with notes: the screen's `notes` are them |
| TP15 | unit | (D81, v1.10, pin) No sentence in zone 2 | Zone 2 of `WorkoutView.swift`, comments aside, has one `Text(` — `Text(screen.exerciseName)` — and no `targetLine`, `screen.rows`, `SetRowView`, `InsetGroup` or string literal in a `Text`; it draws `SetCardView(card: screen.card.showing(field: InputRules.repsValue(repsText)), day: dayColour)`, `NotesButton`, `DotView`, the history route and the spoken line, jumps on a grey dot and edits on a filled one. `SetCardView` has three `Text(`s: the range, the unit, the weight. The file has no `EditResultSheet`, applies `.editSet` on Save, and shows the strip's Undo at every size (source reads on the host routes) |
| TP16 | device | (D81, v1.10; extends D56's row) Zone 2 at accessibility text sizes | At accessibility XL on a 6.1-inch phone: a long range's cells wrap inside the card, the dots wrap, and the inputs and Log set stay on screen — in light and in dark |

### P3 — The walk: a count-up and a ring (D82)

`JimmsBroTests/SymbolsTests.swift` (TP17–TP22), on two lifts of one set each so a log ends a block, with the plan's walk as each case gives it; and the manifest through `ImportTests` and `tools/reference_import.py`, with three new fixtures — `valid/rest-between-exercises.json` (90, with its rests and the step that ends the block checked), `valid/rest-between-exercises-string.json` (`"90"`) and `invalid/rest-between-exercises-negative.json` (-1) — and a new manifest check, `restBetweenExercises`, which `rest-precedence.json` also carries as null. The plan's one proposed fixture became three, one per case of TP18, so both importers read each. The plan named the code `E_REST_NEGATIVE`; the format's code for every bad rest is `E_REST_INVALID`, and that is the one reused. Three earlier cases changed, each noted on its row: **Q25**, **Q27** and **O61**.

| ID | Kind | Case | Expected |
|---|---|---|---|
| TP17 | unit | (D82, v1.10) The walk is the plan's, then the setting's | `RestResolution.after` between blocks: `.blockDone(rest: 90)` with the plan's 90 and the setting's 120; 120 when the plan has none; 0 from the plan's zero and from the setting's; a rest between sets stays the set's 45. Through `PlanLibrary`: logging the block's last set of a plan with 90 starts a `betweenExercises` rest ending at +90, and the engine's `walk` is (90, from the plan). A day's estimate with the plan's 600 equals one with the setting's 600 |
| TP18 | unit | (D82, v1.10; extends the manifest) The format reads the walk | The fixture imports with 90 and no `W_UNKNOWN_FIELD`, its sets' rests stay 60; `"90"` imports as 90; `rest-precedence.json` has nil; -1 has no plan and `E_REST_INVALID` at `restBetweenExercises`. The plan prompt carries `"restBetweenExercises": 120` and its rule, the outline prompt the rule, the day prompt neither; the example JSON has it and still imports (M9). The manifest's check agrees with `reference_import.py` (118/118) |
| TP19 | unit | (D82, v1.10) On disk | The frozen `examples/store/v1/plans.json` decodes with every plan's walk nil; a plan with 90 round-trips through `StoreCoder` equal, one without stays nil; `PlanJSON.render` writes the field only when it is set; a rename and a day replaced as JSON both keep 90 |
| TP20 | unit | (D82, v1.10) The strip between exercises | At 0, 45 and 90 s of a 90 s walk: kind `.blockDone`, `restKind` `.betweenExercises`, direction up, figure 0:00, 0:45, 1:30, fraction 0, ½, 1, full only at 1, no rest controls, next "Row", primary Log set; the colour red, amber, green; the spoken line leads "Between exercises, 0:45. at least 1:30. next, Row". After `restElapsed` at 90: working, and at 200 s the figure 3:20, full, minimum 90, still up, no controls. `adjustRest` and `skipRest` change nothing on the walk, and the warm-up keeps its controls. Log set clears the block's line; Start timer on a timed next set clears it too and the strip is `.timed` with no ring. A zero walk: working at once, the ring full, 0:00. The Lock Screen's state during the walk and after has no `endsAt`, starts at the walk's start, counts up, titled "Between exercises", a break |
| TP21 | unit | (D82, v1.10; extends Q25's notification) The alert is at the ring's end | Logging the block's last set with a 90 s walk schedules the rest notification at +90; `restElapsed` at +90 plays the end alert |
| TP22 | unit | (D82, v1.10) The ring explains itself | `RestText.ringExplanation`: "At least 2:00 between exercises. Your plan's minimum — when the ring is full, you're ready."; with the setting's 90, "At least 1:30 … Your minimum in Settings — …"; with 0, "No minimum between exercises. The ring starts full — go when you're ready."; `WalkRing.explanation` is the same sentence |
| TP23 | device | (D82, v1.10) The ring on the phone | The ring's hue at 0, ½ and 1 reads red, amber and green on a Push day and on a Pull day beside the orange, in light and dark; the check appears at the minimum, the count-up keeps going, and a tap on the ring shows its sentence |

## K. Persistence and recovery (SPEC §8)
| ID | Type | Case | Expected |
|---|---|---|---|
| K1 | unit | Save then load plans | Equal |
| K2 | unit | Save is atomic: temp file replaced; no partial file on simulated failure mid-write | Old file intact |
| K3 | unit | Corrupt `plans.json` (garbage bytes) | Renamed to `plans.json.corrupt-<t>`; store loads empty; `corruptFiles` reports it |
| K4 | unit | Corrupt one of 5 session files | 4 load; 1 set aside |
| K5 | unit | `fileVersion: 99` | Treated as corrupt (set aside), not crash |
| K6 | unit | Missing directory on first launch | Created |
| K7 | unit | Active session written after each event | File on disk decodes to the engine's current state |
| K8 | unit | Complete session | `active-session.json` removed; `sessions/<id>.json` exists |
| K9 | unit | Discard session | `active-session.json` removed; no session file; notification cancelled |
| K10 | unit | Dates round-trip through ISO-8601 with fractional seconds | Equal to the millisecond |
| K11 | unit | Encoder uses sorted keys | Same value → byte-identical output |
| K12 | unit | 1000 session files | Load under 1 s on simulator |
| K13 | unit | Export JSON | Contains settings, all plans, all sessions; decodes back into the same types |
| K14 | unit | Delete all data | Directory empty except nothing; in-memory state reset; active plan nil |
| K15 | unit | Two rapid writes | Serialized by the actor; last write wins; no interleaving |
| K16 | manual | Kill app mid-workout, relaunch | Resume banner with correct elapsed; Resume restores exact step and inputs' prefill |
| K17 | manual | Reinstall from Xcode over the existing app | Plans and history still present |
| K18 | unit | (D24, v1.1) `store.save(session:)` when its directory can't be created | Throws (a genuine error, not a silent no-op); succeeds once unblocked |
| K19 | unit | (D24, v1.1) A session's completion write fails (its directory blocked) | `AppModel.saveFailure == .session(that session)`; the session's id is **not** added to `persistedSessionIds`; `active-session.json` **survives**; `retrySaveFailure()` after unblocking clears the failure, persists the session and then clears `active-session.json` |
| K20 | unit | (D24, v1.1) Launch with an `active-session.json` whose `phase` is already `.completed` (a prior run's file-clear didn't finish) | The session ends up in `sessions/` (added if missing); `active-session.json` is removed; `hasActiveSession == false` — recovered, not resumed, not lost |

| K22 | unit | (D31, v1.1) Read a backup | Reports its date, app version, plan and workout counts, and how many of each a Merge would add; the store is unchanged until a mode is chosen |
| K23 | unit | (D31, v1.1) Restore with **Replace all** | The store ends holding exactly the backup: its plans, its workouts, its active plan and its settings, and nothing that was there before |
| K24 | unit | (D31, v1.1) Restore with **Merge** | Only ids not already present are added; a workout edited here since the backup was taken is left alone; the active plan and the current settings are untouched |
| K25 | unit | (D31, v1.1) A file that isn't a backup, or is from a newer app | Refused with a message before anything is written; `.notABackup` / `.unsupportedFileVersion` |
| K26 | unit | (D31, v1.1) Restore through `AppModel` | A running workout is discarded first, the store is reloaded, and the app shows what was written; an unreadable file comes back as a message and changes nothing |

## L. Plans, active plan, rotation, weekday (SPEC §6.8)
| ID | Type | Case | Expected |
|---|---|---|---|
| L1 | unit | Import into empty library | Becomes active |
| L2 | unit | Import when another plan is active | Not active until chosen (UI asks) |
| L3 | unit | Import with the same normalized name ("push pull legs" vs "Push Pull Legs") | Conflict detected; Replace keeps id and pointer-by-name; Keep both → "Push Pull Legs (2)" |
| L4 | unit | Rotation, pointer nil | Next up = days[0] |
| L5 | unit | Rotation 3 days, pointer 2 | Next up = days[0] (wrap) |
| L6 | unit | Complete days[1] when pointer was nil | Pointer = 1; next up days[2] |
| L7 | unit | Complete a day picked out of order (days[2] while next was days[0]) | Pointer = 2 while nothing was completed yet (the first workout anchors the pattern); once anchored, since v1.9 (D72, §6.46) the pointer stays and a swap is written — `LibraryCalendarPromptTests` asserts 0 and one swap where it asserted 2 until v1.8 (TQ4) |
| L8 | unit | Complete a session with skips | Pointer advances |
| L9 | unit | Discard a session | Pointer unchanged |
| L10 | unit | Complete a session whose plan was deleted | No crash; nothing updated |
| L11 | unit | Complete a session whose day name no longer exists in the plan (plan replaced) | Pointer unchanged |
| L12 | unit | Replace plan; old pointer pointed at "Pull" which is now index 3 | Pointer = 3 |
| L13 | unit | Replace plan; "Pull" gone | Pointer nil |
| L14 | unit | Weekday plan, today Wednesday, has a Wednesday day | Today = that day |
| L15 | unit | Weekday plan, today Tuesday, days Mon/Wed/Fri | "Rest day", next = Wed |
| L16 | unit | Weekday plan, today Saturday, days Mon/Wed/Fri | Next = Mon (wraps the week) |
| L17 | unit | Weekday lookup uses the device's local time zone and calendar | Test with a fixed calendar/time zone injected |
| L18 | unit | Delete plan with sessions | Sessions remain; their planName still displays |
| L19 | unit | Delete the active plan | Active becomes nil (or the only remaining plan if exactly one remains) |
| L20 | unit | Two sessions same day | Both saved and listed |
| L21 | unit | Start a day while an active session exists | Allowed only through the D17 popup; `startDay` without the flag throws `sessionInProgress` |
| L22 | unit | Cycle [P, Pu, L, P, Pu, L, rest], position nil | Next up = P (index 0) |
| L23 | unit | Position 2 (L) | Next up = P at index 3 |
| L24 | unit | Position 5 (L) | Next up = P at index 0 (rest at 6 skipped, wraps) |
| L25 | unit | Complete "Pull" from position 0 | position = 1 (first Pull after 0) |
| L26 | unit | Complete "Pull" from position 3 | position = 4 |
| L27 | unit | Complete "Legs" from position 5 | position = 2 (wraps) |
| L28 | unit | Complete a day not in the cycle | position unchanged |
| L29 | unit | Replace plan; old position pointed at "Pull", new cycle has Pull at index 4 first | position 4; Pull gone → nil |
| L30 | unit | Calendar, weekday plan Mon/Wed/Fri, month view | projected on every future Mon/Wed/Fri, ≤ 62 days ahead |
| L31 | unit | Calendar, rotation cycle with rest, position 2, today Tue | Wed = entry 3, Thu = 4, Fri = 5, Sat = rest (none), Sun = entry 0 … |
| L32 | unit | Calendar, rotation cycle without rest | only tomorrow projected |
| L33 | unit | Calendar, day with 2 completed sessions | `.completed([2 sessions])` |
| L34 | unit | Calendar, today with a completed session | `.completed`, not projected |
| L35 | unit | Calendar uses the injected today/time zone | Deterministic in tests |
| L36 | unit | (D26, v1.1) Import a second plan with the preview's activation choice off, then a third with it on | The second does not change `activePlanId`; the third does; both persist and survive reload |
| L37 | unit | (D25, v1.1) Plan detail's Replace, given a plan whose new JSON renamed it entirely | Keeps the same id (no second plan created); keeps active status if it was active; persists; a missing id is a no-op |
| L38 | unit | (D18, v1.1) Start a weekday plan's next day early from a rest day | `HomeStart` targets that day, and starting it runs that day's session |
| L39 | unit | (D29, v1.1) Edit an exercise's name, sets, reps, rep range, weight and rest | Each goes through the import pipeline; the plan keeps its id, importedAt and cycle position, and `sourceText` is regenerated so Copy JSON and the export file match |
| L40 | unit | (D29, v1.1) Reorder and delete exercises within a day | The order changes as asked; deleting leaves the rest untouched |
| L41 | unit | (D29, v1.1) Duplicate a day | A copy named "<day> copy" is inserted after it with its own ids; the cycle is deliberately unchanged |
| L42 | unit | (D29, v1.1) An edit the import pipeline would refuse | Refused with errors, and the plan is left exactly as it was — a blank name, 0 or 51 sets, unparseable reps, rest outside 0–3600, a backwards rep range, an out-of-range index, or deleting a day's last exercise |
| L43 | unit | (D29, v1.1) The reps field's vocabulary | Accepts a number, "8-12", "8–12", AMRAP, "5+", "45s", "30s+" and "open"; refuses everything else |
| L44 | unit | (D29, v1.1) An edited plan still flattens and runs | Changing the set count changes the step count by the same amount, and the session logs normally |
| L45 | unit | (D29, v1.1) `PlanEdit.text(for:)` and `parseWork` are inverses | Every `WorkTarget` prints as text that parses back to the same value, so opening the edit sheet on a timed set and saving cannot turn it into a rep set |

## M. Prompt rendering (docs/PROMPT.md)
| ID | Type | Case | Expected |
|---|---|---|---|
| M1 | unit | Render with units lb, rest 120 | `"units": "lb"`, `"defaultRestSeconds": 120`, "a number in lb" |
| M2 | unit | Rendered prompt contains marker line first | True |
| M3 | unit | Rendered prompt under 4,000 characters | True |
| M4 | unit | The JSON example inside the prompt imports cleanly through the pipeline | Zero errors, zero warnings |
| M5 | unit | Fix-it prompt with 3 errors | Three "- path: message" lines; marker present |
| M6 | unit | Fix-it prompt with 25 errors | 20 lines + "…and 5 more" |
| M7 | unit | Fix-it prompt for `E_NOT_JSON` | Includes the decoder message |
| M8 | unit | (D26, v1.1) Every error code in PLAN_FORMAT §4 has a friendly sentence | `IssueText.friendly` returns a non-empty sentence for each, distinct from the raw code, and an unknown code falls back to the importer's own message rather than to nothing |

## N. Settings, units, input parsing
| ID | Type | Case | Expected |
|---|---|---|---|
| N1 | unit | Default units by locale: en_US → lb; en_GB, de_DE, fr_CA → kg | As listed |
| N2 | unit | Weight step default: kg → 2.5, lb → 5 | As listed |
| N3 | unit | Weight text "62,5" and "62.5" | 62.5 |
| N4 | unit | Weight text "62.55" | 62.6 on commit |
| N5 | unit | Weight text "abc", "1.2.3", "-5" | Rejected (field keeps last valid) |
| N6 | unit | Reps text "1000" (4 digits) | Truncated to 3 digits by the field |
| N7 | unit | Weight − from 2.5 with step 2.5 | 0; − again stays 0 |
| N8 | unit | Default rest setting 0 | Allowed; plans without rest get 0 |
| N9 | unit | Changing units setting after plans exist | Existing plans unchanged; only the prompt and unit-less future imports change |
| N10 | unit | Settings file missing | Defaults used and written |
| N11 | ui | (D26, v1.1) Import preview's "Set as current plan" toggle | Present and on by default when another plan is already active; hidden during Plan detail's Replace (which already preserves active status) |

## O. UI, accessibility, device (mostly manual)
| ID | Type | Case | Expected |
|---|---|---|---|
| O1 | ui | Empty Home | Two links; "Try the sample plan" imports and activates the sample. **v1.4 (D46)**: the link is "Choose a built-in plan" and opens the picker (Y10, Y11); `importSamplePlan` remains for the seeder and the screenshots |
| O2 | ui | Import screen Paste with text on clipboard | Editor filled |
| O3 | ui | Paste with an image on clipboard | Nothing happens; PasteButton disabled or no-op |
| O4 | ui | Import error list | Each row shows path, message, code; Copy fix-it button present |
| O5 | ui | Preview shows warnings in yellow and day table | Correct counts |
| O6 | ui | Name conflict dialog | Replace / Keep both / Cancel work |
| O7 | ui | Step card renders every target kind | "8–12 reps @ 60 kg", "10 reps (range 8–12) @ 60 kg", "AMRAP", "10+ reps", "45 s" |
| O8 | ui | Log set with empty reps | Button disabled |
| O9 | ui | Step card order and fit: name, target, last-time (bold entry), reps row, weight row + Last/Suggested line, Log set; all visible above the keyboard on an iPhone 15/16 at default text size | True; Log set never hidden by the keyboard |
| O9b | ui | Tapping the reps number opens the number pad; tapping the weight number opens the decimal pad; ± buttons don't open a keyboard | True |
| O9c | ui | Rest overlay shows workout elapsed; after an exercise's last set it also shows "Bench Press done · 9:40" and the advice line | True |
| O9d | ui | Overview list shows duration and advice on finished exercises | True |
| O9e | ui | Summary per exercise shows duration, this vs last, advice | True |
| O29 | ui | Home shows exactly three things: start card, calendar, sparkline; tab bar has four tabs | True; no other controls |
| O30 | ui | Calendar dots: filled accent for completed, hollow accent for projected, grey for a scheduled rest day, none for a day the plan says nothing about; today outlined | True; tapping a dotted day shows one line beneath |
| O31 | ui | Sparkline is ≤ 44 pt tall, no axes, one caption line; tapping it changes the metric and caption | True |
| O32 | ui | Done screen after an exercise: block name, duration (largest), advice, running stopwatch, one Continue button | True; no countdown, no sound, no notification |
| O33 | manual | Lock the phone on the done screen for 5 minutes | Nothing fires; on unlock the stopwatch reads ~5:00 |
| O34 | ui | Drop step card shows "Set 2 of 3 · drop 1 of 2" and weight prefilled from the previous step | True |
| O35 | ui | Plan detail shows the repeat block chips with the current position highlighted and "repeats every N days" | True |
| O36 | ui | Start another day mid-session | Popup with Keep going (default), Finish X and start Y, Discard X and start Y |
| O37 | ui | Step card has no visible label text other than exercise name, set line, target, last-time, and the "kg" suffix; secondary actions only in "···" | True |
| O38 | ui | Preview sheet shows cycle chips | True |
| O39 | ui | Bodyweight exercise step card | No weight row; card is shorter; Log set still under the reps row |
| O40 | ui | Open-duration card: 0:00 large, Start; running: counting up, Stop | Stop logs; the "30+" minimum turns the number accent at 30 |
| O41 | ui | Fixed-duration card: 0:45 large, Start; running: countdown, Done | Number turns accent at the warning; at zero: final beep, auto-log, rest |
| O42 | ui | Rest overlay top line shows "set 0:34" after a rep set | True |
| O43 | ui | Overview and session detail show set time per logged step | "10 @ 60 · 0:34" |
| O44 | ui | (v1.1) Tap a completed calendar day, then tap it again | First tap shows the summary line; second tap opens that session's detail |
| O45 | ui | (v1.1) Tap-then-tap-again a day with two completed sessions | A chooser lists both by day name and time; picking one opens it |
| O46 | ui | (D27, v1.1) Overview: tap a skipped row | Offers **Do this set** (jumps to it, cancelling rest/blockDone) and **Add result** (opens the edit sheet); saving through Add result survives reopening the session |
| O47 | ui | (D25, v1.1) Swipe-to-delete in Plans and History, and Plan detail's Delete | Every path confirms with one dialog before deleting; cancelling leaves the row untouched |
| O48 | ui | (D14, v1.1) After a block finishes, no full-screen "done" gate appears | The next step's card shows immediately, with a dismissible banner naming the finished block, its duration and any advice — a temporary placeholder for R2's status strip |
| O49 | ui | (D23, v1.1) The workout's "···" menu after logging a set | Offers **Undo last set**, which restores it to pending with its inputs re-prefilled; the item is absent once another set is logged or the session is completed — a temporary placeholder for R2's "Set logged · Undo" strip |
| O10 | ui | Overview list statuses and tap-to-edit / tap-to-jump | Work as SPEC 4.4 |
| O11 | ui | Finish with pending sets | Confirmation names the count |
| O12 | ui | Finish with nothing logged | "Nothing was logged. Discard?" |
| O13 | ui | Summary comparison lines | Match J25's sentences; the set-by-set table appears only when the weights varied |
| O14 | ui | History grouping by month, newest first | Correct |
| O15 | ui | Edit a value in a past session | Saved; volume updates; prefill next time uses it |
| O16 | ui | Exercise history reachable from step card, session detail, and summary | All three |
| O17 | ui | Dark mode | All screens legible; timer colors distinct |
| O18 | ui | Dynamic Type at accessibility XL | Log button still on screen; no text clipped |
| O19 | ui | VoiceOver reads step card as one element and announces "Rest over" | True |
| O20 | manual | Screen stays awake during workout; turns off normally after Done | True |
| O21 | manual | Keep-awake setting off | Screen locks per system setting |
| O22 | manual | Rotate the phone | Stays portrait |
| O23 | manual | Sweaty-thumb test: all workout controls ≥ 44 pt and reachable one-handed | True |
| O24 | manual | Free-account 7-day expiry: app refuses to open after a week | Re-run from Xcode restores it with data intact |
| O25 | manual | Full end-to-end: copy prompt → ChatGPT → paste → import → 3-exercise workout with a superset and a plank → summary → history | Works without touching a keyboard except reps/weight |
| O26 | manual | Chatbot output truncated (long weekly plan) | `E_NOT_JSON` with "end of file" message; fix-it prompt gets a complete plan back |
| O27 | manual | Chatbot added `rpe` and `tempo` fields | Imports with warnings, no errors |
| O28 | manual | Chatbot wrote weights as "60kg" strings | Imports; no warning if unit matches |
| O50 | unit | (D22, v1.1) `WorkoutScreen.model` in the working, resting, timed-running and block-done states | The five zones — header, exercise, inputs, strip, primary — are present in that order in every one of them; only their contents differ |
| O51 | unit | (D22, v1.1) Log a set while the previous set's rest is still running | The set logs, the rest ends, its notification is cancelled, and the following step becomes current |
| O52 | unit | (D23, v1.1) Undo from the status strip | The row goes back to pending, `canUndo` becomes false, and the values that had been logged are handed back so the inputs come back filled |
| O53 | ui | (D22, P2, v1.1) Open **Exercises** while resting, and again while a block-done strip is showing | The overview opens in both; the header's Exercises, minimize and "···" are present in every state |
| O54 | unit | (v1.1) Minimize mid-rest, then Resume | Same step, same prefilled inputs, and rest remaining derived from `endsAt` rather than from a counter that stopped |
| O55 | ui | (P6, v1.1) Keyboard raised over the reps or weight field | A **Done** toolbar item dismisses it, and the primary button sits above the keyboard, not behind it |
| O56 | ui | (P5, v1.1) The input rows | Small-caps **REPS** and **KG**/**LB** labels are visible, and VoiceOver reads each field with that label |
| O57 | unit | (D22, v1.1) `StepCard.setRows` for the current exercise | Finished rows carry what was logged, the current row is flagged with its target and last-time value, upcoming rows carry targets; a superset lists only the current round's members |
| O58 | unit | (D14, v1.1) Run a whole multi-exercise day through, logging every set | The session completes without `dismissBlockDone` ever being applied and without entering any phase but working and resting — zero Continue taps |
| O59 | unit | (v1.1) `.logged` feedback on Log set | Played exactly once per logged set, and not for an edit, a skip, or an input the engine rejected |
| O60 | ui | (P6, v1.1) The workout screen at accessibility XL | No zone clipped or pushed off screen; the input numbers keep their size; the layout reflows around them |
| O61 | unit | (D14, v1.1) The status strip once a block ends | Names the finished block with its duration, carries that exercise's advice, and reports the count-up "moving on" time. *(v1.10, D82: the count-up is the strip's figure, direction up; the block's line stays the title, spoken)* |
| O62 | unit | (D20, D22, v1.1) A timed set's primary action | **Start timer**, then **Done** (fixed) or **Stop** (open), in the same bottom slot the reps sets use; the timer replaces the reps row and the weight row stays |

| O63 | unit | (D18, v1.1) `HomeStart.current` for every schedule state | Rotation and weekday name the day and the plan and read "Start &lt;day&gt;"; a rest day reads "Rest day", says which day is next, and offers "Start &lt;day&gt; early" (*v1.6–v1.8's S2*: the next day's name and **Start Thursday's Lower**; *since S3, D71*: **Rest** and **No exercise Today**, with Thursday's Lower one tap away on the strip); a running session reads "Resume &lt;day&gt; · N min"; no plan reads "No plan yet" with **Add plan** |
| O64 | unit | (D18, v1.1) The start card's exercise preview | Names the day's first five exercises and counts the rest as "and N more"; the subtitle carries the plan name, the exercise count and "N min last time", each only when it has data — since v1.8 (D69) there is no subtitle: the rows count themselves, and the clock reads "48 min" *last time* only when there was one |
| O65 | unit | (D18, v1.1) `CalendarProjection.week(containing:)` | Seven days of the calendar week containing today, with the same entries the month grid gives, including across a month boundary |
| O66 | unit | (D18, v1.1) `HomeActivity.line` | "2 workouts this week · 1 h 32 min"; a week with none reads "No workouts yet this week"; only completed sessions count |
| O67 | ui | (D26, v1.1) Add plan's three rows | Paste plan, Create with a chatbot (three numbered steps), Import file; the JSON editor is behind "Show text" and starts collapsed |
| O68 | unit | (D26, v1.1) The review sheet's day rows | Each day expands to its exercises with per-set targets — "3 × 8–12 · 24 / 26 / 28 kg" rather than the first set repeated |
| O69 | unit | (D26, v1.1) Warning classification | A dropped unit, a removed load, a changed grouping and an inferred schedule are material; curly quotes, unknown fields, truncated names and rounded weights are cleanup, and go behind "Details (n)" |
| O70 | unit | (D26, v1.1) An import error | `IssueText.friendly` leads with a sentence naming where it is ("Day 1, exercise 2, set 2 needs either a rep target or a duration."); path, code and the importer's own message stay behind Details |
| O71 | unit | (D26, v1.1) The practice plan | `PracticePlan.json` imports through the normal pipeline with no errors, three exercises, one bodyweight, 60 s rest, and becomes active |
| O72 | ui | (N12, v1.1) Copy prompt | The button reads "Copied" and goes back to "Copy prompt" about two seconds later, without needing another tap |
| O73 | ui | (P6, v1.1) Calendar cells | Every cell is at least 44 pt in the week strip and the month grid alike |
| O74 | unit | (v1.1) The Summary's headline line | "Push · 48 min · 16 of 18 sets · Volume 12,400 kg"; the volume fragment is omitted entirely when it is zero (a bodyweight day) |
| O75 | ui | (v1.1) The Summary | Leads with "Workout saved"; one sentence per exercise; set durations only under **Details** |
| O76 | unit | (v1.1) Plan detail's exercise rows | Show per-set variation via `TargetText.summary` rather than the first set repeated |
| O77 | ui | (v1.1) One list style per screen | Home, the workout screen, Add plan, the review sheet, Plans, Plan detail, History, Session detail and Settings all use the same grouped/inset list idiom and the same 20 pt horizontal margin |
| O78 | ui | (v1.1) The stepper buttons and set rows | Show a pressed state; done rows use the reserved green, not the accent blue |
| O79 | ui | (D28, v1.1) "Do later" in the workout menu | Present only when it would move something; the deferred exercise appears at the end of the Overview and comes round again later in the workout |
| O80 | ui | (D29, v1.1) Plan detail's edit affordances | Tapping an exercise opens the edit sheet; Edit reorders and deletes; the day header's menu renames and duplicates; a refused edit says why |
| O81 | ui | (D30, v1.1) The exercise chart and PR badges | The chart draws top weight over time with reps annotated when there are two or more weighted sessions; a PR badge shows on the Summary and in session detail, in the reserved green |
| O82 | ui | (D31, v1.1) Settings → Import backup | Names the backup's date and counts, says what Merge would add, and offers Merge / Replace all / Cancel; a file that isn't a backup says so and changes nothing |

`ITERATION_2_PLAN.md` §R2 proposed these as O48–O60. O48 and O49 were already taken by R1's
placeholder rows above, so the R2 block runs O50–O62 instead; the order is otherwise the plan's.
§R3 proposed O61–O70 and they follow at O63–O73 for the same reason. L38, M8 and N12 kept their
proposed ids; N12 is covered by O72 above, and M8 and L38 sit in their own sections.
