# Jimm's Bro+ — v1.3 plan (iteration 4)

One input drove this release: the owner's list after v1.2, with one instruction attached to
all of it — *"implement them seamlessly; the app should feel extremely intuitive and simple to
use."*

1. The Dynamic Island is too big; it should not be so wide.
2. A feature called **Progression**: based on the current plan, give the chatbot a JSON and
   have it calculate your progression over a period. When there is history, use it as context.
3. An importable CSV history file, and an importable history file in general — one you can
   add to another app.
4. Single-plan JSON edits, and specific JSON edits in general.
5. Changing an exercise mid-workout.

Milestones **X0–X6, in order**. Each ends with the full suite green
(`xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'`,
`swift test`, `python3 tools/check_core.py`) and one commit on `v1.3-refinement`. SPEC
amendments land **before** the code that depends on them, as in v1.1 and v1.2. Each feature is
one decision, D41–D45, and one Core type that a view only renders.

"Seamless" is read the way the v1.1 reviews read it: nothing new on Home unless it has
something to say, every new action in the menu of the thing it acts on, every paste going
through the one import pipeline, and every number the app offers still loadable (D35).

---

## X0 — This plan, the branch, and the decisions

- Branch `v1.3-refinement` off `v1.2-refinement` (v1.2 is not yet merged to main; merging is
  the owner's call).
- D41–D45 are written into SPEC §6 and `DECISIONS_LOG.md` by the milestone that lands
  them, as v1.2 did with D32–D40; §1's table stops at v1.1.
- No app code.

## X1 — A narrower Dynamic Island (owner note 1, D41)

The compact Island was wide for two reasons, neither of them content: `Text(timerInterval:)`
reserves the width of the widest string it might ever show, and a count-up whose range runs to
`.distantFuture` is allowed to grow to `h:mm:ss`.

- `WorkoutActivityState.timerRange(now:)` in Core: the closed date range the system timer
  draws, bounded so it never shows hours — a countdown clamps at `now + 1 s`, a count-up is
  cut at 59:59. Unit-tested, since it is the one rule the Island's width depends on.
- The widget's compact trailing view is the timer alone at a fixed width with monospaced
  digits; compact leading is one symbol; minimal is the timer at a smaller fixed width. The
  expanded view keeps the set line and the progress bar. The Lock Screen banner loses 4 pt of
  padding and one line of detail.
- Checklist row Q74 for the phone.

## X2 — Change exercise mid-workout (owner note 5, D42)

The machine is taken and **Do later** is not the answer because you want to do *something*
now. `Event.substituteExercise(exerciseIndex:name:weight:)`:

- Pending steps of the exercise become steps of the new exercise; logged and skipped ones stay
  what they were. If nothing has been logged, the exercise is renamed in place; if something
  has, a second `SessionExercise` is appended and the pending steps re-pointed to it, so
  history says "Bench Press 1 set, Dumbbell Press 2 sets". `blockIndex` and step order do not
  change, so the rest that is running keeps running.
- The new exercise keeps its own identity: prefill, "last time", the suggestion chip, advice
  and PRs all read *its* history (D8). `substitutedFor` records the original's name, so the
  Overview, Session detail and the Summary can say "Dumbbell Press · was Bench Press".
- An optional weight replaces every pending target's weight; empty keeps the plan's. A
  superset member is substituted alone.
- UI: "···" → **Change exercise** opens one sheet: a name field with recent exercises from
  history as suggestions, an optional weight, **Change**. Reachable in every state, like
  Skip and Do later.

## X3 — JSON edits, at every size (owner note 4, D43)

Plan editing (D29) is structured — a sheet per exercise. Sometimes the fastest edit is the
text: the chatbot wrote one day wrong, or truncated the week, or you want a second set to
differ from the first. Every JSON edit goes through the same pipeline a paste does, so the
app cannot end up holding a plan it would refuse to import.

- `PlanJSON.render(day:)` and `render(exercise:)` render a fragment; `PlanEdit.Operation`
  gains `replaceDayJSON`, `replaceExerciseJSON`, `insertDaysJSON` and `insertExercisesJSON`.
  A splice decodes the fragment leniently (a bare object, an array of them, or a whole plan
  whose days or exercises are taken), puts it into the plan's own JSON tree, and re-imports.
  Errors carry the full path (`days[1].exercises[2].sets[0].reps`), so the sentence the
  editor shows names the real place.
- The plan itself: Plan detail's **Replace** becomes **Edit JSON** — the same sheet, titled
  for what it does, with the text already open. Replace's semantics (keep the id, keep it
  active, remap the cycle position) are unchanged.
- The parts: the exercise sheet gains **Edit as JSON**; the day's menu gains **Edit day as
  JSON** and **Add exercise from JSON**; the plan menu gains **Add day from JSON**. Adding
  opens the editor with a template, so an exercise can be typed in from nothing. One
  `JSONFragmentSheet` does all of them: monospace text, Paste, the friendly error sentence
  with Details, Save.
- This closes two things SPEC §10 still listed as out: adding an exercise to a day, and
  editing an individual set independently of the others.

## X4 — History as a file other apps can read (owner note 3, D45)

- **Export history (CSV)**, from Settings → Data: one row per logged set, in the column
  order Strong writes and Hevy reads — `Date, Workout Name, Duration, Exercise Name, Set
  Order, Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE` — plus `Weight Unit`
  last, because this app never converts (D10). Drops are their own rows; skipped sets are
  not rows. `HistoryCSV.render`.
- **Import history (CSV)**, from the same section: the file is read and *described* before
  anything is written — "42 workouts from 12 Jan to 3 Sep · 5 already here · weights read as
  kg" — then **Import**. `HistoryCSV.parse` reads its own export, a Strong export and a Hevy
  export by header name, not by position; it takes the unit from a unit column, a `_kg` /
  `_lbs` header, or the setting, and says which. A workout already in History (same start,
  same name) is skipped, so importing the same file twice adds nothing.
- Imported sessions are ordinary sessions: `planId` nil, the workout name as the day name,
  steps logged with their timestamps, so prefill, PRs, the chart and Metrics read them as
  if they had been logged here.
- The JSON backup (D31) stays the app-to-app format; CSV is the app-to-*other*-app one.

## X5 — Progression (owner note 2, D44)

The app's premise is the chatbot round-trip, and until now it ran one way. **Progression**
runs it the other way: the app writes out what the plan is and what you have actually done,
the chatbot plans the next N weeks, and the plan carries the answer week by week.

- `Progression` on a `Plan`: a start date, a number of weeks, and per (day, exercise) the
  week-by-week targets — weight, reps, or seconds, or per-set overrides. Optional in
  `Persistence.swift`; a plan without one is exactly a v1.2 plan.
- **The prompt** (`Prompts.progression`, marker `JIMMSBRO-PROGRESSION-PROMPT-V1`): the plan
  as a compact listing (not its JSON — a week of exercises fits a chat paste), the period,
  and, when the owner keeps the toggle on and history exists, the last six sessions of every
  exercise in the plan with the advice they earned. Under the paste bound.
- **The reply** (`docs/PROGRESSION_FORMAT.md`): a small JSON — `weeks`, and one entry per
  exercise with an array of week objects. `ProgressionImport` parses it with the import
  pipeline's leniency (numbers as strings, the reps vocabulary of PLAN_FORMAT §3.2, unknown
  fields ignored), matches entries to the plan by day and exercise name (§6.9), snaps every
  weight to the loadable increment (D35), and reports what it dropped. Nothing in the plan's
  structure changes: a progression is attached to the plan you have.
- **The week** is calendar weeks from the start date. `Session.start` applies the current
  week's targets to the day's snapshot (D7 holds: the session records what it was asked to
  do), and `SessionExercise.progressionWeek` says which week it was. Prefill reads the week's
  weight before last time's (§6.5, rule 0), and the suggestion chip's reason reads "Week 3 of
  8 of your progression". After the last week, the plan's own targets and advice are back.
- **UI**: Plan detail gets a **Progression** row — "Plan your progression" or "Week 3 of 8 ·
  started 8 Sep". It opens one screen: the period (4 / 6 / 8 / 12 weeks), **Use my history**
  when there is any, the three steps Add plan already taught (Copy prompt, paste it into
  your chatbot, paste its reply), the review (each exercise's weeks in one row, warnings in
  yellow), and **Save progression**. With one saved, the same screen reads it back, with
  **Plan the next one** and **Remove**. Home's subtitle says "week 3 of 8"; when it has run
  out, one line says so with **Plan the next one**. Nothing else moves.
- Plan edits (D29, X3) carry the progression through; Edit JSON / Replace of the whole plan
  drops it, because that is a new plan.

## X6 — Docs, checklist, bundle

- SPEC §4, §6, §8 and §10 reconciled; `PLAN_FORMAT.md` §5 unchanged (the plan format itself
  did not grow); `PROGRESSION_FORMAT.md` new and bundled; `PROMPT.md` gains the progression
  prompt and its marker rule.
- `TEST_CASES.md` gains section **W** (v1.3), per milestone as they land.
- `DEVICE_CHECKLIST.md` gains v1.3 rows; `BUILD_STATUS.md`, `DECISIONS_LOG.md`, README and
  `HANDOFF_BUNDLE.md` regenerated; `tools/check_bundle.py` passes.
