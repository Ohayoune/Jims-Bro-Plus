# Build status

Updated 2026-09-17. **v1.11 is built and green on branch `v1.11-round-trip` (off `v1.10-symbols`
at 33e7d50): N0–N6, with N7 — the documents, the checklist, the bundle and version 1.11 — still to
do.** v1.10 and everything before it are below, unchanged except where a later milestone corrected
them; the device checklist, the Developer Program, a release Xcode and the submission itself are
the owner's.

## v1.11 (N0–N6): built and green, N7 open

`docs/ITERATION_12_PLAN.md` is the v1.11 plan, written from the owner's note that the JSON screens
*"feel like an instruction manual"*. It is the first plan cut for a parallel build: **N0–N1 are the
trunk**, **N2–N5 four tracks** that share no file, each built in its own git worktree on its own
branch and its own simulator clone, and **N6 the merge**. Each milestone still ends with the whole
suite green on the three routes, a Release build and `tools/check_release.py`.

After N6:

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17 n2'` | **438 tests, 32 skipped, 0 failures** |
| `swift test` | **437 tests, 0 failures** |
| `python3 tools/check_core.py` | **437 test bodies, 8940 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **118/118 fixtures match** (unchanged: v1.11 touches no fixture and no pipeline rule but the change prompt's marker) |
| `xcodebuild build -scheme JimmsBro -configuration Release` | **BUILD SUCCEEDED** |
| `python3 tools/check_release.py` | **ready, as far as a script can tell** — version **1.10 (1)** until N7 bumps it |
| `python3 tools/check_bundle.py` | **stale until N7**, which regenerates the bundle with the v1.11 documents |

The simulator route hung twice before any test connected — *"The test runner hung before
establishing connection"*, as it did in P6 — and passed on a simulator erased and booted before
`xcodebuild`. That is how the merge runs were made: `xcrun simctl erase "iPhone 17 n2" && xcrun
simctl boot "iPhone 17 n2"` first, then the three routes.

After each merge, in order: **N2** the simulator 419 tests (27 skipped), `swift test` 418,
`check_core.py` 418; **N3** 425 (29 skipped), 424, 424; **N4** 432 (30 skipped), 431, 431; **N5**
437 (31 skipped), 436, 436 — with a Release build and `check_release.py` green after each. No
merge conflicted: the tracks' files were disjoint, N1 had registered every file in
`project.pbxproj` and `Package.swift`, and `TEST_CASES.md`'s neighbouring blocks merged untouched.

| Milestone | What it did | State |
|---|---|---|
| N0 | The plan, cut for a parallel build, and the branch. The requirements were settled first on the "The Round Trip" artifact, whose seven questions (J1–J7) the owner answered 2026-09-16 | Done |
| N1 | The trunk: SPEC §6.60–§6.68 and D87–D95, `Core/Trip.swift` (`TripStage`, `TripStrip`, `TripButtons`), `TripStripView` and `RefusedBand` in `DaySquare.swift`, `PromptButtons` in `Features/Shared`, `ExerciseEditSheet` extracted with Core's `PlanEdit.ExerciseFields` behind it, the change prompt (PROMPT.md §7, `Prompts.change`, `PlanImport.changePromptMarker`), the mechanism sentence on the introduction's first page, **every file the tracks fill registered while empty**, and TEST_CASES' TN section with a block per track (TN1–TN6) | Done |
| N2 | Add plan as one screen whose stage is Core's (`ImportTrip`): the strip large and centred, Send the prompt / Copy the prompt, the system's Paste alone, the plan as its page draws it with **Use *name***, a refusal's sentence in a red band (D88). The built-in plans are a row of four tiles drawn by their own cycles and the pushed picker is gone (D90); day by day is offered only on a reply cut short and runs on the review itself (`DraftTrip`, D91). D52's pipeline and `draft.json` untouched. TN7–TN14 | Done |
| N3 | Progression's planning screen as the trip (D92): the steps and the mode as two rows of pre-marked tiles, the strip small beneath, one control at a time, and a review that shows the result — grouped by day, each exercise a ladder of bars, step 1's numbers beside the name, one button, **Start step 1**. No history switch (J5). The stage, the tiles and the ladders are Core's (`ProgressionScreen`, `ProgressionLadder.of`). TN17–TN21 | Done |
| N4 | Today's exercises edited in place (D93): the Change *day* card opens the day's editor — rows to swap, drop, add and reorder — every change a `DayEdit` on a `Day` value the screen holds and never stores, **Use for *Wednesday*** reading it back through the same `ownDay` check the sheet's Save ran, and Add exercise searching the names the app already knows (`ExerciseNames`). The result is §6.58's `.own(day)` swap, the plan untouched. TN23–TN29 | Done |
| N5 | **Say what should change** (D94): Plan detail's ··· sends the plan's canonical JSON and one sentence, reads the reply through the ordinary pipeline, and shows the old name struck above the new, a removed exercise struck, an unchanged day as one grey line, under a button that names its effect. **Apply is an edit, not a Replace** — the plan keeps its id, its import date, its cycle place and anchor, and its progression. `PlanDiff`, `ChangeRequest`, `AppModel.applyChange`. TN32–TN36 | Done |
| N6 | The merge, and the lines the tracks left. The four branches merged in order with the suite and a Release build after each; the owner's two readings taken (days matched **by name only**, SPEC §6.67 amended; **Send the prompt again** returns every trip screen to Ask, so Progression's `changeSteps()` is `restart()` and §6.65's second item is not built); `JSONPoint` gained `.plan` and `.progression` in place of the tracks' stand-ins; `TripText` gave the four ···s and Plan detail's day row one word each (**Edit day as JSON** is **Edit the text**); the strip's done squares became `Color(.label)`, which does not go grey over `.bar` material; and the dead code went — `DraftPlanView.swift`, `PromptText.copyStep` and `.mechanism`, `BuiltInPlans.buildYourOwn`, `AddPlanRequest.builtIns`. TN38 pins all of it out of the sources | Done |
| N7 | Docs, checklist, bundle, 1.11 | **Open** |
| — | The v1.11 device rows (TN15, TN16, TN22, TN31, TN37 and VoiceOver on the strip) | **Written, not run** — need the phone |

### Not run in v1.11

- The device rows above, and every earlier release's; the phone is the owner's.
- `tools/check_bundle.py`, until N7 regenerates the bundle.

## v1.10 (P0–P7): built and green

`docs/ITERATION_11_PLAN.md` is the v1.10 plan, written from the owner's notes after living with
v1.9 — *"I want to make everything symbols, and the app colorful"*. Each milestone ends with the
whole suite green on all three routes, a Release build and `tools/check_release.py`, and one
commit on `v1.10-symbols`.

After P7:

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'` | **404 tests, 23 skipped, 0 failures** — the skips are the pins that read the source tree, which the simulator's sandbox cannot see; P7 adds none |
| `swift test` | **403 tests, 0 failures** |
| `python3 tools/check_core.py` | **403 bodies, 8,211 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **118/118 fixtures match** (unchanged; P7 touches no code but the version) |
| `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | **BUILD SUCCEEDED** |
| `python3 tools/check_release.py` | **ready, as far as a script can tell** — version 1.10 (1) |
| `python3 tools/check_bundle.py` | **current** (regenerated in P7) |

The simulator route and the Release build ran on the version bump, P7's last change to anything compiled; the host routes ran again after the last SPEC edit, since the doc pins read SPEC.

After P6: the simulator 404 tests (23 skipped), `swift test` 403, `check_core.py` 403 bodies and 8,211 assertions, 118/118 fixtures, Release and `check_release.py` green at version 1.9, the bundle current. The first two simulator runs never reached the tests — *"The test runner hung before establishing connection"*, then *"Simulator device failed to launch"* — and passed once the simulator was booted before `xcodebuild`.

After P5: the simulator 398 tests (22 skipped), `swift test` 397, `check_core.py` 397 bodies and 8,115 assertions, 118/118 fixtures, Release and `check_release.py` green, the bundle current.

After P4: the simulator 393 tests (22 skipped), `swift test` 392, `check_core.py` 392 bodies and 8,028 assertions, 118/118 fixtures, Release and `check_release.py` green, the bundle current.

After P3: the simulator 388 tests (21 skipped), `swift test` 387, `check_core.py` 387 bodies and 7,827 assertions, 118/118 fixtures, Release and `check_release.py` green, the bundle current.

After P2: the simulator 382 tests (21 skipped), `swift test` 381, `check_core.py` 381 bodies and 7,637 assertions, 115/115 fixtures, Release and `check_release.py` green, the bundle current.

| Milestone | What it did | State |
|---|---|---|
| P0 | The plan, the branch, the mocks (the "Workout in Symbols" and "Symbols, Round Two" artifacts, not committed) | Done |
| P1 | Three states, three colours (D79) and the header is the bar (D80). `MarkState` — done, now, todo — in `Core/WorkoutMarks.swift`, Foundation only and compiled into the widget extension, since `DaySquare.swift` maps a state to its colour there (done the day's colour or the no-colour grey, now the accent, todo `secondarySystemFill`); the rule, `MarkState.of(step:session:)`, in `Core/WorkoutBar.swift` beside `WorkoutBar`, because it reads an `ActiveSession` the extension does not build. `ActiveSession.currentStep` became the one "step the workout is on", read by the engine and `AppModel`. `WorkoutBar.of(session:showing:)`: a segment per block in `SessionBlocks` order, weighted by its set count, a state per step, the caret under the current step's block. `WorkoutScreenModel` gained `bar` and `spokenHeader` (the stage, exactly) and `SetRow` its `mark`; nothing left the model. Zone 1 is the day's square, `BarView` — one `Canvas`: rounded segments 3 pt apart, each set filled in its state's colour and cut by a 1 pt tick, an ink caret — and the elapsed time under the bar's right end, one 44 pt button that opens the Overview and speaks the stage, then ⌄ and ··· in the secondary colour, centred on the bar's track. The screen is tinted `.primary`, so the capsules, Done, Undo and the chip are ink; **Log set** is ink (`PrimaryButton(ink:)`); the set rows' ticks take the day's colour. The Lock Screen's bar fills in the day's colour. SPEC §4.0, §4.5, §4.8, §6.15, §6.17, §6.40 (the bar's tap, ungated), §6.41 (the fifth place) and the new §6.52 and §6.53; TP1–TP7, T21 and T23 amended; the log | Done |
| P2 | The exercise in symbols (D81). `Core/RepCells.swift`: `RepCells.target`, `.logged` and `.timed` from `RepCells.Bounds.of(_:range:)` — a cell per rep or per five seconds rounded up, solid to the minimum (or to what was done), faint to the top, yellow past it, a caret for the field's number, a line for last time's, a group per five, sixty at most. `Core/WorkoutScreen.swift`: `SetDot` (a step of the block, its D79 state, skipped, what VoiceOver hears), `SetCard` (range — *8–10*, *8*, *8+*, *max* — unit, the set's weight, cells, colour, and the bounds and last time so `showing(field:)` redraws the cells for the number in the field), `WorkoutScreen.notes` (*was …* first), `InputDefaults.seconds`, `PrimaryAction.Kind.save`; the model lost `targetLine` and `rows` and gained `exerciseMark` (`MarkState.of(exercise:session:)`), `notes`, `dots`, `card` and `editing`, which `WorkoutScreen.model(…, editing:)` takes from the view and ignores unless it is a logged step of the block — the inputs then take the logged result and the primary is **Save**. The strip's Undo is set during a rest or the moment a block ends, not after. Zone 2 is the name with its dot and the ? popover, the dots (`ViewThatFits` a row or `WrapLayout`), and `SetCardView` — `WrapLayout` of 8 × 22 pt cells with the caret and line above and below each; a filled dot sets `editing`, a grey one `jumpTo`s, the blue one ends a change; Save applies `.editSet`; the edit sheet left the screen; Undo shows in the strip at every size. `StepCard.setRows` and `SetRow` stay in Core for I41, I42, O57 and U34–U35 — `SetRow.mark` went. SPEC §4.5 (zones 2, 4, 5), §4.6, §6.34, §6.36, §6.52 and the new §6.54; TP8–TP16; O57, U34, U35, W7 and TP1 re-pointed with their assertions kept, U28 annotated; the log | Done |
| P3 | The walk: a count-up and a ring (D82). `Plan.restBetweenExercises: Int?` — decoded with `container.optional` in `Core/Persistence.swift`, read by `PlanImport` as a rest (0–3600, digits accepted, `E_REST_INVALID` at `restBetweenExercises`), written by `PlanJSON.render` when set, and read the same way by `tools/reference_import.py`; three fixtures and a `restBetweenExercises` manifest check. `RestResolution.walk(plan:settings:)` — the plan's, then `Settings.transitionRestSeconds` — and `RestResolution.after(…, restBetweenExercises:)`; the engine's `restBetweenExercises` and `walk`, set from the session's plan by `PlanLibrary.refreshWalk()` at a start, before every event and at restore (`AppModel.load`); the engine refuses `adjustRest` and `skipRest` on the walk, and `startTimer` clears `blockDone`. `StatusStrip.direction`, `.ring` (`WalkRing { fraction, minimum, fromPlan, full, explanation, colour }`) and `.spoken`; `RestText.ringExplanation`; one `walkStrip` for the walk's rest and the block's line after it, with the count-up as the figure, the next exercise's name and no controls. `WorkoutScreen.model(…, walk:)` from `model.engine?.walk`. The Lock Screen counts the walk up (no `endsAt`) before the ring fills and after. The view: `WalkRingView` (58 pt, the arc in Core's colour, a green disc and a check when full), the figure 36 pt or 28 pt secondary when full, a walking figure, a blue dot and the next name, the ring's sentence in a popover. The plan and outline prompts ask for the field; the day prompt drops it; `BuiltInPlans.estimatedMinutes` walks the plan's minimum. PLAN_FORMAT §1, §2, §3.6, §4; PROMPT §1, §4, §5 and the rendered length; `schema/plan.schema.json`; SPEC §4.6, §4.7, §6.3, §6.4, §6.6, §7 and the new §6.55; TP17–TP23; Q25, Q27 and O61 re-pointed; the log | Done |
| P4 | Pages (D83). `PagePlace` (current, behind, ahead — by what is left in the block, not its place on the bar) and `ExercisePage { blockIndex, place, exerciseIndex, exerciseName, exerciseMark, notes, checked, dots, card, live, cardOpacity, firstPending, spoken }` with `card(field:)`, built by `WorkoutScreen.page`; `WorkoutScreen.model(…, showing:)` gives the model every page (`pages`), the one on screen (`page`), `currentBlock`, `showing`, `showsInputs`, `currentName` and `page(_:)`, and the bar's caret under the page — the fill unchanged; `exerciseName`, `exerciseMark`, `notes`, `dots`, `card` and `spoken` became the page on screen's. `PrimaryAction.Kind.back` (*Back to …*) and `.doNow` (*Do this now*, `step` the block's first pending), `WorkoutText.back(to:)` and `.doNow`; `editing` is honoured in the shown block only. The view: zone 2 a `ScrollView(.horizontal)` of pages with `containerRelativeFrame`, `scrollPosition(id:)` kept level with `@State showing`, a 20 pt margin and 8 pt gap, `OnePagePerSwipe`, pages off screen hidden from VoiceOver and a three-finger swipe to turn; a check in the day's colour where the ? was, the card at `cardOpacity`; zone 3 empty off the page; ↩ and ▶ on the primary; Do this now and a grey dot `jumpTo` and then follow the page; Change exercise names the exercise that is on; a debug-only `-uiShowPage`. `SessionEngine` unchanged. SPEC §4.5 (zones 2 and 5), §6.53, §6.54 and the new §6.56; TP24–TP29; TP6 and TP15 re-pointed; the log | Done |
| P5 | A bar that learns your pace (D84). `Core/Pace.swift`: `Pace.weights(day:history:)` — one weight per block in the bar's order: the median of the block's past times from the third, a past time running from its first start to the next start or log outside it at or after its last log (so the walk after it is counted in, and a skip never ends one), from finished sessions that started before this one, the block known by its exercises' names as they now are (a substitute by its own); before that the paced blocks' time per set × its sets; with no paced block, by set count; held between ½× and 2× the median stretch. `Pace.weights(sets:medians:)` is the rule apart from the clock, with `time(of:in:)`, `names(of:in:)` and `median`. `WorkoutBar.of(session:showing:weights:)` takes the weights (nil or a wrong count is by set count) and `WorkoutScreen.model` passes them from the history it already reads. Nothing stored, nothing in the view or the Lock Screen changed. SPEC §4.5 (zone 1), §6.53 and the new §6.57; TP30–TP35; TP3's message; the log | Done |
| P6 | Change *day* in squares, with a button (D85), and squares that join (D86). `Core/ChangeDay.swift`: `DayChoices` has `day` (a `Face` — name, colour, outlined — for the day the date is now, *Rest* on a rest date), `title` from `DayChoices.title(dayName:)` (*Change Push*), `when`, `strips` of `Tile`s (`face`, `slot`, `isChosen`) in place of sections and rows — this plan's filled, each other plan's outlined, titled by the plan's name — `own`, Custom's `point`, and `exercises` (`face`, `rows`, and a `point` pre-filled with `PlanJSON.render(day:)` of the day as it stands; nil on a rest date); `ownTitle` went. `ChangeDayText.confirm(_:marked:)` → `Confirm { title, from, to, isEnabled, slot, opensSheet }` for `DayChoices.Mark` (`.day(slot)`, `.custom`): disabled *Change Push* with nothing marked, the date's own tile or a vanished one; *Push → Pull* with both faces and the slot; *Write a day for Wednesday*, opening the sheet. `HomeStart.Alternative.changeExercises(dayName:colour:outlined:)` named after the shown square's day. `Core/DayColour.swift`: `CycleGlyph.width` (7), `rows(_:of:)`, `rows`, `ends(_:count:of:)`; `Core/PlanPage.swift`: `RepeatBlock.Square.isToday`. `DaySquare.swift`: `CycleStrip` — the `SquareRows` layout (seven to a row, one side for every place, `side` at most) and `StripSquare` (rounded at a row's ends, filled, outlined, dashed or ringed) — which `CycleSymbol`, the plan page's repeat block (40 pt, names beneath, today ringed, no `WrapLayout`) and `ChangeDayView` share. `ChangeDayView` redrawn: a `ScrollView` of the line, the strips at 58 pt with names beneath and *when* under the chosen tile, the dashed Custom, the exercises card (Today's `SetBlocks`, now internal) and the confirm button in the bottom slot, the title with the day's square; the ··· item's square outlined for a borrowed or own day. SPEC §4.1, §4.2, §4.3, §6.40, §6.49, §6.50, §6.51 and the new §6.58 and §6.59; TP36–TP42; TQ21, TQ22 and TQ25 amended; the log | Done |
| P7 | Docs, checklist, bundle, 1.10. SPEC §4.5's five zones rewritten once, top to bottom, as the page now is — the colour rule and the words left said once above them, the zone 2 pager and its pages as a list, zone 3 empty off the current page and the hold's seconds field, zone 4's three strips, zone 5 in ink — with the text each replaced in italics beneath; and the rest of SPEC checked against v1.9 for words that still read as current: thirty-four places caught up, each with a v1.10 note beside the text it corrects — §1's D14, D22 and D23, §3's block, §4.0's and §6.41's picker rows and workout header, §4.3's weekday squares, §4.7's first paragraph, §4.8, §4.11's walk, §5.3–§5.4, §6.3–§6.5's strip, overrun and last-time lines, §6.7, §6.18, §6.27's effort target, §6.32, §6.37, §6.43–§6.45, §6.50, §6.52's one disabled control and §9's VoiceOver — a few of them (the done screen's) stale since v1.1. `docs/DEVICE_CHECKLIST.md`'s **v1.10 rows** (TP7, TP16, TP23, TP29, TP35, TP42), with how to reach the walk and a ten-day cycle on the phone; `DECISIONS_LOG.md` gains D80's, D85's and D86's headlines and names D48's reversal on the picker, D59's Undo moved back to the strip and §4.0's one exception; `TEST_CASES.md` says where the device cases went; the README's `workout.png` retaken; version **1.10** in all six `MARKETING_VERSION` settings and in `docs/APP_STORE.md`; the handoff paragraph in `CLAUDE.md` and `AGENTS.md`; the bundle regenerated | Done |
| — | The v1.10 device rows (TP7, TP16, TP23, TP29, TP35, TP42) | **Written, not run** — need the phone |

### Checked on the simulator (v1.10)

- P7, `docs/screenshots/workout.png` for the README, on the iPhone 17 simulator with `SEED=1 SETTLE=8
  DEVICE="iPhone 17" tools/shot.sh build/p7-workout.png -uiScreen workout -uiNoAsk -uiNoAlerts
  -uiAdvance 2 -uiSkipDone`, downscaled to 720 px high with `sips -Z 720` like the other four — the
  rest after Barbell Bench Press's first set: the bar with its green square, a green mark, a blue mark
  and the grey track, the caret under the first segment and **0:05**; a blue dot before the name, the
  ? at the right and the next page's edge; the dots green, blue, grey, grey; the card **6–8** over
  *80 kg* with six blue cells, two faint, two faint yellow and the caret under the tenth for the 10 in
  the field; REPS 10 and KG 80; the strip's **2:25** *Rest* with −30 · +30 · Skip, the next-set line,
  *set 0:00* and **↶ Undo**; **Log set** in ink. It replaces the one taken on 2026-09-08, which showed the stage title,
  the Exercises button and the set rows.

- P1, on the iPhone 17 simulator with `SEED=1 DEVICE="iPhone 17" tools/shot.sh <png> -uiScreen
  workout -uiNoAsk -uiNoAlerts -uiAdvance 5 -uiSkipWaits -uiSkipDone` — the sample plan's first
  block logged and the walk to the second running: the header has no words but **0:03**; the green
  square, then four green marks, a segment of one blue mark and two grey, a long grey segment of
  twelve marks and one of three, each cut by its ticks and set apart by rounded ends and the gap;
  the ink caret under the second segment; ⌄ and ··· grey and level with the bar. **Log set** black
  with white words, the −30 · +30 · Skip capsules grey with ink words, the current row's dotted
  mark blue. In dark (`xcrun simctl ui "iPhone 17" appearance dark`): the track dark grey, the
  ticks still cut, the caret white, **Log set** white with black words.

- P2, on the iPhone 17 Pro simulator with `SEED=1 DEVICE="iPhone 17 Pro" tools/shot.sh <png> -uiScreen
  workout -uiNoAsk -uiNoAlerts -uiAdvance 2 -uiSkipWaits -uiSkipDone` — Barbell Bench Press with
  two sets logged: a blue dot before the name and the ? at the right; two green dots, the blue ring
  with its centre, a grey ring; the card **6–8** over *80 kg*, six blue cells, a gap after the fifth,
  two faint, two faint yellow past the top, the caret under the tenth for the 10 in the field and
  last time's line over it; Log set ink, the idle strip unchanged. Without `-uiSkipWaits` and with
  the new debug-only `-uiEditSet` (the last logged set changed in place, as a tapped dot does): the
  first dot green with an ink ring, the card's eight cells green with the ninth and tenth faint
  yellow for last time, 8 × 80 in the fields, **Save**, and the rest's strip with **↶ Undo** beside
  *set 0:00*. In dark: the card dark grey, the cells blue and dim, the yellow olive, caret and line
  white, the grey ring still visible.

- P3, on the iPhone 17 Pro simulator with `SEED=1 SETTLE=12 DEVICE="iPhone 17 Pro" tools/shot.sh <png>
  -uiScreen workout -uiNoAsk -uiNoAlerts -uiAdvance 5 -uiSkipWaits` — the sample plan's first
  exercise logged and the walk to **Incline Dumbbell Press** running, with the seeded setting's 2:00 as the minimum (the sample plan declares
  none). At **0:08** the ring's grey track with a short red arc from twelve o'clock, **0:08** large
  beside it, the walking figure, a blue dot and *Incline Dumbbell Press* under it, **↶ Undo** at the
  right, no −30 · +30 · Skip, Log set ink. At **1:09** the arc past half and amber. At **2:19** a
  green disc with a white check and **2:19** smaller and grey, still counting. In dark at 2:23: the
  same green disc and check, the figure grey, Log set white.

- P4, on the iPhone 17 Pro simulator with `SEED=1 SETTLE=10 DEVICE="iPhone 17 Pro" tools/shot.sh <png>
  -uiScreen workout -uiNoAsk -uiNoAlerts -uiAdvance 6 -uiSkipWaits -uiSkipDone`, and the new
  debug-only `-uiShowPage <block>` (the page a swipe would show) — the sample plan's first exercise
  logged and the walk to **Incline Dumbbell Press** running. The page that is on: the caret under the
  second segment, a sliver of the previous page's dot and card at the left edge and of the next
  page's at the right. `-uiShowPage 0`: the caret under the first segment and the fill unchanged,
  **Barbell Bench Press** with a green dot and a green check where the ? was, four green dots, the
  card faded with its green cells and faint yellow past the top, no inputs, the walk's ring still
  counting, and **↩ Back to Incline Dumbbell Press**. `-uiShowPage 2`: the caret under the long third
  segment, **Lateral Raise** with a grey dot and grey dots, a grey card of *12–15* over *10 kg* with
  last time's line and no caret, no inputs, and **▶ Do this now**. In dark, the page behind: the card
  dim with green and olive cells, the check green, Back white with black words.

- P6, on the iPhone 17 simulator with `SEED=1 SEED_PLANS=1 DEVICE="iPhone 17" tools/shot.sh <png>
  -uiScreen changeDay [-uiMark Pull]` — the new debug-only `-uiScreen changeDay` pushes the picker
  for today and `-uiMark` marks a tile by name. The seeded Wednesday is a rest: **▪ Change Rest**
  with a grey square in the title, the date line, *Push Pull Legs* over three filled tiles touching
  2 pt apart with the strip's two ends rounded, *Upper Lower* and *Full Body* over outlined tiles,
  a dashed **Custom**, and a disabled **Change Rest** in the bottom slot. `-uiMark Pull`: Pull's tile
  ringed in ink with a check, the button blue, **▪ Rest → ▪ Pull**. The first look ran *Full Body A*
  and *Full Body B* together under their touching tiles and drew the rest's grey as dark blue on the
  button, so names under tiles now take two centred lines and the button's squares sit on a chip of
  the background. With a scratch plan seeded through `build/seed/seed` (a three-day rotation, every
  day a workout): **▪ Change Push**, *Today* under Push's tile; in dark with `-uiMark Custom`, the
  dashed tile ringed white with a check and **Write a day for Today**. A ten-day cycle
  (*Push Pull Legs Rest Push Pull Legs Rest Rest Push*): on the Plans list its symbol is 7 over 3
  and Full Body's fourteen 7 over 7, each row joined; on its page (`-uiScreen plans -uiPlanDetail`)
  40 pt squares 7 over 3 with names beneath, today's rest outlined in ink and **Push** named in ink
  as Next up.

### Not run in v1.10

- **P6's taps and the exercises card.** The simulator tool refused the swipe that would have
  scrolled to the card (*"stopped retrying after repeated crashes"*), so the date's exercises card
  was not seen, nor a tap marking a tile, the button's press writing the swap and popping to Today,
  or the sheet opening pre-filled; `-uiMark` sets the same `marked` a tap does, and TP37–TP39 cover
  the button, the write and the pre-fill. The ··· item's *Change Push* in the menu was not opened.
  **TP42**, a long cycle on the phone and the picker's tap and button, joins the checklist in P7.

- **P5's widths were not looked at on the simulator.** `tools/seed` writes every past step 110 seconds
  after the one before, so each block's time is its sets × 110 and the paced bar is exactly P1's by
  set count; a screenshot would have shown nothing P5 did. TP31 checks the screen's bar carries the
  pace; seeing it is **TP35**, on the phone after three workouts of a day, with the Lock Screen
  unchanged.

- **P4's swipe** was not made on the simulator: the simulator tool refused the gesture ("stopped
  retrying after repeated crashes"), as it refused taps in P1–P3. The pages were reached through
  `-uiShowPage`, which sets the same `showing` a swipe does; that the pager lands one block per
  swipe, that Back and Do this now scroll it, and VoiceOver's three-finger swipe are **TP29**'s, on
  the phone, with the Lock Screen unchanged while a page is looked at.

- **P3's tap on the ring** and its popover were not tried, the simulator tool having refused taps
  in P1 and P2; TP22 pins the sentence and the view's popover shows `ring.explanation`. Nor was
  **the Lock Screen's count-up** seen (no Live Activity from `shot.sh`), nor VoiceOver's reading of
  the strip or the *Ready* announcement. **TP23**, the ring's hues on Push and Pull days in light and
  dark, joins the checklist in P7. A plan that declares `restBetweenExercises` was not imported on
  the simulator; TP17 and TP20 run one through `PlanLibrary`.

- **P2's taps.** The simulator tool refused taps again, so a dot's tap, Save's result, a grey dot's
  jump, the ?'s popover and the cells following − and + were not seen; TP13 and TP15 cover the
  model and the source. To look: the command above, then tap a green dot, change the reps, Save.
- **TP16**, zone 2 at accessibility text sizes on the phone, joins the checklist in P7.

- **The bar's tap.** The simulator tool refused taps again ("stopped retrying after repeated
  crashes"), so the Overview opening from the bar was not seen, nor VoiceOver's reading of it; TP6
  pins the tap's action and the spoken label in the source. To look: the command above, then tap
  the bar. `-uiOverview` opens the sheet directly but does not test the tap.
- **The Lock Screen's bar** in the day's colour was not looked at: the simulator runs no Live
  Activity from `shot.sh`. TP2 pins its tint.
- **TP7**, the bar at sixteen sets on a 6.1-inch phone at arm's length, is the phone's; it joins
  the checklist in P7.
- Noticed, not changed: after the walk is skipped, `blockDone` stays until the next log (D14), so
  a timed set started straight out of it still reads **Between exercises** as its stage — which
  since P1 only VoiceOver and the Lock Screen say. TP5 records the timed set's caret rather than
  its words.

## v1.9 (Q0–Q7): built and green

`docs/ITERATION_10_PLAN.md` is the v1.9 plan, written from the owner's notes after living with
v1.8's strip — *"shift today's colour to the colour of the other day (without changing the plan
itself)"*. Each milestone ends with the whole suite green on all three routes, a Release build and
`tools/check_release.py`, and one commit on `v1.9-swaps`.

After Q7:

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'` | **368 tests, 18 skipped, 0 failures** — the skips are the pins that read the source tree, which the simulator's sandbox cannot see; Q7 adds none |
| `swift test` | **367 tests, 0 failures** |
| `python3 tools/check_core.py` | **367 bodies, 7,345 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **115/115 fixtures match** (unchanged; Q7 touches no code but the version) |
| `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'` | **BUILD SUCCEEDED** |
| `python3 tools/check_release.py` | **ready, as far as a script can tell** — version 1.9 (1) |
| `python3 tools/check_bundle.py` | **current** (regenerated in Q7) |

| Milestone | What it did | State |
|---|---|---|
| Q0 | The plan, the branch, the mock (the "Swapping Days" artifact, not committed) | Done |
| Q1 | A day swapped, not a plan changed (D72) and Slide (D73), in Core: `Core/DaySwap.swift` — `DaySwap` with its five-kind `Slot`, `swaps.json` beside `plans.json` (a missing file is no swaps; an unreadable one is set aside), `PlanLibrary.swaps`, `settle` (the three completion cases: the expected day re-anchors at the projected entry and keeps the grid; what the date said writes nothing; anything else writes today's record and a question on the day whose workout was taken, with today's day as the default), `answer` (Rest, today's day, Keep, and Slide on rotations, which re-anchors as D37 did and remembers what it replaced), `question` (the options in order, the default, what was chosen); `PlanSchedule.base`/`slot` — one slot per date, swaps read — under `CalendarProjection`'s three functions (`swaps:` with no default), `WeekStrip.days` (the dot, the outline, the ring, the question on the shown square's card), `PlanSchedule.next(_:today:swaps:)` for Today's card on both schedules and the Summary's next line, and `PlanSchedule.missed`, which never misses a swapped-to-rest day and names the swapped day for Do it now; `DayEntry.own` drawn in ink on the grid; the backup's optional `swaps`; `examples/store/v1/` gains `swaps.json`, `backup-1.9.json` and `backup-1.7.json`. Nothing in the pipeline, the format, the prompts, the Workout screen, the rest or the Live Activity changed, and nothing is drawn yet: Q2 draws the marks. TQ1–TQ13 in `SwapTests`; L7 and one `LibraryCalendarPromptTests` assertion rewritten for D72. SPEC §6.8, §6.12, §6.41, §7, §8.1, §8.5 and the new §6.46 and §6.47 | Done |
| Q2 | Today shows the swap (D74): under a square whose day is not the pattern's, a dot in the pattern's colour (grey for rest); a yellow ring on a date carrying a question, breathing while it asks (still under Reduce Motion) and faint once answered; a long press that reopens a ringed square's question or shows a "was Push" callout on a dotted one (`WeekStrip.Square.was` and `.hold`); and the question's block where the rows would be — `SwapQuestionView`: the heading, the options as large squares with their word beneath and a check on the chosen one, and on a rotation the Slide row previewing three days — with the button following the choice through the projection (`SwapQuestion.heading` and `.slide`, each option's `colour` and `isChosen`; `HomeStart.showsQuestion` and `current(…reopened:)`). A date whose workout is done asks nothing; the block is never on an open session's card; a question reopened after a slide offers what it first offered (a Q1 gap, fixed here). The seeder's `--swap` (`SEED_SWAP=1` in `tools/shot.sh`). TQ14–TQ17 in `SwapTests`; T21 counts two ungated rows. SPEC §4.1, §6.40, §6.44 and the new §6.48 | Done |
| Q3 | The ··· speaks in squares (D75): **Change plan** beside the active plan's cycle drawn as one symbol (`CycleSymbol` in `DaySquare.swift`, its colours from `DayColour.cycle(of:)`, its fourteen-and-a-mark cut from `CycleGlyph`) and **Change *day*'s exercises**, named by the strip's own when, beside the shown day's square — both handed to the SwiftUI `Menu` as pictures in their own colours (`ImageRenderer`, `.alwaysOriginal`), and `HomeStart.Alternative` carrying what each symbol draws. On any day's card with no session open, but not today's once its workout is done; Change plan alone on Nothing scheduled; Change plan and Discard workout while a session is open. Until Q4 the second item opens the active plan in Plan detail. Progression left Today's menu — Plan a progression, the step line, `HomeStart.offersProgression`, `stepLine` and `previewPlanId`, `Gates.planProgression` and `PromptText.planProgression` are gone, and History's Progression row is the way — and the rows are the preview and nothing more. TQ21–TQ23 in `TodayTests` and `DayColourTests`; T2, T3, T21 (four gates), TS2, W39, Z1, Z3, Z22 and Z25 rewritten; T19, TS4 and Z2 removed. SPEC §4.1, §6.26, §6.37, §6.40, §6.42–§6.45 and the new §6.49 | Done |
| Q4 | Change *day*'s exercises (D76): the ···'s second item pushes a picker for the shown date (`ChangeDayView`; `DayChoices` from `PlanLibrary.dayChoices(for:now:)` in the new `Core/ChangeDay.swift`) — this plan's days, every other plan's, and **Write a day just for Wednesday** — and a tap writes a swap for that date alone (`choose(_:for:now:)`: answered and asked by nobody; the pattern's own day removes it; a date carrying a question is answered instead). A borrowed day projects as its own plan's day (`CalendarProjection` and `WeekStrip.days` take `plans:`), is drawn **outlined in that plan's colour**, starts as that plan's day, and its finished session moves neither plan (`isBorrowed`). A day just for the date goes through `JSONFragmentSheet` (Save **Use for Wednesday**, `saveTitle`) and the importer (`ownDay(_:named:units:settings:now:)`), is held by the swap, is drawn **outlined in ink**, and starts as the active plan's session under its own name (`startOwnDay`). `StartCard.own`, `HomeStart.ownDay` and `.isOutlined`, `MissedWorkout.planId` and `.own` (Do it now starts either), `WeekStrip.Square.planId` and `.own`, `DaySquare(outlined:)`. TQ25–TQ28 in `SwapTests`; no earlier case changed. SPEC §4.1, §6.41, §6.44, §6.46, §6.49 and the new §6.50 | Done |
| Q5 | The JSON sheet, redone (D77), at its five points — an exercise, a day, exercises to add, a day to add, and Q4's day just for a date — by a `JSONPoint` (`Core/JSONPoint.swift`) that `FragmentTarget` maps to and `DayChoices.point` hands over (in place of Q4's `ownFooter` and `saveTitle`): **named** — One exercise, One day, Exercises to add, A day to add, A day just for Wednesday, with the place beneath ("Bench Press, exercise 3 of 5 in Push", "Added at the end of Push", "For Wednesday 16 September. Not saved to Push Pull Legs."); **pre-filled** — an edit on the part's own text, an addition on a Push-up that saves as it stands (a free weekday on a weekday plan); **the error at the line** — `Core/JSONLocator.swift` walks the text as strict JSON to the path's line, through the origins `PlanEdit.located` keeps (`fragment(_:as:)` is it without them), or answers nothing, and the box, now a TextKit 1 `UITextView`, tints the line with a bar at its edge and puts the sentence in a gap beneath it, while an edit unmarks until the next Save; and **a Save that says its effect** — Replace Bench Press, Replace Push, Add to Push, Add to Push Pull Legs, Use for Wednesday. Smart quotes are off in the box. TQ30–TQ32 in `JSONEditTests`; TQ25 reads Save from the point; W17's message changed. SPEC §4.3, §6.19 and §6.50 | Done |
| Q6 | Plans speak in squares (D78). **The list**: a row is the accent chevron at its left, the plan's `CycleSymbol`, its name with **how often** beneath (`PlanText.howOften` — 6 days a week, 3 days every 10, Every day — counted from the symbol's own squares) and a circle at its right; the filled circle is the mark, the active plan's until another is tapped, and a marked plan that is not active puts **Use *name*** in the bottom slot (`PlanText.toUse`, `.useTitle`), which makes it active and empties Today's stack (`PlansView` takes Today's path). Add plan moved to the top right; the mark is never stored. **The page**: the repeat block's chips became squares, names beneath and the entry Next up would start in ink (`RepeatBlock.squares`), and the days became the whole cycle again as rows (`PlanPage.rows`) — repeats included, a rest with nothing to open, any day the cycle never reaches after it — each closed until tapped, an open day v1.8's section with the day's menu on its row. **Use this plan** left Plan detail's ···; nothing else did. `Core/PlanPage.swift`; the seeder's `--plans` (`SEED_PLANS=1` in `tools/shot.sh`). TQ34–TQ37 in `PlansTests`; Y13's Add plan pin reads the top-right button. SPEC §4.2, §4.3, §6.49 and the new §6.51 | Done |
| Q7 | Docs, checklist, bundle, 1.9. SPEC's v1.9 amendments checked against v1.8: every rule a milestone changed keeps the text it replaced beside it (landed as each milestone shipped), and six places where v1.8's words still read as current were caught up — §4.0's colour line and its **Use this plan** example, §6.29's step line, §6.34's Plans line, §6.37's block that opened its plan, §6.41's "exactly four places" (now four places and the squares that name a day, §6.48–§6.51) and §6.42's way to make a plan active — with §6.12's old signature noted and §6.26's offer marked as until v1.9. `docs/DEVICE_CHECKLIST.md`'s **v1.9 rows** (TQ18–TQ20, TQ24, TQ29, TQ33, TQ38, TQ39) with how to make a swap on the phone; `DECISIONS_LOG.md`'s D77 and D78 lines, with D72 naming the D37 amendment and D75 the D50 reversal on Today; TEST_CASES' note that no TQ id was renumbered; version **1.9** in the six `MARKETING_VERSION` settings (the app, the extension and the tests, Debug and Release) and in `docs/APP_STORE.md`; the README's status, counts and plan table; the v1.9 paragraph in `CLAUDE.md` and `AGENTS.md`; the bundle regenerated. No screenshot changed — the ordinary card is unchanged — and `docs/PRIVACY.md` names no files | Done |
| — | The v1.9 device rows (TQ18–TQ20, TQ24, TQ29, TQ33, TQ38, TQ39) | **Written, not run** — need the phone |

### Checked on the simulator (v1.9)

- Q2, on the iPhone 17 simulator with `SEED=1 SEED_SWAP=1 DEVICE="iPhone 17" tools/shot.sh` — Legs
  finished today, which the sample plan's pattern made a rest day: today's square purple with a
  grey dot; Thursday's grey, ringed in yellow, with a purple dot; the moon level with the squares.
  A tap on Thursday opened its card — Rest, the moon, **No exercise Thursday** — with the block:
  *"Thursday's Legs is done. Make Thursday:"*, Rest (checked) and Legs as large squares, and the
  Slide row. Choosing Legs closed it: Thursday's card became Legs with **▶ Start Thursday's Legs**,
  its square purple, its ring faint, no dot. A long press on Thursday brought the block back with
  Legs checked; a long press on today's square raised the callout — a grey square and "was rest" —
  and left the shown day alone.
- Q3, on the iPhone 17 simulator with `SEED=1 DEVICE="iPhone 17" tools/shot.sh` — the sample plan
  on a rest day: the ··· opened on **Change plan** beside seven tiny squares in the cycle's
  colours, grey for its rest, and **Change Today's exercises** beside a grey square, in light and
  in dark. iOS kept the pictures' colours, so the plan's fallback sheet was not built.
- Q4, on the iPhone 17 simulator with `SEED=1 DEVICE="iPhone 17" tools/shot.sh` — the sample plan
  on a rest day: ··· → **Change Today's exercises** pushed the picker, *"For Monday 14 September
  only. The plan does not change."*, with Push, Pull and Legs in their colours under *Push Pull
  Legs · this plan* and **Write a day just for Today** beside a square outlined in ink. Pull
  brought Today back as Pull — an orange square, a grey dot under today's square, Pull's rows and
  **▶ Start Today's Pull**. The last row opened the sheet on a day to fill in, its footer naming
  *Monday's own day* and its Save **Use for Today**. With one plan there was no borrowed day to
  see; the outlined squares at the strip's size are TQ29's, on the phone.
- Q6, on the iPhone 17 simulator with `SEED=1 SEED_PLANS=1 DEVICE="iPhone 17" tools/shot.sh <png>
  -uiScreen plans` (and `-uiPlanDetail` for the page): three plans — Push Pull Legs, seven squares,
  *6 days a week*; Upper Lower, a weekday plan, *4 days a week*; Full Body's fourteen squares, *6
  days every 14* — each behind the accent chevron at its left, the active plan's circle filled and
  the others empty, **Add plan** at the top right and nothing in the bottom slot. The page: *kg ·
  repeats every 7 days* over seven squares with their names beneath and **Push** in ink, then Push,
  Pull, Legs, Push, Pull, Legs as closed rows with grey chevrons, and Rest with none.

### Not run in v1.9

- **Q6's taps.** The simulator tool refused taps again ("stopped retrying after repeated
  crashes"), and no launch argument opens a day or marks a circle, so an open day — its exercises,
  Add exercise, Start and the menu on its row — the circle's **Use Upper Lower**, and the tap that
  makes it active and lands on Today were not seen. To look: `SEED=1 SEED_PLANS=1 DEVICE="iPhone
  17" tools/shot.sh <png> -uiScreen plans`, tap Upper Lower's circle, then the button. On the phone
  these are TQ38 and TQ39.
- **Q5's sheet on the simulator.** `SEED=1 DEVICE="iPhone 17" tools/shot.sh` brought the app up on
  the seeded rest day (seen in a `simctl` screenshot), but the simulator tool then crashed on every
  screenshot and afterwards refused taps as well ("stopped retrying after repeated crashes"), and no
  launch argument opens Plan detail or the JSON sheet. So the named title, the place line, the
  marked line with its bar, the gap its sentence opens beneath it, and the scroll to it were not
  looked at. To look: put a day with `"reps": "lots"` on the simulator's clipboard (`xcrun simctl
  pbcopy`), open a day's **Edit day as JSON**, tap Paste, then **Replace Push**. On the phone this
  is TQ33.
- The ring's breathing and Reduce Motion, the long press under a finger, the block at
  accessibility XL (TQ18–TQ20) and the ···'s symbols at the menu's size on the phone (TQ24) and an outlined
  square beside filled ones on the strip (TQ29) are the phone's, on the checklist's v1.9 rows (Q7).
  VoiceOver's words are held in Core (TQ17) and not yet heard.

## v1.8 (S0–S4): built and green

`docs/ITERATION_9_PLAN.md` is the v1.8 plan, written from the owner's note after looking at
v1.7's Today — *"too much text, and too little use of visual cues"*. Each milestone ends with the
whole suite green on all three routes, a Release build and `tools/check_release.py`, and one
commit on `v1.8-cues`.

After S4:

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'` | **341 tests, 14 skipped, 0 failures** — the skips are the pins that read SPEC or a source file, which run on the host routes. iPhone 16, as in T7, where iPhone 17's test runner never connected |
| `swift test` | **340 tests, 0 failures** |
| `python3 tools/check_core.py` | **340 bodies, 6,622 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **115/115 fixtures match** (unchanged; S4 touches no code) |
| `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'` | **BUILD SUCCEEDED** |
| `python3 tools/check_release.py` | **ready, as far as a script can tell** — version 1.8 (1) |
| `python3 tools/check_bundle.py` | **current** (regenerated in S4) |

| Milestone | What it did | State |
|---|---|---|
| S0 | The plan, the branch, the mock (the "Today, Simpler" artifact, not committed) | Done |
| S1 | Nothing without a cue (D69): a day's card carries no sentence. The colour square stands as tall as the title's capitals; a meta row with a clock and **39 min** *last time* (**23 min** *so far* mid-session); the exercises at body size, each with its sets as blocks in the day's colour at half strength that fill as they are logged; the step as the ···'s last line; **▶ Start Today's Push** in D70's words (**Start Tomorrow's Push**, **Start Thursday's Lower** on a rest day); the gear and the ··· as grey glyphs in hairline circles, on History too. `HomeStart` traded `subtitle` and `exercises` for `sentence` (the empty and nothing-scheduled cards only), `rows`, `lastDuration`, `elapsed`, `stepLine` and `startTitle`. TS1–TS4 in `TodayTests`; T3, T4, O63/O64, U20, W39, Z22, Y13 and the built-in plan's card rewritten for them. SPEC §4.1 (v1.7's text in italics) and §6.43 | Done |
| S2 | The week is the strip (D70): seven small squares at the left of the meta row — the next seven days, today first, each in its day's colour and grey for rest, the shown one larger and the others at half strength — drawn from the calendar's own projection (`Core/WeekStrip.swift`, `CalendarProjection.next(days:from:)`). A tap shows that day (`HomeStart.current(showing:)`; the view's `shownOffset`, never stored, reset when a workout starts) and the button says when — **Start Wednesday's Legs**; a tapped grey square shows D71's rest card early (**Rest**, the moon in the meta row, a disabled moon button); Nothing scheduled draws seven grey squares under **No exercise Today**. **Another day** left the ··· with its chooser and `Gates.anotherDay`; the strip is recorded in §6.40's table as the one control that is not earned; a day started from the strip mid-session raises the switch popup on Today. TS6–TS10 in `TodayTests`; T2, T21 and Z3's pin rewritten, T17 removed. SPEC §4.1, §6.37, §6.40 and the new §6.44 | Done |
| S3 | A rest day says rest (D71): on a rest day the card is **Rest** after a grey square, the strip's first square grey and larger, the moon where the clock was and no minutes, the system's z's in the accent where the rows were, and a disabled **☾ No exercise Today** — reversing D57 on Today, since the next workout is one tap away on the strip (**Start Tomorrow's Pull**). After the day's workout, on every plan, the same card says **✓ Done Today** under a check (the owner's reading, 2026-09-13) — whenever a workout was finished today; a weekday plan's own day no longer offers the workout just done again. A missed workout still speaks with Do it now, and a progression that has run its course with Plan the next one (now the active plan's, as Do it now's is). One function draws today's rest card and a tapped grey square's; `StartCard.restDay` keeps its payload and its target (the screenshot runs). TS13–TS15 and TS17 in `TodayTests`; TS1, O63 and U20 rewritten. SPEC §4.1, §6.33, §6.44 and the new §6.45 | Done |
| S4 | Docs, checklist, bundle, screenshots, 1.8: SPEC §4.1 consolidated with S1–S3's changes and the older text kept in italics under each (landed as each milestone shipped); `docs/DEVICE_CHECKLIST.md`'s **v1.8 rows** (TS5, TS11, TS12, TS16); the README's `today.png` retaken to show the strip and the set blocks (**Push** after its green square, the seven-square strip, **▶ Start Tomorrow's Push**); version **1.8** on the app, the extension and the tests, and in `docs/APP_STORE.md`; the bundle regenerated | Done |
| — | The v1.8 device rows (TS5, TS11, TS12, TS16) | **Written, not run** — need the phone |

### Checked on the simulator (v1.8)

| Screenshot | What it shows |
|---|---|
| `build/s1-today.png` | Today on the seeded plan on a Sunday — a rest day, so the card headlines Monday's Push (D57, until S3) — from `SEED=1 tools/shot.sh build/s1-today.png -uiScreen today -uiNoAsk`: the green square as tall as "Push"; the clock and "39 min last time" at the right; five names at body size, each with its sets as pale green blocks (four for the bench, three for the rest) and no chevron; the gear and the ··· as grey glyphs in hairline circles; **▶ Start Tomorrow's Push** |
| `build/s2-today.png` | Today on the seeded plan on the same Sunday, from `SEED=1 tools/shot.sh build/s2-today.png -uiScreen today -uiNoAsk`: the strip under "Push" — a grey square first, larger, for today's rest entry, then Push, Pull, Legs, Push, Pull, Legs in their colours at half strength, the seven-day cycle as the calendar draws it — with the clock at the row's right; the card behind the first square still headlines Monday's Push (D57, until S3), **▶ Start Tomorrow's Push** |
| `build/s2-today-pull.png` | The same screen after tapping the fourth square (through the simulator, not a launch argument): **Legs** after a purple square, the tapped square drawn larger and at full colour, **28 min** *last time*, Legs' five exercises with their blocks in purple, and **▶ Start Wednesday's Legs** — the card followed the tap and the button said when |
| `build/s3-today.png` | Today on the seeded plan on the same Sunday, a rest day, from `SEED=1 tools/shot.sh build/s3-today.png -uiScreen today -uiNoAsk`: a grey square and **Rest**; the strip with its first square grey and larger, the six workouts after it at half strength; the moon at the meta row's right, and no minutes; the system's blue z's centred in the card's empty half; **☾ No exercise Today**, greyed, in the bottom slot — D57's Push headline gone |
| `build/s4-today-push.png` → `docs/screenshots/today.png` | Today for the README, from `SEED=1 tools/shot.sh build/s4-today.png -uiScreen today -uiNoAsk` then tapping the strip's second square (through the simulator, as `s2-today-pull.png` did): **Push** after a green square, the strip with that square larger, **39 min** *last time*, the five exercises with their sets as green blocks, and **▶ Start Tomorrow's Push**. Downscaled to 720 px high with `sips -Z 720`, like the other four |

### Not run in v1.8

- TS5, Today at accessibility XL on the phone; on the checklist's v1.8 rows (S4).
- TS11 and TS12, the strip at accessibility XL and the shown day surviving a background but not
  a relaunch — both on the phone, on the checklist's v1.8 rows (S4). On the simulator the tap was
  seen to show the day (above); backgrounding and relaunching were not walked.
- The switch popup raised from the strip mid-session: no session was opened on the simulator;
  it is held in Core (TS8) and not yet seen drawn. The rest card was seen (S3, `build/s3-today.png`),
  and a tapped grey square draws the same card from the same function.
- S3's **✓ Done Today**: no workout was finished on the simulator, so the check's card is held
  in Core (TS17) and not yet seen drawn. TS16, the z's and the moon in light and dark and the
  card read by VoiceOver, is on the phone, on the checklist's v1.8 rows (S4).
- The ··· with its step line open on screen: the seeded plan carries no progression, so the line
  is held in Core (TS4) and not yet seen drawn.

## v1.7 (T0–T7): built and green

`docs/ITERATION_8_PLAN.md` is the v1.7 plan, written from the owner's note after living with
v1.6 — *"sensory overload… less choices… more forcing… feels like a settings menu"*. Two
milestones were the owner's call and were chosen on 2026-09-13: T2 is Reading A (Today ·
History) and T5 (a colour per day) is go. Each milestone ends with the whole suite green on all
three routes, a Release build and `tools/check_release.py`, and one commit on `v1.7-today`.

After T7:

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'` | **329 tests, 12 skipped, 0 failures** on iPhone 16 (T7, below) — the skips include T7, T21, T27, T28 and T23's read of `DaySquare.swift`, which read SPEC or a source file and so run on the host routes. T6's first run never reached a test — "the test runner hung before establishing connection" — and this is the rerun, after restarting the iPhone 17 simulator |
| `swift test` | **328 tests, 0 failures** |
| `python3 tools/check_core.py` | **328 bodies, 6,122 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **115/115 fixtures match** (unchanged) |
| `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'` | **BUILD SUCCEEDED** |
| `python3 tools/check_release.py` | **ready, as far as a script can tell** — version 1.7 (1) |
| `python3 tools/check_bundle.py` | **current** (regenerated in T0–T7) |

| Milestone | What it did | State |
|---|---|---|
| T0 | The plan, the branch, the mock (the "Jimm's Bro+ Today" artifact, not committed) | Done |
| T1 | Today is one card (D61): the day's name, one subtitle, the exercise block as the preview, at most one message, Start — and the day's alternatives in one ···. `HomeStart.message` and `.alternatives` are Core data (T1–T4 in `TodayTests`); the calendar, the week's line, Preview, the Week/Month control and the small buttons left the screen; the empty card offers **Choose a plan** and the practice link; Home's tab is Today | Done |
| T2 | How many tabs (D62) — Reading A: the tab bar is **Today · History** (`AppTab`, `Core/Tabs.swift`, drawn as `AppTab.allCases` and held to SPEC §4.0 by T7); Plans is pushed from Today's ··· → Change plan and Settings from a gear top-left on both tabs (`settingsGear`), both keeping large titles; Y13 re-run as T8; `-uiScreen plans` and `settings` land on Today and push the screen. The README's landing section names no tabs, so it did not change | Done |
| T3 | The calendar lives in History (D63): the week strip, **Month**, the tapped-day line and the week's line open History, above Metrics, Find an exercise, Goals and the months (`Features/History/CalendarView.swift`, drawing unchanged). The tapped-day line is Core's (`CalendarText.line` → `DayLine`): "planned", not "projected", and no **Start this**; a finished day opens pushed onto History's stack. With no workouts the strip still shows the plan's week above "No workouts yet" and Import from another app. O66 re-homed as T10, T11–T12 in `HistoryTests`; the seeder takes `--no-history` (`SEED_NO_HISTORY=1`) | Done |
| T4 | Controls are earned (D64): `Core/Gates.swift` has one function per row of SPEC §6.40's table (the plan's §6.39, which T3 took), and the views and `HomeStart` ask it rather than counting. New on screen: **Month** waits for a workout older than this week, and History's search field waits with Metrics and Find an exercise for the first workout. Another day, Change plan, Plan a progression, Goals and the notifications-off line go through `Gates` with their behaviour unchanged. Nothing is stored; each gate is a function of the data. T14–T21 in `GatesTests`, and T21 pins the table to the type | Done |
| T5 | A colour per day (D65): every day of a plan takes a colour by its place in the day list — green, orange, purple, pink, teal, indigo, then round again (`Core/DayColour.swift`), derived and never stored — drawn in four places and nowhere else: a square before the day's name on Today, the calendar's finished fill and planned name (where the reserved green and the accent were), a square leading each History row, and a square leading the workout header and the Lock Screen's title, with the compact Island's figure in it while working. Core decides the colour (`HomeStart.dayColour`, `DayEntry.dayColour`, `DayColour.of(session:plans:)`, `WorkoutActivityState.dayColour`); `DaySquare.swift` is the one mapping to a `Color`, in both targets. T22, T23 and T25 in `DayColourTests`; SPEC §6.41 | Done |
| T6 | Docs, checklist, bundle, screenshots, 1.7: SPEC's remaining Homes made Today, with D18's row, §5.1's button, the progression link and v1.6's hierarchy line keeping their older text in italics; T26, the version check; the v1.7 device rows' failure pointers; the README's landing screenshots (`today.png` for `home.png`, `history.png` retaken on the month), its status, agent paragraph, test counts and document table; version **1.7** on the app, the extension and the tests and in `docs/APP_STORE.md`; the bundle regenerated | Done |
| T7 | The owner's review before the push (SPEC §6.42), three commits: History's search field went — **Find an exercise** is the way (D66, T27); the **Progression** row moved from Plan detail into History's block with Metrics and Find an exercise, for the active plan, and Today's **Plan the next one** opens it (D67, T28); goals were removed — `goals.json` is left unread and a backup that carries goals still restores (D68, T30). Checked on the simulator: History's block and the Progression sheet opened from it. The suite ran on iPhone 16: on iPhone 17 the test host launched and XCTest never connected, four runs in a row and across a simulator restart — the simulator's, not the app's (the same build passed on iPhone 16, and the Release build for iPhone 17 succeeded) | Done |
| — | The v1.7 device rows (T5, T9, T13, T24, T29) | **Written, not run** — need the phone |

### Checked on the simulator (v1.7)

| Screenshot | What it shows |
|---|---|
| `build/today.png` | Today on the seeded plan, from `SEED=1 tools/shot.sh build/today.png -uiScreen today -uiNoAsk` (T6): "Push", "Planned for Mon · Push Pull Legs · 5 exercises · 39 min last time", the five names with a chevron, the ··· top-right, **Start Push** in the bottom slot; no calendar, no week line, no buttons under the names |
| `build/t2-today.png` | Today after T2, from `SEED=1 tools/shot.sh build/t2-today.png -uiScreen today -uiNoAsk`: the gear top-left, the ··· top-right, and a tab bar of **Today** and **History** and nothing else |
| `build/t2-plans.png` | `-uiScreen plans`: the Plans list pushed onto Today — a back button, the large title, the plan in use marked, **Add plan** in the bottom slot, Today still selected in the tab bar |
| `build/t2-settings.png` | `-uiScreen settings`: Settings pushed onto Today, with a back button and its large title |
| `build/t2-history.png` | `-uiScreen history`: the same gear at the same point as Today's, top-left, above the large title |
| `build/t3-history.png` | History after T3, from `SEED=1 tools/shot.sh build/t3-history.png -uiScreen history -uiNoAsk`: **This week** and **Month** over the strip — today outlined (a rest day, drawn as a dash), the plan's days named in the accent — then "No workouts yet this week" (the seeded six are all last week or earlier), Metrics, Find an exercise, Goals and September 2026 |
| `build/t3-history-empty.png` | `SEED=1 SEED_NO_HISTORY=1 tools/shot.sh … -uiScreen history -uiNoAsk`: the plan and no workouts — the plan's week in the strip (Push today, outlined; Saturday a rest dash), "No workouts yet" under it, then **Import from another app** with "Finished workouts appear here." |
| `build/t4-history.png` | History after T4, from `SEED=1 tools/shot.sh build/t4-history.png -uiScreen history -uiNoAsk`: the seeded six workouts are all older than this week, so **Month** is earned, and the search field, Metrics, Find an exercise, Goals and September 2026 are there — the screen T3 left |
| `build/t4-history-empty.png` | `SEED=1 SEED_NO_HISTORY=1 tools/shot.sh … -uiScreen history -uiNoAsk`: the plan and no workouts — **This week** with no Month beside it, no search field under the title, the plan's week in the strip, "No workouts yet" and **Import from another app**; no Metrics, Find an exercise or Goals |
| `build/t6-today.png` → `docs/screenshots/today.png` | Today for the README, from `SEED=1 tools/shot.sh build/t6-today.png -uiScreen today -uiNoAsk` after T5: the green square before "Push", "Planned for Mon · Push Pull Legs · 5 exercises · 39 min last time", the five names with their chevron, the gear and the ···, **Start Push**, and a tab bar of Today and History |
| `build/t6-history-week.png` | `SEED=1 SEED_GOALS=1 SKIP_BUILD=1 tools/shot.sh build/t6-history-week.png -uiScreen history -uiNoAsk`: the strip's planned days named in their colours (Push green, Pull orange, Legs purple), "No workouts yet this week", Metrics, Find an exercise, the two goals, and a Legs row led by its purple square |
| `build/t6-history-month.png` → `docs/screenshots/history.png` | The same after tapping **Month**: September 2026 with the six finished days filled in their days' colours — Push on the 1st and 8th, Pull on the 3rd and 10th, Legs on the 5th and 12th — the planned days named in the same colours, today outlined, Sundays as rest dashes. Both README shots downscaled to 720 px high with `sips -Z 720`, like the other three |

### Not run in v1.7

- The four device rows, which need the phone: T5 (Today at accessibility XL, every state, on the
  smallest supported iPhone), T9 (Plans and Settings reached from Today by hand, back to the tab
  each left, and the gear in the same place on both tabs), T13 (History's calendar by hand —
  Month and Week, a done day tapped twice landing on its session, and back) and T24 (one day, one
  colour, in all four places and on the Lock Screen, in light and in dark).
- The App Store's 1320 × 2868 screenshots (`APP_STORE.md` §5): the table names Today and History
  as they now are; the captures are taken with the submission.

The one-commit gap T1 left — the calendar off Today and not yet on History — closed in T3.

## v1.6 (U0–U7): built and green (merged as pull request #2)

`docs/ITERATION_7_PLAN.md` is the v1.6 plan, built from the 2026-09-09 usability audit
(`docs/UX_REVIEW_2026-09-09.md`): v1.5 walked on the simulators as a stranger (a clean install
through the first workout) and as a returning user, judged for the owner's three users — a
coach, a great-grandparent and a five-year-old. Every milestone ended with the whole suite green
on all three routes, a Release build and `tools/check_release.py`, and one commit on
`v1.6-refinement` (off `main`, which holds v1.5).

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'` | **312 tests, 7 skipped, 0 failures** |
| `swift test` | **311 tests, 0 failures** |
| `python3 tools/check_core.py` | **311 bodies, 5,981 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **115/115 fixtures match** (unchanged) |
| `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'` | **BUILD SUCCEEDED** |
| `python3 tools/check_release.py` | **ready, as far as a script can tell** — version 1.5 (1) |
| `python3 tools/check_bundle.py` | **current** (regenerated in U5, U6, U7 and U4; CI's bundle job was red for U1–U3's pushes until then) |

| Milestone | What it did | State |
|---|---|---|
| U0 | The plan, and the audit it answers, committed | Done |
| U1 | Nothing untrue (D55): a missed workout only when the plan expected one; "Nothing logged" before "First time"; calendar labels unique within the plan; a chip that never contradicts the fields; the right sentence for a plan pasted in words; the overview says a note once; version 1.5 | Done |
| U2 | Nothing unreachable (D56): every menu confirmation an alert with two buttons; Done in the strip, off Log set; no phantom bar under empty sheets; the empty weight field looks like one; Finish not red; large text keeps the inputs and the button on one screen; the stage said once | Done |
| U3 | The first five minutes (D57): no warm-up on a fresh install (old files keep theirs); **Start first set** during a warm-up; the notification permission at the first Log set; the weight hint; the unit asked on the review; **Start here** in the picker; Home headlines the workout on a rest day; "Next: …" on the Summary | Done |
| U4 | Plain words (D58), **Reading B**: the app speaks in words — "Aim 4–6 reps · 100 kg", "Last time 10 × 100 kg", "paired with …", "lighter set 1 of 2", "as many reps as you can", "stop 2 short of failure" — and **Settings → Compact notation** restores v1.5's forms. The prompt and the progression ladder keep them regardless | Done |
| U5 | Hierarchy (D59): Start in the bottom slot; headers in ink; small actions as buttons; a quieter grid; Undo on the row; an idle strip that says what follows; chips that wrap; Add exercise and Start per day; labelled History rows and a Find an exercise row; Settings presets; sentences for a stranger; "Use this plan" | Done |
| U6 | Docs, checklist rows, bundle | Done |
| U7 | An activity that outlived the app (D60): the Live Activity the owner could only clear by deleting the app. `SystemActivityPresenter` holds no handle — `Activity.activities` is asked instead — and every launch reconciles the Lock Screen | Done |
| — | The v1.6 device rows (U9, U10, U13, U22, U23, U28, U33, U37) | **Written, not run** — need the phone |

### Checked on the simulator (v1.6)

Every screenshot is from a real build; the `u3-*` ones from a clean install on the iPhone 16
simulator, the rest from the iPhone 16 or 17 with data the walkthrough itself produced.

| File | Shows |
|---|---|
| `build/u2-home.png` | A three-minute-old plan with no "was due Sunday"; calendar cells FBA / FBB |
| `build/u2-warmup.png`, `build/u2-working.png` | The empty weight reading *tap to type* in its outline; the stage said once |
| `build/u2-keyboard.png` | The keyboard up with Done in the strip and nothing over Log set |
| `build/u2-finish-alert.png`, `build/u2-finish-alert-2.png` | Discard and Finish as alerts with a visible way out; Finish not red |
| `build/u2-ax-2.png` | Accessibility-XL text with the reps, the weight and Log set on one screen |
| `build/u2-addplan-empty.png` | Add plan with no white rectangle at the bottom |
| `build/u3-02-intro-2.png` | The intro's rest page saying the app will ask to send the alert |
| `build/u3-03-picker.png` | **Start here** on Full Body; the sentence that names Copy prompt |
| `build/u3-04-review.png`, `build/u3-05-review-lb.png`, `build/u3-13-review-kg.png` | The review asking kg / lb, the line beneath following the choice |
| `build/u3-06-home.png`, `build/u3-10-home-after.png` | Home before and after the first workout: "Start Full Body A", then "Full Body B · Planned for Fri" |
| `build/u3-07-card.png` | The first card with no warm-up, the hint under the empty weight |
| `build/u3-08-permission.png` | The permission alert over a counting rest, at the first Log set |
| `build/u3-09-summary.png` | The Summary with "Next: Full Body B, Friday" and "Nothing logged" |
| `build/u5-01-home.png` | Start above the tab bar, headers in ink, bordered links, a planned day without a box |
| `build/u5-02-workout-idle.png`, `build/u5-03-undo-row.png` | "Rest 3:00 starts when you log"; ↺ on the logged row |
| `build/u5-04-plan-detail.png`, `build/u5-04b-plan-detail-end.png` | "lb · repeats every 14 days", chips on three lines, Add exercise and a bordered Start |
| `build/u5-05-history.png`, `build/u5-06-settings.png` | "2 min · 1 set · 540 lb lifted", Find an exercise; the preset rows |

### Not run in v1.6

- The device rows above. Three findings depend on system presentation — the popover dialogs,
  the keyboard's Done pill and the search field — and were seen on the iOS 27.0 simulator; the
  phone should confirm them.
- U4, by design: the plan's two readings are the owner's to choose between.

## v1.5 (Z0–Z6): built and green

`docs/ITERATION_6_PLAN.md` is the v1.5 plan — the owner's notes after living with the app, with
the four readings that led to different builds put to the owner and chosen the same day. Every
milestone ended with the whole suite green on all three routes, a Release build and
`tools/check_release.py`, and one commit on `v1.5-refinement` (off `main`, which holds v1.4).

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'` | **287 tests, 7 skipped, 0 failures** |
| `swift test` | **286 tests, 0 failures** |
| `python3 tools/check_core.py` | **286 bodies, 5,797 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **115/115 fixtures match** (the original 111, plus four for `inReserve`) |
| `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'` | **BUILD SUCCEEDED** |
| `python3 tools/check_release.py` | **ready, as far as a script can tell** |
| `python3 tools/check_bundle.py` | **current** |

The seven skipped cases read the checkout — the five prompt pins (plan, fix-it, progression,
outline, day), the introduction's source pin (Y13) and the D50 sentences' pin (Z3) — outside the
simulator's sandbox. They run on the other two routes.

| Milestone | What it did | State |
|---|---|---|
| Z0 | The plan, the branch, the owner's readings | Done |
| Z1 | Clearer, not louder: the Progression row's line and chevron, Home's quiet link, the accent Copy prompt beside its sentence, the mechanism footer; `PromptText` pinned to the views (D50) | Done |
| Z2 | The effort target: `inReserve` (alias `rir`) at exercise and set level, on the card, in summaries, in the edit sheet and the JSON, in the prompt, in the reference implementation, schema and four fixtures (D51) | Done |
| Z3 | A plan in several pastes: the outline prompt and draft, one day per paste named by its slot, the assembly through the importer, `draft.json`, PROMPT.md §4–5 pinned (D52) | Done |
| Z4 | Steps you earn: `Progression.mode`, per-entry `step` and `tries`, achievement by the advice's arithmetic, the advance on completion, the ladder on screen, the prompt's cadence, `steps` in the reply with `weeks` as the alias (D53) | Done |
| Z5 | A goal per exercise: `goals.json`, progress and reached, the History section and sheet, the Summary line, the backup, MY GOALS in the prompt (D54) | Done |
| Z6 | Docs, checklist rows, bundle | Done |
| — | The v1.5 device rows (Z4, Z10, Z17, Z25, Z31) | **Written, not run** — need the phone |
| — | "A history for each exercise" as typed current numbers | **Parked** by the owner (the plan's last section) |

### Checked on the simulator (v1.5)

Every screenshot is from a real build on a booted iPhone 17 simulator; the seeded ones through
the app's own `Store` (`tools/seed`, which can now attach a stepped progression and two goals).

| File | Shows |
|---|---|
| `build/z1-home.png` | Home with history on every exercise of the day: Preview · Another day · **Plan a progression** |
| `build/z1-plan.png` | Plan detail's Progression row with its line and the accent chevron |
| `build/z1-addplan.png` | Add plan's step 1 with the sentence, the accent Copy prompt, and the mechanism footer |
| `build/z2-review.png` | A pasted plan's review: "3 × 6–8 · 80 kg · 2 in reserve", the alias read, seconds on the hold, nothing where the plan said nothing |
| `build/z3-draft-empty.png` | Build it day by day before an outline: the outline step and Paste outline |
| `build/z3-draft-outline.png` | The outline pasted: the header, the repeat block, three empty slots |
| `build/z3-draft-day.png` | A day pasted with prose and a fence around it: "1 of 3 days pasted", the slot at "3 exercises" |
| `build/z4-plan.png` | Plan detail's row reading "Step 1 of 4" for a stepped progression |
| `build/z4-progression.png` | The Progression screen: one exercise on step 2 with ▸ moved, one at "Step 1 of 4 · 1 try", the ladders |
| `build/z4-planning.png` | Planning: How many steps, **Advance** (When I hit the target / Every week) with its explanation, the accent Copy prompt |
| `build/z5-history.png` | History's Goals section: one reached in green with its date, one climbing with its bar and date, Set a goal |

### Not run in v1.5

The three flows that need a chatbot's reply (Z17's day prompts, Z25's steps, Z31's MY GOALS
block) were exercised with pasted JSON, not with a live chatbot; the prompts are pinned to their
documents and the readers to their fixtures, and the owner's phone is where a real reply gets
tried. Nothing in v1.5 changed the workout screen's zones, the timers or the notifications.

## v1.4 (Y0–Y5): built and green

`docs/ITERATION_5_PLAN.md` is the v1.4 plan — the owner's four notes after running v1.3 on the
phone: the second between a tap and its screen, getting the app ready to publish, an
introduction, and built-in plans. Every milestone ended with the whole suite green on all three
routes, from Y4 with a Release build and `tools/check_release.py` as well, and one commit on
`v1.4-release` (off `main`, which holds v1.3).

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'` | **259 tests, 4 skipped, 0 failures** |
| `swift test` | **258 tests, 0 failures** |
| `python3 tools/check_core.py` | **258 bodies, 5,311 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **111/111 fixtures match** |
| `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'` | **BUILD SUCCEEDED** — the first Release build of the app |
| `python3 tools/check_release.py` | **ready, as far as a script can tell**: version 1.4 (1), an opaque icon, the compliance answer in the binary, the policy and the submission page, every built-in plan bundled |
| `python3 tools/check_bundle.py` | **current** |

The four skipped cases are the prompt pins (M9 and W37) and the introduction's source pin (Y13),
which read the checkout — outside the simulator's sandbox. They run on the other two routes.
The Xcode on this Mac is 27.0 build `27A5252f`, a beta, and its simulators are the iPhone 17
family, so the destination is now `iPhone 17`; any installed iPhone works.

| Milestone | What it did | State |
|---|---|---|
| Y0 | The plan, the branch | Done |
| Y1 | The workout opens the moment it exists: `startedWorkouts` counted before the notification, the Island and the disk write; the cover on the count; no view waits on `startDay` (D48) | Done |
| Y2 | Four built-in plans through the ordinary pipeline with no warnings and no weights, one spelling per movement, minutes computed from the plan; the picker in Add plan and on Home; Add plan presented from an item because a sheet's closure captures stale state (D46) | Done |
| Y3 | The introduction: four Core pages pinned to real control names; a cover on a launch with no plans; `Settings.introSeen` optional on disk; How the app works in Settings (D47) | Done |
| Y4 | An opaque icon and a generator that keeps it so, the compliance answer, version 1.4 (1) on all targets, the first Release build, `check_release.py`, `PRIVACY.md`, `APP_STORE.md`, a README section for people (D49) | Done |
| Y5 | Docs, checklist rows, bundle | Done |
| — | The v1.4 device rows (Y3, Y11, Y16, Y19) | **Written, not run** — Y19 needs TestFlight, which needs the paid program |
| — | The Developer Program, a release Xcode, the LICENSE, the submission | **The owner's** — `docs/APP_STORE.md` §1 and §6 |

### Checked on the simulator (v1.4)

Every screenshot is from a real build on a booted iPhone 17 simulator.

| File | Shows |
|---|---|
| `build/y2-home.png` | Home's empty card on a clean install: "Choose a built-in plan, or get one from a chatbot." and the two links |
| `build/y2-builtins.png` | The built-in picker: four rows with days, minutes and equipment, and the build-your-own footer — opened from Home's link, and from `-uiScreen import -uiBuiltIns` |
| `build/y2-review.png` | Full Body's review: the paragraph on top, the plan in lb (the simulator is set to the US), the repeat block, the days with ranges and no weights, Save plan |
| `build/y3-intro.png` | The introduction's first page on a clean install, with Choose a plan and Not now |
| `build/y3-after-choose.png` | Choose a plan landed on the picker once the cover was down |

### Not run in v1.4

The second the owner saw (Y1) was diagnosed by reading the code — the cover waited for
`startDay`, which waited for the Live Activity — and the fix is proven by a test against a
scheduler that never returns, not measured on the phone; Y3 is the row that measures it. Two
things about that second are worth knowing and were not changed: a Debug build from Xcode runs
SwiftUI and the import pipeline unoptimised, and TestFlight ships Release; and the first tap
into a text field in a session pays the keyboard's own warm-up, which no app controls. The
Release build was compiled for the simulator, not archived — archiving needs the distribution
certificate the paid program provides.

## v1.3 (X0–X6): built and green

`docs/ITERATION_4_PLAN.md` is the v1.3 plan — the owner's list after running v1.2, with
"implement them seamlessly" attached to all of it. Every milestone ended with the whole suite
green on all three routes and one commit, on the `v1.3-refinement` branch (off
`v1.2-refinement`, which is not yet merged to main).

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'` | **246 tests, 3 skipped, 0 failures** |
| `swift test` | **245 tests, 0 failures** |
| `python3 tools/check_core.py` | **245 bodies, 4,055 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **111/111 fixtures match** |
| `python3 tools/check_bundle.py` | **current** |

The three skipped cases are the prompt pins (M9 and W37), which read `docs/PROMPT.md` from the
checkout — outside the simulator's sandbox. They run on the other two routes.

| Milestone | What it did | State |
|---|---|---|
| X0 | The plan, the branch | Done |
| X1 | The Dynamic Island the width of its timer: `timerRange` in Core, never inverted, never an hour (D41) | Done |
| X2 | Change exercise mid-workout: pending steps to a new name that keeps its own history; a split when something was logged (D42) | Done |
| X3 | JSON edits at every size, spliced into the plan's own tree and re-imported; Edit JSON, Add day / Add exercise from JSON (D43). Fixed on the way: a plan edit and Replace both dropped `cycleAnchor` | Done |
| X4 | History as CSV in Strong's column order, and a reader for its own, Strong's and Hevy's exports by header name; read-then-describe-then-Import (D45) | Done |
| X5 | Progression: the prompt out, the reply in, the week applied to the day's snapshot, the chip's reason, Home's line (D44) | Done |
| X6 | Docs, checklist rows, bundle | Done |
| — | The v1.3 device rows (W3, W12, W21, W30, W40) | **Written, not run** — needs the owner's iPhone |

### Checked on the simulator (v1.3)

Every screenshot is from a real build on a booted simulator, seeded through the app's own `Store`.

| File | Shows |
|---|---|
| `build/x2-change.png` | The Change exercise sheet over a running workout: the name field, the exercises done before, the optional weight, **Change** |
| `build/x3-plan.png` | Plan detail with the Progression row and, in the menus, Edit JSON, Add day from JSON, Add exercise and Edit day as JSON |
| `build/x5-home.png` | Home with a progression on the plan: the subtitle ends "week 1 of 4", and nothing else moved |
| `build/x5-progression.png` | The Progression screen reading a saved progression back: the week, this week's targets first, every week in one line, **Plan the next one** |

### Not run in v1.3

The Island's width (W3) needs a phone with one. What the compact view is given is unit-tested
(`timerRange`, W1–W2), but nothing here has measured it on a Dynamic Island.


## v1.2 (V0–V7): built and green

`docs/ITERATION_3_PLAN.md` is the v1.2 plan, and `docs/CODE_HEALTH_REVIEW.md` is the review that
prompted half of it; the other half is the owner's notes after running v1.1 on the phone. Every
milestone ended with the whole suite green and one commit, on the `v1.2-refinement` branch.

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'` | **210 tests, 2 skipped, 0 failures** |
| `swift test` | **209 tests, 0 failures** — this route had not compiled since `AppModel` became `@Observable`; V1 fixed it |
| `python3 tools/check_core.py` | **209 bodies, 3,289 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **111/111 fixtures match** |
| `python3 tools/check_bundle.py` | **current** |

The two skipped cases are the prompt pins (M9), which read `docs/PROMPT.md` from the checkout —
outside the simulator's sandbox. They run on the other two routes, both of which are on the host.

| Milestone | What it did | State |
|---|---|---|
| V0 | Repository hygiene: leftover rewrite refs deleted, `tools/icon` and `tools/seed` rescued from the ignored `build/`, `tools/check_bundle.py` | Done |
| V1 | The five confirmed defects of the code-health review, and `swift test` unbroken | Done |
| V2 | Schema durability (`Core/Persistence.swift`, `examples/store/v1/`), `AlertIdentifier` and `SessionBlocks` as one definition each, the prompt pinned to its doc | Done |
| V3 | Warm-up (D32), the timed walk between exercises (D33), the stage in the header (D34) | Done |
| V4 | Loadable weights (D35) and a per-set suggestion with its reason (D36) | Done |
| V5 | The anchored rotation (D37) and a calendar you can read (D38) | Done |
| V6 | Session and trend metrics (D39) | Done |
| V7 | Lock Screen and Dynamic Island (D40), and the `JimmsBroActivity` extension target | Done |
| — | The v1.2 device checklist | **Written, not run** — needs the owner's iPhone |

### Checked on the simulator (v1.2)

Every screenshot is from a real build on a booted simulator, seeded through the app's own `Store`.

| File | Shows |
|---|---|
| `build/v3-warmup.png` | A session opening in a warm-up: the stage named, the countdown, the first exercise already up, **Log set** live |
| `build/v3-resting.png` | The same screen resting between sets |
| `build/v3-between.png` | The walk between exercises: its own countdown, the next exercise already showing, the finished block's sentence on the strip |
| `build/v5-home.png` | Home and the week strip agreeing: "Rest day · Push is next, Tue" over a grid that names each day and draws the rest day as a gap |
| `build/v6-metrics.png` | A past workout's metrics: duration, working and resting share, sets, volume, reps, heaviest set, PRs |

### Not run in v1.2

The Live Activity itself (Q71–Q73) needs a phone: the extension builds, embeds and installs, and
what it would draw is unit-tested through `ActivityPresenting`, but nothing here has watched it
appear on a Lock Screen.

## v1.1 (refinement release): R0–R5 done, R6 open

`docs/ITERATION_2_PLAN.md` is the v1.1 plan. R0 through R5 are implemented and green:
`xcodebuild test` reports **148 tests, 0 failures** on the iPhone 16 simulator, and the portable
Core runner reports **147 test bodies, 2,939 assertions, 0 failures**. SPEC.md, TEST_CASES.md and
DECISIONS_LOG.md were amended alongside the code, per milestone, before it was written.

| Milestone | What it did | State |
|---|---|---|
| R0 | Truthfulness: skipped-set recovery (D27), every delete confirms (D25), Replace, the activation toggle, calendar taps that open the session, and a surfaced save failure with Retry (D24) | Done |
| R1 | Core for the new loop: `.transition` removed (D14), `blockDone`, undo (D23), the prefill rule for varied exercises (D11) | Done |
| R2 | The workout screen rebuilt as five fixed zones (D22) | Done |
| R3 | Home leading with the workout (D18) and **Add plan** replacing the JSON editor (D26) | Done |
| R4 | One visual language, and the Summary said in words | Done |
| R5 | Do later (D28), plan editing (D29), the exercise chart, search and PR marker (D30), backup restore (D31) | Done |
| R6 | Device checklist v2 | **Written, not run** — needs the owner's iPhone |

### What changed, by milestone

- **R0** — `SessionEngine.editSet` recovers a skipped step (D27) instead of silently doing
  nothing; every plan/session delete confirms (D25); Plan detail gained **Replace**; the import
  preview gained a **Set as current plan** toggle; the Home calendar's second tap on a completed
  day opens it; a failed write is surfaced as `AppModel.saveFailure` with **Retry**. A real bug
  was caught by the new failure-injection test, not by inspection: `SessionRunner.run(_:)` was
  clearing `active-session.json` on a batch's trailing `.persist` even when the session's own
  save had just failed.
- **R1** — the `.transition` phase is gone (D14); a v1 file holding it still decodes.
  `Event.undoLog` (D23). Prefill no longer carries a weight forward across a **varied**
  exercise's sets (D11), and the dynamic "changing weight re-prefills reps" rule is removed.
- **R2** — the workout is one screen with five fixed zones (SPEC §4.5, D22), resolved as data by
  `WorkoutScreen.model` so "the zones never move" is a unit test (O50) rather than a convention.
  Rest, the block-done line and the timed-set state are contents of one status strip; the primary
  button never moves; Exercises, minimize and "···" are reachable in every state. Undo moved onto
  the strip. Three defects were found on the simulator: notes repeating on every set row, two
  superset rows reading identically (`StepCard.rowLabel` now lives in Core and is shared with the
  Overview and Session detail), and the header wrapping to four lines at accessibility XL.
- **R3** — Home names the day, the plan and its exercises and says what its button will do (D18);
  a 7-day strip discloses to the month; one activity line replaced the sparkline, which was
  removed along with `HomeMetric` and its Settings row. **Add plan** (D26) offers Paste plan,
  the three-step chatbot round-trip and Import file, with the JSON editor behind "Show text";
  errors lead with a sentence (`IssueText.friendly`, one per `E_` code); **Review plan** shows the
  exercises with per-set targets and separates material warnings from tidying.
- **R4** — one grouped-list language on every screen, a green reserved for "this happened",
  pressed states, and a Summary that says "2 more reps at the same weight" instead of printing
  both sessions' raw sets. Volume totals are grouped ("12,400 kg").
- **R5** — **Do later** (D28) moves an exercise's remaining sets to the end of the day; **plan
  editing** (D29) renders a plan back to JSON and re-imports it, so an edit is validated by the
  import pipeline itself (C40 asserts that round trip over every valid fixture, and caught a real
  bug: an "off" warning beep has to be written as an explicit `false`); the **exercise chart**,
  History **search** and the **PR** marker (D30); and **backup restore** with Merge / Replace all
  (D31).
- **R6** — `docs/DEVICE_CHECKLIST.md` gained a v1.1 section (H24, H33, O53–O60, O76–O82, K27–K28
  and the T2–T6 acceptance tasks) and `-uiReadOnlyStore`, a DEBUG-only argument that makes every
  write fail so D24's Retry path can be exercised on a real phone. Building it found a genuine
  bug: the save-failure alert was attached only to `RootView`, which the workout is presented
  *over*, so a failed write mid-workout showed nothing at all. Fixed, and visible in
  `build/r6-savefail.png`.

### Checked on the simulator (v1.1)

Every screenshot is from a real build on a booted simulator, seeded through the app's own `Store`.

| File | Shows |
|---|---|
| `build/r2-working.png` | The five zones, working: header, exercise + set rows, labelled inputs, empty strip, Log set |
| `build/r2-resting.png` | Resting: countdown, −30/+30/Skip, "Next: …", "set 0:06" and Undo, with the set rows still on screen |
| `build/r2-blockdone.png` | A finished block: the next exercise already showing, the block's line and "moving on · 0:03" in the strip, no Continue gate |
| `build/r2-superset.png` | A superset round, its rows named by exercise rather than all reading "A · Set 3 of 3" |
| `build/r2-timed.png` | A timed set: TIME label, 0:45, **Start timer** in the same primary slot, no weight row |
| `build/r2-xl.png` | Accessibility XL: the header reflowed to two rows, rest controls on their own row, nothing clipped |
| `build/r4-workout.png`, `build/r4-dark.png` | The R4 visual pass, light and dark |
| `build/r4-summary.png` | "Workout saved", one sentence per exercise, the set table only where the weights varied |
| `build/r3-home.png` | Home leading with the workout, the week strip and the activity line |
| `build/r3-addplan.png`, `build/r3-review.png`, `build/r3-errors.png` | Add plan's three ways in; Review plan with per-set targets; an error said in a sentence |
| `build/r5-plandetail.png` | Plan detail with Edit, per-day menus and per-set variation |
| `build/r5-exercise.png` | The exercise chart, top weight over time with reps annotated |
| `build/r6-savefail.png` | The save-failure alert over the workout screen, with Retry |

### Not done

- **R6's rows have not been run.** They need the owner's iPhone. Signing is already configured
  (`DEVELOPMENT_TEAM = 3CDZYD6W6G` on both targets), so nothing blocks a device build but the
  phone being plugged in — see `docs/DEVICE_CHECKLIST.md`.
- ITERATION_2_PLAN §7 step 4 asks for the owner's phone walkthrough of T2–T6 after R2, before R3.
  That checkpoint was **not** taken: R3–R5 were built straight through on the instruction to
  complete the remaining refinements. If the walkthrough turns up something about the workout
  screen, R3–R5 sit on top of it.
- The six owner decisions in ITERATION_2_PLAN §9 were never answered in writing. Everything above
  was built on the plan's own recommendation for each, which is now recorded in SPEC §1 (D18,
  D22–D31) as the contract.

## v1 (M0–M7)

M0 through M7 are implemented and **certified on iOS XCTest and the Simulator**: `xcodebuild test`
runs the whole suite green on the iPhone 16 simulator. (The M7-era licence blocker and the beta
Xcode in `~/Downloads` are gone: there is one Xcode, at `/Applications/Xcode.app`, and a plain
`xcodebuild` works.)

M4's and M5's screens are built and were checked on the simulator (see **Screens checked** below).
Start and Resume now run a real workout end to end: step card, rest, the between-exercises done screen,
timed sets, overview, summary and resume after a relaunch. History lists finished workouts by month,
with an editable, deletable session detail and a per-exercise history showing the best set. Settings is
complete, including export and delete-all, and the polish pass is done: dark mode, Dynamic Type to
accessibility XL, VoiceOver labels, and an app icon.

What remained after M7 was M8: the `manual` cases in `TEST_CASES.md`, which need the owner's iPhone. They are still outstanding, now as part of v1.2's device checklist.

## Results actually run

| Check | Result |
|---|---|
| **iOS XCTest + Simulator (beta Xcode, iPhone 16)** | **97 tests, 0 failures — `** TEST SUCCEEDED **`** |
| M0 hosted resource test (`ProjectSkeletonTests`) | Passed on the simulator; no longer pending |
| M3 store tests (`StoreTests`, K1–K15) | 15 tests, 0 failures |
| M4 settings/home tests (`SettingsAndHomeTests`, N1–N2, N8–N10) | 14 tests, 0 failures |
| M5 workout tests (`WorkoutTests`, N3–N7, H1, H2, H17) | 15 tests, 0 failures |
| M6 history tests (`HistoryTests`, O14–O16) | 8 tests, 0 failures |
| M7 settings/polish tests (`SettingsPolishTests`) | 7 tests, 0 failures |
| Portable Core checks (Command Line Tools) | 96 test bodies, 2,022 assertions, 0 failures |
| Python reference importer | 111/111 fixtures match the manifest |
| Original fixture integrity | 112/112 files under `examples/` match the design-package zip byte-for-byte |
| Core isolation | No SwiftUI/UIKit imports in `Core/` or `Store/` |
| M0 simulator visual check | App installs and launches on a booted simulator, showing its name (`build/m3-home.png`); no longer pending |

Logs and result bundles: `build/M7-beta.xcresult`, `build/m7-beta-tests.log` (generated, ignored by git).

## Screens checked on the simulator

Each was captured from a real build on a booted simulator, with the store seeded through the app's own
`Store` code (`tools/seed/`). Screenshots are in `build/`.

| Case | Screen | Result |
|---|---|---|
| O1 | Empty Home | Two buttons, four tabs; "Try the sample plan" imports and activates |
| O2 | Import, text on the clipboard | Paste enabled, editor fills |
| O3 | Import, no text on the clipboard | PasteButton disabled; nothing happens |
| O4 | Import error list | Each row shows path, message and code; Copy fix-it prompt present |
| O5 | Preview sheet | Warnings in yellow with paths, day table counts, cycle chips |
| O6 | Name conflict | Replace / Keep both / Cancel all present |
| O29 | Home with data | Start card, calendar, sparkline, four tabs; nothing else |
| O30 | Calendar dots | Filled accent for completed, hollow accent for projected, grey for scheduled rest days, none for days the plan says nothing about, today outlined |
| O31 | Sparkline | 44 pt, no axes, one caption; metric cycles and persists |
| O35 | Plan detail repeat block | Chips with the current position highlighted, "repeats every 7 days" |
| O38 | Preview cycle chips | Present |
| O9 | Step card order and fit | Name, set line, target, bold last-time entry, reps row, weight row + Last line, Log set directly beneath |
| O9c | Rest overlay | Countdown largest, −30/+30, "Next: …", set time on top, Skip rest |
| O10 / O43 | Overview | Grouped by block with durations; logged rows read "8 @ 80 · 0:00"; pending rows show the target; drops and superset members named |
| O13 | Summary | Duration, sets, volume; per exercise duration, this-vs-last, advice |
| O32 | Done screen | Block name, duration largest, advice, running stopwatch, one Continue button |
| O34 | Drop rows | "· drop 1 of 2" with the weight prefilled from the previous step |
| O39 | Bodyweight card | No weight row; Log set directly under the reps row |
| O41 | Fixed-duration card | Countdown with Done; the number turns accent at the warning |
| O14 | History list | Grouped by month, newest month and newest session first, with duration · sets · volume |
| O15 | Session detail | Every set editable; exercises grouped with block durations; delete behind "···" |
| O16 | Exercise history | Best set on top, sessions newest first; reachable from the step card, session detail and summary |
| O17 | Dark mode | Every screen legible; the countdown stays primary while resting and turns accent on overrun, so the two states are distinct |
| O18 | Dynamic Type at accessibility XL | Nothing clipped; the target line wraps; Log set fully on screen |
| O19 | VoiceOver | The card's description is one element reading "Bench Press, set 2 of 4, target 8 to 12 reps, at 60 kilograms"; "Rest over" is announced once at zero |

Three rendering defects were found and fixed this way: the calendar's weekday header collapsed to five
columns, the primary buttons were not full width, and the sparkline rendered empty whenever no two
workout days were adjacent.

M6's pass found one more: the History month headings were a month early whenever a session sat near a
month boundary, because the section key is the month's first instant in the injected calendar while the
formatter was still reading it in the system zone.

M5's pass found and fixed three more: the workout dismissed straight past the Summary (the engine is
cleared the instant a session completes, so the finished session needed its own hold), Log set was
pinned to the screen bottom leaving a dead gap instead of sitting under the weight row, and every row
of a superset in the overview read "A · Set 1 of 3" with no way to tell the two exercises apart.

After M4 the owner asked for scheduled rest days to be visible. `DayEntry` gained a `.rest` case, rest
days now draw a grey dot and tapping one reads "Sun 14 · Rest day", while days the plan says nothing
about still draw nothing. SPEC §4.1 and §6.12, TEST_CASES O30, `HANDOFF_BUNDLE.md` and the docs inside
`JimmsBro-design-package.zip` were all updated to match (`build/o30-rest-dots.png`).

The portable runner executes the real test methods in `JimmsBroTests` through the assertion adapters
in `tools/CoreCheckSupport.swift`. It discovers no-argument `test*` methods (sync and async), refuses
an empty filtered run, and exits nonzero on any failure. It excludes `ProjectSkeletonTests`, which
needs the app and test resource bundles. It is a Core behavior check; the xcodebuild run above is the
authoritative one.

## Implemented and tested areas

| Source/test area | Behaviors |
|---|---|
| Models, RawJSON, PlanImport / ImportTests | Codable models; extraction, strict decoding, normalization and validation; manifest codes/paths/warning multisets; expected normalized fields; limits and malformed input; identity and round trips |
| Steps, RestResolution / StepsAndEngineTests | All valid fixture step/rest expectations; groups, mismatched rounds, drops, block transitions, same-block wraps; 2,500-step flattening well inside budget |
| SessionEngine / StepsAndEngineTests | Logging/editing/skipping/jumping/finishing; Date-based rest; transitions; fixed/open work timers; notifications as effects; missed-beep reconciliation; persisted timer state and edited weight |
| Prefill / PrefillAndStatsTests | History filtering by name, unit and completion; current-session precedence; missing sets/weights; dynamic reps; drops; bodyweight; last-time formatting and suggestions |
| Stats, ProgressionAdvice / PrefillAndStatsTests | Volume, best set, block/set durations, advice thresholds and messages, editing advice, history series |
| PlanLibrary, PlanSchedule / LibraryCalendarPromptTests | Conflicts, activation, replacement, deletion, cycles, weekday lookup, switch-day coordination, completion/discard, history edits |
| CalendarProjection, Sparkline / LibraryCalendarPromptTests | Local calendar boundaries, projection horizon, rest cycles, completed days, seven-day metrics, unit filtering, captions, metric cycling |
| Prompts / LibraryCalendarPromptTests | 3,510-character prompt, unchanged JSON example data, fix-it errors, marker rejection, large valid input, truncated input, exact/over byte-limit handling |
| **Settings, delete-all, export, spoken card / SettingsPolishTests** | **Every remaining setting persisting independently; a silenced app playing nothing while still scheduling notifications; delete-all cancelling alerts, emptying the store and leaving it usable; the backup document; the notification-state row; the spoken step card for every target kind and unit** |
| HistoryGrouping, ExerciseText / HistoryTests | **Month grouping newest first with running sessions excluded and local-calendar boundaries; editing a past session persisting and feeding the next prefill; deleting one file and leaving the rest; best-set text with its weightless and timed fallbacks; per-exercise series by normalized name and unit |
| InputRules, StepCard, Alerts, SessionRunner / WorkoutTests | **Weight separators and rounding, rejected input, reps/seconds limits, steppers never below zero; step-card lines for every target kind; Date-based rest with rescheduled notifications; fixed and open timers with warning/end/minimum alerts and no replayed beeps; finish, discard, day switching, resume, and the finished session held for the Summary |
| AppModel, HomeCard / SettingsAndHomeTests | Locale unit defaults, weight steps, zero default rest, units changes leaving plans untouched, first-launch settings write, sample-plan import, start-card wording per schedule, repeat-block chips, import error rows and fix-it prompt, preview warnings and counts, conflict choices, plan list actions, corrupt-file alert, metric cycling |
| Store, StoreFiles / StoreTests | Atomic writes; corrupt and unknown-version files set aside and reported; per-event active-session persistence; complete/discard; ISO-8601 fractional dates; sorted-key stability; 1,000-session load; export document; delete-all; serialized concurrent writes |

Decisions and conflicting older test text are recorded in `DECISIONS_LOG.md`. Copy/paste research and
the limits of what was tested are in `COPY_PASTE_NOTES.md`.

## Reproduce

Authoritative iOS run:

```sh
xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'
```

Portable Core checks, which need only the Command Line Tools:

```sh
python3 tools/check_core.py
python3 tools/reference_import.py
```

The manual cases are collected as a ready-to-run checklist in `DEVICE_CHECKLIST.md`.

## Remaining manual checks

K16 (kill the app mid-workout and relaunch) and K17 (reinstall from Xcode over the existing app) are
marked `manual` in `TEST_CASES.md` and need the resume banner from M5/M6 before they can be exercised.
