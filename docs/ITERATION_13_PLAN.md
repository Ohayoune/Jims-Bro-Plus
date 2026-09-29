# Jimm's Bro+ — v1.12 plan (iteration 13): one of each

The owner's notes, on 2026-09-17 after v1.11, in their words: *"I want a lean and easily
understandable codebase"*, and after the review below, *"I want logic to be reused wherever
possible, I don't want logic duplicates anywhere."*

The review ran on `main` at `9a6e6b4`: three read-only reviewers (Core's session and Today files;
Core's import, plans, round trip, progression and history files; the views, Store and the
extension) and a scan for declarations nothing calls. Its verdict: not spaghetti — the engine, the
import pipeline, the diff and the history code are written once and read well — but twelve
releases have each added a layer and left the one before it alive, the v1.11 tracks were built in
parallel and merged with two to four copies of their shared parts, and small helpers (a day by
name, a weekday of a date, a number, a rest) have been rewritten wherever they were needed. Some of
the copies already disagree, and three of those disagreements are bugs.

The owner chose on 2026-09-17: **`tools/reference_import.py` stays** — it re-implements the import
pipeline on purpose, as the independent check on the fixtures, and is the one sanctioned copy; and
**this plan first, then L1**.

This plan is about duplicated logic only. Dead code, test-only code, misnamed files and long
functions the review also found are listed at the end, parked for the plan after this one.

## D96 — one owner for each piece of logic

- Every rule, parser, formatter, lookup and piece of text lives **once**. Core owns it unless it
  draws; a view owns only drawing. Every other place calls the owner.
- When two copies behave differently, **SPEC decides**. Where SPEC is silent, the stricter rule
  wins, and the choice is one line in `docs/DECISIONS_LOG.md`.
- What really differs by caller becomes a **named argument** of the one function, never a second
  function.
- **Sanctioned copies**, kept on purpose: `tools/reference_import.py` (the oracle, the owner's
  choice); the prompt text in `docs/PROMPT.md` and the formats in `docs/*_FORMAT.md` (the tests pin
  the Swift to them); `examples/` (fixtures, never regenerated to pass a test).
- **No change on disk.** `Core/Persistence.swift`'s decoder still reads every file
  `examples/store/v1/` freezes; `StoreMigrationTests` stays green untouched.
- **No change in behaviour** except where a milestone below names a disagreement and picks a side.

## How each milestone is built

On `v1.12-one-of-each`, off `main`. Each milestone ends with the three routes green —
`xcodebuild test`, `swift test`, `python3 tools/check_core.py` — plus a Release build and
`python3 tools/check_release.py`, and is one commit that says why. A file added or removed goes
through the project with `tools/add_sources.py` (or `tools/pbxproj_edit.py` until L7).

Tests: existing tests are **re-pointed** at the owner, not deleted. Where two copies disagreed, a
new test pins the side chosen. New tests take **TL** ids (TL1, TL2, …) in `docs/TEST_CASES.md`,
numbered as they land.

Line numbers below are as of `9a6e6b4`. The reviewers found them; each milestone re-finds them
before it edits, and a finding that turns out wrong is dropped with a line in the commit message.

---

## L0 — This plan, the branch, the bundle

This file on `v1.12-one-of-each`; the file added to `tools/build_bundle.py` and the bundle
regenerated in the same commit; the v1.12 paragraph in `CLAUDE.md` and `AGENTS.md` ending
*"L0 is written; nothing else is built"* until L8 rewrites it.

## L1 — One parser per value, one escaper, one formatter

- **Reps, weight, duration.** Owner: `PlanNormalizer.reps/duration/weight`
  (`Core/PlanImport.swift:150-191`), made callable without a normalizer instance.
  `ProgressionImport.weight/work` (`Core/Progression.swift:444-499`) and `PlanEdit.parseWork` /
  `parseRange` (`Core/PlanEdit.swift:517-561`) call it. The open-duration words
  (PlanImport:168, Progression:491) and the bodyweight words (PlanImport:175, Progression:456) are
  one list each.
  *Disagreements:* reps are 1…1000 in a plan (PlanImport:153) and 0…999 in an edit or a progression
  step (PlanEdit:537), so `"reps": 0` is refused in a plan and accepted in a step; `"8/12"` is a range
  in a plan and not in a step. **The importer's rule wins everywhere** (PLAN_FORMAT §2 is the only
  written rule).
- **A JSON string.** Owner: `PlanJSON.string` (`Core/PlanEdit.swift:129-144`).
  `JSONPoint.exampleDay` (`Core/JSONPoint.swift:127`) writes the day name in without escaping — a day
  named `Push "heavy"` pre-fills text that doesn't parse — and `ProgressionScreen.quoted`
  (`Core/ProgressionScreen.swift:190-192`) is a second, partial escaper. Both call the owner.
- **A number.** Owner: `TargetText.number` (`Core/Stats.swift:252-255`). `TrendMetrics.oneDecimal`
  (`Core/Metrics.swift:191-194`) is the same function; `PlanJSON.number`
  (`Core/PlanEdit.swift:122-126`) calls the owner unless JSON output needs a different form, in
  which case the difference is an argument.
- **A best set.** `ExerciseText.best` (`Core/HistoryGrouping.swift:42-50`) and
  `SessionMetrics.bestText` (`Core/Metrics.swift:90-95`) → one.
- **Issues.** Severity from the `E_` prefix (PlanImport:127, Progression:282-284); the stable sort
  by path (PlanImport:30, Progression:394-396); *"That edit doesn't apply"* built three times
  (PlanEdit:188, :299, and `invalid()` at :302); the sorted, pretty-printed `JSONEncoder`
  (PlanDraft:150-155, PlanEdit:385-388) — each once.
- **"Plan in words" by code, not by message.** `ImportTrip:52` and `IssueText:52` both test the
  message prefix *"No JSON found"*; both test the error code instead.
- **One default mode.** `ProgressionImport.run` and `Prompts.progression` default to `.calendar`
  (Progression:269, Prompts:229) while the app's default is `.performance` (ProgressionScreen:20,
  ProgressionModel:8, 17). The default lives once, on `Progression.Mode`.

## L2 — One JSON grammar

`StrictJSON` (`Core/RawJSON.swift:64-154`) and `LocatorParser` (`Core/JSONLocator.swift:123-259`,
*"StrictJSON's grammar, keeping offsets"*) are two hand-written parsers of the same grammar, and
`PlanImport.valueEnd` (`Core/PlanImport.swift:67-80`) is a third bracket scanner. One parser keeps
the offsets, and throws its errors with a position; the locator reads the offsets it kept.

The import pipeline is the riskiest code in the app, so this milestone changes no rule: the
manifest tests, `python3 tools/reference_import.py` and every `examples/invalid/` fixture's code and
path stay exactly as they are.

## L3 — Plans and the schedule

- **A plan's identity carried into its replacement.** Written three ways with three rules:
  `PlanLibrary.replace` (`Core/PlanLibrary.swift:43-54`: id, position by name, anchor);
  `PlanEdit.apply` (`Core/PlanEdit.swift:197-208`: id, importedAt, raw position, anchor,
  progression); `ChangeRequest.applied` (`Core/ChangeRequest.swift:152-168`: position where the day
  name matches, else by name). One function on `Plan`; what SPEC makes differ — whether the
  progression survives a re-import — is an argument. Position is always matched **by day name**
  (the owner's N6 reading).
- **A day by name.** `plan.days.firstIndex { normalized($0.name) == normalized(x) }` seven times:
  DaySwap:180, :318; WeekStrip:98; CalendarProjection:31, :202; PlanLibrary:268; ChangeDay:324-329
  (`PlanLibrary.borrowed`). One `Plan` method.
- **A date's weekday.** Four times: HomeCard:36, ChangeDay:226, DaySwap:451, WeekStrip:166. One.
- **A weekday's and a month's name.** `WeekdayText.full` is the owner. HomeCard:393 uses
  `calendar.weekdaySymbols` (the phone's language), which HomeCard:706-707's own comment calls
  unreliable; `SummaryText` uses a `DateFormatter` in the current locale; ChangeDay:112 hard-codes
  English months. *Disagreement:* on a phone set to German the card can say *"Montag"* beside
  *"Start Monday's Push"*. **English everywhere**, per ChangeDay's rule that the app speaks English
  whatever the phone's language — checked against SPEC before it lands.
- **"A workout of this day was done on that date."** DaySwap:324-330 and :427-431 are identical;
  HomeCard:607-609 and DaySwap:413-415 are variants. One.
- **The first date within the horizon.** `DaySwap.firstDay` (:189-201) and `firstDate` (:480-488)
  are one loop, but one runs `0...horizonDays` and the other `0..<horizonDays`. One function; the
  horizon as SPEC §6.44/§6.4x defines it.
- **A week.** `CalendarProjection.week(containing:)` (:216-233) is `next(days: 7, from: weekStart)`
  (:238-254), and builds the next month even when the week doesn't need it. One.
- **A cycle as squares, and as names.** Three projections, each with its own struct:
  `ImportTrip.squares` (`Core/ImportTrip.swift:245-274`), `RepeatBlock.squares`
  (`Core/PlanPage.swift:37-70`), `PlanPage.rows` (:92-112). The cycle-to-names list four more
  times: PlanJSON (PlanEdit:19-22), `RepeatBlock.chips`, Prompts:181 (which lower-cases the chips
  again), `PlanDiff.scheduleText` (:302-305). One projection and one list; `CycleStrip.hollow`
  (`DaySquare.swift:123-132`), which the strip never reads, goes with it.
- **The next entry in the pattern.** `PlanSchedule.nextInPattern(_:)` (PlanLibrary:215-219) is a
  second entry point that reads `Date()` itself; its callers pass the date to the one function.
- **An exercise search.** `ExerciseText.search` (`Core/HistoryGrouping.swift:81-93`: history only,
  normalized contains) serves History's Find an exercise and the Workout's Change exercise
  (`ChangeExerciseSheet.swift:26`); `ExerciseNames.known` (`Core/ExerciseNames.swift:22-38`: plans
  and history, case- and accent-blind) serves Add exercise. One search; where each screen draws its
  names from is an argument. *Disagreement:* the matching rule — **case- and accent-blind** wins.
  The stale comment at HistoryGrouping:79-80 (*"History's search box uses it"*, gone since D66) goes.

## L4 — The session and the Workout screen

- **The rest after a set.** `RestResolution` (`Core/Steps.swift:52`) uses `restSeconds` when the
  exercise has no group; the Workout screen's *"Rest 1:30 starts when you log"*
  (`Core/WorkoutScreen.swift:704-705`) uses `groupRestSeconds ?? restSeconds` either way. The line
  asks `RestResolution`, so it cannot promise a rest the engine won't start.
- **The next step, said.** `SessionEngine:146-152` and `WorkoutScreen:713-722` both build
  *"Next: name · set x of y · …"*, and SessionEngine:271 and WorkoutActivity:31-32 strip the
  *"Next: "* back off. One builder without the prefix; the prefix is added where it's shown.
- **The step that is on.** `ActiveSession.currentStep` (`Core/WorkoutBar.swift:30`) is the owner;
  WorkoutScreen:393-398 and WorkoutActivity:24-29 rewrite its switch (the latter with a redundant
  guard at :23).
- **Counts.** *Exercise n of m* (WorkoutScreen:61-62, InputRules:235-236); steps finished
  (WorkoutScreen:73, WorkoutActivity:30); `SessionEngine.loggedCount` and `elapsed(now:)`
  (:44, :76) repeat `SessionStats.loggedCount` and `duration` (Stats:48, :41). Each once.
- **Last time.** `Prefill.historicalResult` and `historicalWeight` (`Core/Prefill.swift:50-64`)
  are near-copies, and `values` scans history three times through `lastSteps` (:97). One lookup,
  one scan.
- **Limits.** `0...10000` for a weight three times (SessionEngine:155, :301, :366) beside
  `InputRules.maxWeight`; `String(name.trimmed.prefix(100))` twice (:298, :367). The constants
  once.
- **A step.** `Step` (`Core/Steps.swift:3-29`) repeats `SessionStep`'s six fields and is converted
  field by field (Steps:71, HistoryCSV:235-240). The flattener returns `SessionStep`.
  `target(at:)` (Steps:81) returns a four-field tuple retyped at Prefill:148 and WorkoutScreen:554,
  then rebuilt into a pretend `SetTarget(restSeconds: 0)` (InputRules:167, WorkoutScreen:718): a
  named type instead.
- **The walk, stored one way.** The rest between exercises is either
  `.resting(kind: .betweenExercises)` or `.working` with `blockDone` (a walk of 0, or
  `.skipExercise`, SessionEngine:210-214, which re-implements `advance`), and every reader handles
  both: WorkoutScreen:612-623, WorkoutActivity:38-52, `WorkoutStage` :45-54. One form. The active
  session is on disk, so the decoder still reads the other. *Disagreement:* whether skipping an
  exercise starts the walk — `advance`'s comment (:128-130) says it does, `.skipExercise` doesn't —
  **SPEC §6.55 decides**. The two comments false since D33 (WorkoutScreen:595-596, Models:231-233)
  are corrected.
- **Decoding.** `ActiveSession` and `RestState` put `init(from:)` in the type body, against
  Persistence.swift:18's rule, and so hand-write their memberwise inits and an `encode(to:)` that
  repeats the synthesized one; the legacy `.transition` decode is written twice (Models:376-379,
  :399-404). The rule followed; each once.
- **A day's blocks as names.** `StepCard.blockNamesRows` (InputRules) copies
  `SessionBlocks.namesRows` (`Core/HistoryGrouping.swift:160`); OverviewView:18-31 and
  SessionDetailView build the same list. One.

## L5 — The chatbot screens

- **One refusal.** `refusal` is four types — `ImportTrip.Refusal?` (ImportTrip:88), `[Issue]`
  (ChangeRequest:30), `String?` (ProgressionScreen:98), `ImportTrip.Refusal?` again (DraftTrip:15)
  — and *where the fix is* is worked out three ways (ImportTrip:38-47, ChangeRequest:18/:47-50,
  ProgressionScreen:72-74) as a bare `1` or `2`. One `TripRefusal` in `Core/Trip.swift`: the errors,
  a `fix` enum (`.chat`, `.paste`), what the button sends, whether day by day is offered, the
  sentence. *Disagreement:* an empty error list is fixed at Paste in ImportTrip (:40) and at Chat in
  the other two; SPEC §6.60–§6.68 decides.
- **One set of words and buttons.** *"Ask for the whole plan"* is written twice (ImportTrip:75,
  ChangeRequest:15); `ImportTrip.buttons` (`.refused`) and `sendButtons` both produce it;
  ChangePlanView:128-132 types *"Send the prompt again"* instead of `TripText.sendAgain`;
  `ImportTrip.fix()` (:155) only calls `sent()`; `DraftTrip.pastedOutline` and
  `pasted(index:read:)` both only call `take`. And the ··· menu is built three ways — Core's
  `trip.menu` (ImportView), conditions in ProgressionView:89-116, typed words in ChangePlanView —
  so every screen draws Core's.
- **Which prompt.** ImportView:208-216 chooses between `Prompts.render(errors:)` and
  `render(settings:)` itself; ChangeRequest makes the same choice in Core (:82-85). Core chooses
  for every screen. `ProgressionScreen.prompt` (:104-106) and `AppModel.progressionPrompt` are two
  routes to one prompt; one goes.
- **Every JSON sheet in `JSONPoint`.** Five kinds are built in `Core/JSONPoint.swift`; `.plan` and
  `.progression` are built in ImportTrip:229-232, DraftTrip:123-142 (the footer string again),
  ChangeRequest:177-184 and ProgressionScreen:170-176. All in `JSONPoint`.
- **A day tried before it is taken.** `DraftTrip.preview` (:95-108) repeats `PlanDrafting.day`'s
  trial import (`Core/PlanDraft.swift:62-67`), and runs from `ImportView.body` (:122) — every render
  re-reads the outline and re-imports each filled day. One function, run when the draft changes.
- **The views' shared parts,** into `Features/Shared`: the issue Details list
  (`"\(issue.code) · \(issue.message)"`, ImportView:180, ChangePlanView:242, ProgressionView:214,
  JSONFragmentSheet:90); *"Worth knowing"* (ImportView:367, ProgressionView:328, ChangePlanView:220);
  the cleanup `DisclosureGroup` (ImportView:391, ProgressionView:354); the styled `PasteButton`
  (ImportView:267, ProgressionView:231, ChangePlanView:101).
- **One JSON sheet for a whole plan.** With `replacingPlanId` set, ImportView is a second
  `JSONFragmentSheet` (ImportView:47-54, 609-620) with its own unit fix-up and `PlanJSON.render`;
  every other text edit in Plan detail goes through `.sheet(item: $fragment)` (PlanDetailView:85).
  A `.plan` fragment target instead.

## L6 — The other views

- **Text a view works out, moved to Core's text types.** SummaryView:96-140 (the headline, the
  record, the advice, the mean set time) → `SummaryText`; ExerciseHistoryView:92-97 writes
  `10@100` whatever the notation setting says, copying `InputRules.resultText(_:wording:)`
  (`Core/InputRules.swift:249`) — it calls it, so plain words say *"10 × 100 kg"*;
  ProgressionView:128-132, :139-141, :171 (*n of m exercises done*, entries to exercises,
  *"This step:"*/*"This week:"*); SettingsView:99-104, :266-282 (the restore sentences' plurals, a
  duration formatter).
- **One switch-workout alert.** HomeView:170-175, :262-267, :395-429 and PlanDetailView:110-115,
  :144-149, :293-310 each build the prompt from `SessionStats`, the same three-button alert and the
  same `catch LibraryError.sessionInProgress` (and PlanDetail:309 swallows the error with `try?`).
  One modifier; the prompt from Core.
- **Small SwiftUI repeats.** `Binding(get: { x != nil }, set: { if !$0 { x = nil } })` 24 times in 15
  files → one helper. The OK-only error alert five times (ImportView:95, PlanDetailView:104,
  BuiltInPlansView:28, SettingsView:258, HistoryImportFlow:43) → one modifier. Two share sheets —
  SettingsView's `ShareSheet` and PromptButtons' `SharePresenter` — → one.
- **Records worked out once per screen,** not once per row: SessionDetailView:18-20, :148 and
  SummaryView:15, :44.
- **One way to save an exercise.** ExerciseEditSheet's operation form starts one `Task { editPlan }`
  per changed field (PlanDetailView:77-79, :137-142) — N pipeline runs, N writes, and each error
  alert replaces the last — while DayEditorView saves once. One replace-exercise edit.

## L7 — Tools and the tests' support

- `tools/pbxproj_edit.py` and `tools/add_sources.py` both add files to the project; one script
  (`add_sources.py`, the one `check_release.py` names) does add, remove and remove-group.
  `add_activity_target.py` keeps its one-shot job but uses the same project-editing code.
- `JimmsBroTests/CoreTestSupport.swift`, `JimmsBroTests/FixtureLoader.swift` and
  `tools/CoreCheckSupport.swift`: any helper written twice becomes one. The tests weren't in the
  review; this milestone sweeps them for copied helpers the same way and merges what it finds.

## L8 — Docs, bundle, 1.12

- `DECISIONS_LOG.md`: D96, and one line per disagreement settled in L1–L6.
- `TEST_CASES.md`: the TL rows as they landed. `DEVICE_CHECKLIST.md`: a **v1.12 rows** section only
  for what a person can see change — the exercise history in plain words, Change exercise's
  search, a weekday name on a non-English phone.
- `BUILD_STATUS.md` for L0–L8; the v1.12 paragraph in `CLAUDE.md` and `AGENTS.md` rewritten for
  what shipped.
- Version **1.12** on every target and in `docs/APP_STORE.md`; the bundle regenerated; Release build
  and `check_release.py` green.

---

## Found by the review, not in this plan

Not duplication, so parked for the plan after this one, in this order:

1. **Two bugs worth fixing first.** `AppModel.importHistory` (`Store/HistoryTransfer.swift:43-49`)
   stops at the first failed write and the rest of the CSV's workouts never reach memory — its
   comment says the opposite. `AppModel.deleteAllData` (`Store/AppModel.swift:478`) ignores a failed
   delete with `try?`, so the screen shows nothing and the files come back at the next launch.
2. **Code nothing calls:** `InsetGroup` (`RootView.swift:250`), `StepCard.lastWeightLine`,
   `HistoryCSV.parse(calendar:)`, `HistoryImportFlow.importing`, `WorkoutActivityAttributes.dayName`,
   PlanDetailView's `showWorkout` binding.
3. **Code only the tests call:** `StepCard.setRows`/`SetRow`/`header`; StartCard's `title` and
   `buttonTitle`; `WorkoutScreenModel.zones`/`progress`/`progressLine`/`undoStep`;
   `StatusStrip.restKind`/`direction`; `SessionEngine.adviceForBlockJustFinished`;
   BuiltInPlans' `summary`/`estimatedMinutes`/`forWhom`/`daysPerWeek`/`equipment`;
   `PlanDraft.progress`; `Progression.apply(to:week:)`; `RepeatBlock.highlighted`;
   `Store.isDestructive`; `Store.complete(session:)`; `AppModel.importSamplePlan` with
   `SamplePlan.json`, which ships in the app for it.
4. **Files named for one thing that hold several:** `InputRules.swift` (mostly `StepCard`),
   `HomeCard.swift` (six types), `Stats.swift` (`TargetText`), `PlanLibrary.swift`
   (`PlanSchedule`), `Progression.swift` (`ProgressionImport`), `PlanEdit.swift` (`PlanJSON`),
   `RootView.swift` (eleven shared views).
5. **Long functions:** `HomeStart.current` (`Core/HomeCard.swift:362-560`), `ProgressionImport.run`,
   `PlanNormalizer.plan`.
6. **Work done more often than needed:** the Workout screen rebuilds its model every second and
   re-scans history; `BuiltInPlansView` runs the import pipeline on four bundled files on the main
   thread to draw squares; `HistoryCSV.parseDate` builds up to fifteen formatters a row.
7. **DEBUG screenshot hooks,** about 200 lines across ten files, which shape two production types.
