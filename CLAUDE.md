# Jimm's Bro+ — implementation handoff

This file is the entry point for whichever coding agent builds the app: ChatGPT / Codex reads `AGENTS.md`, Claude Code reads `CLAUDE.md`. Both files are identical; if you edit one, copy it over the other.

You are implementing a native iOS workout-tracking app from a finished design.
The owner has already made the product decisions. Your job is to build exactly
what the docs describe, with tests, in the milestone order given.

## Read these first, in this order

1. `docs/SPEC.md` — what the app is, decisions already made, screens, behaviors, data model, persistence
2. `docs/PLAN_FORMAT.md` — the JSON plan format: fields, leniency rules, validation, error/warning codes
3. `docs/PROMPT.md` — the exact chatbot prompt text the app copies to the clipboard
4. `docs/TEST_CASES.md` — the test list. Every case marked `unit` must have a passing automated test
5. `docs/BUILD_PLAN.md` — milestones. Do them in order; each ends with green tests
6. `examples/` — fixture files and `manifest.json` (expected outcomes). Drive the import tests from these files
7. `tools/reference_import.py` — a Python reference implementation of the import pipeline, step flattening, and rest resolution. It passes the whole manifest (`python3 tools/reference_import.py`). Port its behavior to Swift; when a Swift test disagrees with the manifest, run the Python on the same file to see the intended result
8. `tools/generate_fixtures.py` — regenerates every file in `examples/` from scratch. If `examples/` is missing (for example you received only the bundle file), run it first

## v1.1 and v1.2 — the refinement releases

`docs/ITERATION_2_PLAN.md` is the v1.1 plan (milestones **R0–R6**) and
`docs/ITERATION_3_PLAN.md` is the v1.2 plan (milestones **V0–V8**), in order, with the SPEC
amendments landing before the code that depends on them. Everything through V7 is built and
green (and v1.3 on top of it, below); what remains is the device checklist, which needs the owner's iPhone
(`docs/DEVICE_CHECKLIST.md`). `docs/BUILD_STATUS.md` says what is done and what was actually run,
and `docs/CODE_HEALTH_REVIEW.md` records the review that prompted half of v1.2.

Read `docs/SPEC.md` as the contract, not the plan: where they disagree, SPEC wins, and the plans'
proposed test-case ids were renumbered on landing (TEST_CASES notes the mapping).

`docs/ITERATION_4_PLAN.md` is the v1.3 plan (milestones **X0–X6**): a narrower Dynamic Island
(D41), changing an exercise mid-workout (D42), JSON edits at every size (D43), history as CSV in
and out (D45), and **Progression** — the chatbot round-trip run the other way (D44,
`docs/PROGRESSION_FORMAT.md`, `docs/PROMPT.md` §3). Everything through X6 is built and green;
the v1.3 device rows (W3, W12, W21, W30, W40) join the checklist that still needs the phone.

`docs/ITERATION_5_PLAN.md` is the v1.4 plan (milestones **Y0–Y5**), the owner's notes after
running v1.3 on the phone: a tap's result before its side effects (D48 — the workout cover no
longer waits for the notification, the Live Activity and the disk write), four **built-in
plans** through the ordinary import pipeline with no weights in them (D46,
`Core/BuiltInPlans.swift`, `JimmsBro/Resources/*.json`), an **introduction** whose pages are
Core data pinned to real control names (D47, `Core/Introduction.swift`, `Settings.introSeen`),
and store readiness (D49: an opaque icon, version 1.4 on every target, the export-compliance
answer, `docs/PRIVACY.md`, `docs/APP_STORE.md`, `tools/check_release.py`, and a Release build
as part of every milestone's green). Everything through Y5 is built and green. What remains is
the owner's: the device checklist, the Developer Program, a release Xcode, the LICENSE and the
submission (`docs/APP_STORE.md` §1 and §6).

`docs/ITERATION_6_PLAN.md` is the v1.5 plan (milestones **Z0–Z6**), the owner's notes after
living with the app, with four readings put to the owner and chosen: a clearer Progression row
and Copy prompt with the mechanism explained once (D50, `PromptText`), an **effort target** in
the plan format — `inReserve`, reps or seconds short of failure (D51, `SetTarget.inReserve`,
four fixtures) — **a plan in several pastes** for free chatbot tiers: the outline first, then one
day per paste, through the ordinary importer (D52, `Core/PlanDraft.swift`, `draft.json`,
PROMPT.md §4–5), **progression as steps you earn** by performance with the calendar kept as a
mode (D53, `ProgressionSteps`, `Progression.mode`), and **a goal per exercise** (D54 —
removed in v1.7's review, D68). Everything through Z6 is built and green; the v1.5 device
rows (Z4, Z10, Z17, Z25, Z31) join the checklist. The reading of "a history for each exercise"
as typed current numbers is parked by the owner's decision (the plan's last section).

`docs/ITERATION_7_PLAN.md` is the v1.6 plan (milestones **U0–U7**), built from the 2026-09-09
usability audit (`docs/UX_REVIEW_2026-09-09.md`) and judged for three users — a coach, a
great-grandparent and a five-year-old: **nothing untrue** (D55 — a missed workout only when the
plan expected one, "Nothing logged" before "First time", calendar labels unique within the plan,
a chip that never contradicts the fields, the right sentence for a plan pasted in words),
**nothing unreachable** (D56 — every menu confirmation an alert with a way out, Done in the strip
instead of over Log set, no phantom bar, a placeholder in the empty weight, large text that keeps
the inputs on screen), **the first five minutes** (D57 — no warm-up on a fresh install, **Start
first set** during a warm-up, the notification permission at the first Log set,
`InputDefaults.weightHint`, the unit asked on the review when the plan named none, a **Start
here** badge, Home that headlines the workout on a rest day, "Next: …" on the Summary) and
**hierarchy** (D59 — Start in the bottom slot, headers in ink, `WrapLayout`, Undo on the row, an
idle strip that says what follows, labelled History rows, Settings presets). U4 — **plain words**
(D58) — was written as two readings and the owner chose **Reading B**: the app speaks in words
("Aim 4–6 reps · 100 kg", "Last time 10 × 100 kg", "paired with …", "lighter set 1 of 2") and
**Settings → Compact notation** restores v1.5's forms; `Wording` is chosen once from
`Settings.compactNotation` and threaded from `WorkoutScreen.model(settings:)`, and the chatbot
prompt and the progression ladder keep the compact forms whatever the switch says. U7 — **an
activity that outlived the app** (D60) — is the one defect the owner hit on the phone rather than
in the audit: a Live Activity survives the process that started it, so `SystemActivityPresenter`
keeps no handle and asks `Activity.activities` instead, and every launch reconciles the Lock
Screen (`refreshActivity(force:)`). U0–U7 are built and green on `v1.6-refinement` (pull request
#2). The v1.6 device rows join the checklist.

`docs/ITERATION_8_PLAN.md` is the v1.7 plan (milestones **T0–T6**), written 2026-09-13 from the
owner's note after living with v1.6 — *"sensory overload… less choices… more forcing… feels like a
settings menu"*. Home became **Today**, one card with the same five zones every day and its
alternatives in one ··· (D61); the tab bar shrank (D62 — the owner chose **Reading A: Today · History**
on 2026-09-13); the calendar and the week's line moved to History (D63); controls
became **earned** by a table in SPEC (D64, `Core/Gates.swift`); and each day took a **colour** in
four places (D65, `Core/DayColour.swift`, chosen go the same day). Nothing in it touched
`Core/Persistence.swift`, the pipeline, the format, the prompts or the Workout screen. The Today
mock is the "Jimm's Bro+ Today" artifact linked from the plan. T0–T6 are built and green on
`v1.7-today`, off `main`, which holds v1.6 since pull request #2 merged: Today is one card (`HomeStart.message`
and `.alternatives` are Core data, `TodayTests` T1–T4), and the empty card offers **Choose a
plan**. The tab bar is **Today · History** (`AppTab`, `Core/Tabs.swift`, pinned to SPEC §4.0 by
T7): Plans is pushed from Today's ··· → Change plan, and Settings from a gear at the top-left of
both tabs (`settingsGear`). The calendar and the week's line open History
(`Features/History/CalendarView.swift`); the tapped-day line is Core's (`CalendarText.line`) and
has no Start this, because a workout starts on Today. Controls are earned (T4): `Core/Gates.swift`
has one function per row of SPEC §6.40's table, pinned by T21, and the views ask it — Month waits
for a workout older than this week, and Metrics and Find an exercise
for the first workout. Each day has a colour (T5): `Core/DayColour.swift` gives a day its colour by
its place in the plan's day list, derived and never stored, and `DaySquare.swift` draws it in
SPEC §6.41's four places — Today, the calendar, History's rows, and the workout header with the
Lock Screen — and nowhere else. T6 made the documents say so: version 1.7 on every target,
Today and History's month as the README's screenshots, SPEC's remaining Homes made Today, and the
v1.7 device rows (T5, T9, T13, T24) in the checklist that still needs the phone. Before the push the
owner reviewed T0–T6 (SPEC §6.42; T7 in TEST_CASES): History lost its search field — **Find an
exercise** is the way (D66); the **Progression** row moved from Plan detail into History's block
with Metrics and Find an exercise, for the active plan, and Today's **Plan the next one** opens it
(D67); and **goals are removed** (D68) — `goals.json` is no longer read or written, a file left on
the phone stays unread, and a backup that carries goals still restores. Its device row is T29.

`docs/ITERATION_9_PLAN.md` is the v1.8 plan (milestones **S0–S4**), written 2026-09-13 from the
owner's note after looking at v1.7's Today — *"too much text, and too little use of visual
cues… I want the visual cues to be a sort of guide for the user"*. The rule is **no words without
a cue** (D69, S1): every line of words on Today sits beside a mark that says the same thing
without words, or it leaves the card. The week becomes a seven-square strip that replaces
**Another day** (D70, S2), and a rest day says rest instead of naming the next workout (D71, S3).
Nothing in it touches `Core/Persistence.swift`, the pipeline, the format, the prompts, the
Workout screen, the rest, the Live Activity, History, or the empty card. The mock is the "Today,
Simpler" artifact linked from the plan. S0–S4 are built and green, on `v1.8-cues` off `main`: a day's
card has no sentence (`HomeStart` has no `subtitle`, TS1) — a clock and the minutes, the
exercises with their sets as blocks (`HomeStart.rows`, `PreviewRow`), the step as the ···'s last
line (`stepLine`), **▶ Start Today's Push** (`HomeStart.startTitle`, D70's words), and a lighter
gear and ··· (`QuietGlyph`); and the week is a strip (S2, D70, SPEC §6.44): seven squares at the
left of the meta row from the calendar's own projection (`Core/WeekStrip.swift`,
`CalendarProjection.next(days:from:)`), a tap shows that day (`HomeStart.current(showing:)`, the
view's `shownOffset`, never stored) with a button that says when, a tapped grey square shows
D71's rest card early, and **Another day** left the ··· with its chooser and `Gates.anotherDay`
(§6.40's table records the strip as the one ungated control). S3 is built too: a rest day says
rest (D71, SPEC §6.45) — **Rest** after a grey square, the moon where the clock was, the
system's z's in the accent where the rows were, and a disabled **No exercise Today** — which
reverses D57 on Today, because the next workout is one tap away on the strip; after the day's
workout, on every plan, the same card says **✓ Done Today** (the owner's reading), and a missed workout still
speaks. S4 made the documents say so: version **1.8** on the app, the extension and the tests,
`docs/DEVICE_CHECKLIST.md`'s **v1.8 rows** (TS5, TS11, TS12, TS16), `today.png` retaken for the
README with the strip and the set blocks, and the bundle regenerated. Everything through S4 is
built and green. What remains is the owner's: the device checklist (the v1.7 and v1.8 rows both
need the phone), the Developer Program, a release Xcode and the submission
(`docs/APP_STORE.md` §1 and §6).

`docs/ITERATION_10_PLAN.md` is the v1.9 plan (milestones **Q0–Q7**), written 2026-09-14 from the
owner's notes after living with v1.8's strip: **a day swapped, not a plan changed** (D72 — an
off-day workout writes two dates to `swaps.json`, a new file beside `plans.json`, and leaves the
plan's cycle, position and anchor alone; the day whose workout was taken carries a question on the
strip: Rest, today's day, keep, or **Slide**, which is D37's re-anchor chosen on purpose and offered
on rotations only, D73), **the marks on Today** (D74 — a dot in the pattern's colour under a
swapped square, a yellow ring for a question, a long press for "was Push", the question block with
words beneath its squares and a button that follows the choice), **a ··· of two items** with squares
for symbols and no progression in it (D75 — History's Progression row is the way), **Change a day's
exercises** from this plan, another plan (outlined in its colour) or a day written just for that
date (D76), **the JSON sheet redone** at every fragment point — named, pre-filled, the error at the
line, a Save that says its effect (D77) — and **Plans that speak in squares** (D78 — a circle to
mark and a button to confirm, the page with the cycle as squares and every day closed until
tapped). The requirements were settled in two rounds on the "Swapping Days" artifact linked from
the plan. Q0–Q7 are built and green on `v1.9-swaps` — Q1 the swap in Core, Q2 its marks on
Today, Q3 the ··· in squares with progression left to History, Q4 a day's exercises changed for one
date — a day of this plan, a day borrowed from another plan (outlined in its colour) or a day
written just for the date (outlined in ink), `Core/ChangeDay.swift` and `ChangeDayView` — Q5
the JSON sheet redone at its five points: named, pre-filled with an example that saves as it
stands, the error marked at its line or nowhere (`Core/JSONPoint.swift`, `Core/JSONLocator.swift`),
and a Save that says its effect — and Q6 Plans in squares: on the list a chevron at the left, the
cycle's symbol, how often, and a circle that marks while **Use *name*** confirms (now the one way
to change plan), and on the plan's page the cycle as squares, then as rows each closed until
tapped (`Core/PlanPage.swift`). v1.9 touches the on-disk contract once: `swaps.json` beside
`plans.json` (absent means no swaps) and an optional `swaps` in a backup, frozen in
`examples/store/v1/` with a backup that carries swaps and one that does not. Q7 made the documents
say so: version **1.9** on the app, the extension and the tests, `docs/DEVICE_CHECKLIST.md`'s
**v1.9 rows** (TQ18–TQ20, TQ24, TQ29, TQ33, TQ38, TQ39), D72–D78 in `docs/DECISIONS_LOG.md` with
the D37 amendment and the D50 reversal on Today named, and the bundle regenerated; no screenshot
changed. Everything through Q7 is built and green. What remains is the owner's: the device
checklist (the v1.7, v1.8 and v1.9 rows all need the phone), the Developer Program, a release Xcode
and the submission (`docs/APP_STORE.md` §1 and §6).

`docs/ITERATION_11_PLAN.md` is the v1.10 plan (milestones **P0–P7**), written 2026-09-16 from the
owner's notes after living with v1.9: the Workout screen in **symbols**, and colour that means
**state** — done in the day's colour, now in blue (reserved on that screen for the current set),
not yet in grey (D79); the header without words, its bar one segment per exercise with a tick per
set, tapped to open the Overview (D80); the exercise as a name with a **?** for its notes, a row of
**dots** for its sets, and one **card of cells** for the set you are on — solid to the minimum,
translucent to the top of the range, a caret under the reps, a line where last time reached — with
a logged set changed in place by **Save** (D81); the walk between exercises as a **count-up and a
ring** that fills red → amber → green over the plan's minimum, `restBetweenExercises`, the one
field this release adds to the plan format and the on-disk contract, optional, the setting as the
fallback (D82); **pages** — swipe to the next or previous exercise while the bar's fill stays put
and its caret moves (D83); a bar whose segments take **your median time** per exercise once it has
been done three times, held between ½× and 2× (D84); **Change *day*** as joined squares with a
button that confirms and names its effect, and today's exercises editable through the JSON sheet
pre-filled with the day (D85); and cycles drawn **seven to a row, the squares touching** (D86).
The requirements were settled on two artifacts linked from the plan: round 1, "Workout in Symbols",
and round 2, "Symbols, Round Two", redrawn four times on the owner's corrections. P0–P7 are built
and green on `v1.10-symbols`: P1 gave every mark on the Workout screen a state — `MarkState`
(`Core/WorkoutMarks.swift`, compiled into the extension too, its colour in `DaySquare.swift`) and
`MarkState.of(step:session:)` — so done is the day's colour, now is blue and not yet grey, with the
screen tinted ink and Log set ink; and made the header the bar — `WorkoutBar` (`Core/WorkoutBar.swift`),
a segment per block and a mark per set in one `Canvas`, a caret, the elapsed time, a tap that opens
the Overview, and the stage spoken, not printed (`spokenHeader`). The Lock Screen's bar fills in the
day's colour. P2 put the exercise in symbols (D81, SPEC §6.54): zone 2 is the name with its state's
dot, a **?** only when there are notes or a change behind it (`WorkoutScreen.notes`), a dot per step
of the block (`SetDot`), and one card of cells (`SetCard`, `Core/RepCells.swift` — solid to the
minimum, faint to the top, yellow past it, a caret that follows the field through
`SetCard.showing(field:)`, a line over last time); a filled dot changes its set in place with
**Save** (`editing`, the view's, never stored), a grey dot does its set now, and Undo is the strip's
again during the rest. `StepCard.setRows` stays in Core for its tests; no screen draws a row.
P3 made the walk a count-up and a ring (D82, SPEC §6.55): between exercises the strip is a ring that
fills red → amber → green over the minimum and becomes a green check, the count-up beside it and the
next exercise's name under it, no −30 / +30 / Skip (the engine refuses them on the walk), and a tap
on the ring for one sentence (`RestText.ringExplanation`); `StatusStrip.direction`, `.ring`
(`WalkRing`) and `.spoken` carry it, and the Lock Screen counts the walk up. The minimum is the
plan's new optional `restBetweenExercises` (PLAN_FORMAT §2, PROMPT §1 and §4, three fixtures, decoded
with `container.optional`), then the setting — read from the plan by `PlanLibrary.refreshWalk()`,
never copied into the session. P4 made zone 2 a pager (D83, SPEC §6.56): a page per block in the
bar's order, one block per swipe, the next peeking 12 pt, the caret moving while the fill stays; a
page's place is what is left in its block (`PagePlace`) — behind has a check and its last set at
70 % with **↩ Back to …**, ahead is grey with **▶ Do this now** (`jumpTo`) — and neither has inputs
(`showsInputs`). Every page is Core's (`ExercisePage`, `WorkoutScreen.page`), the page on screen is
the view's `showing`, never stored, and the ··· still acts on the step that is on. P5 made the bar
learn your pace (D84, SPEC §6.57): a segment is as long as its block usually takes you — the median
of its past times from the third, the walk after it counted in, read from `startedAt` and `loggedAt`
with nothing new stored — before that the day's time per set × its sets, by set count with no pace
at all, and held between ½× and 2× the day's median stretch (`Core/Pace.swift`,
`Pace.weights(day:history:)`, passed to `WorkoutBar.of(…, weights:)`); the Lock Screen's bar is
unchanged. P6 made Change *day* squares with a button (D85, SPEC §6.58): the ··· item and the
picker read **Change Push** after the day the date is now (`DayChoices.title(dayName:)`), this
plan's days are a joined strip of tiles, every other plan's an outlined strip, **Custom** a dashed
tile, and the date's exercises a card that opens the JSON sheet pre-filled with the day; a tap marks
and the button — *Push → Pull*, *Write a day for Wednesday* — confirms (`ChangeDayText.confirm`),
reversing D48 on that screen. And squares join (D86, §6.59): a cycle wraps at seven and its squares
touch (`CycleGlyph.rows`, `.ends`), drawn by one `CycleStrip` in `DaySquare.swift` that the Plans
list's symbol, the plan's page — today's square outlined — and the picker share. P7 made the
documents say so: SPEC §4.5's five zones rewritten once as the page now is, `docs/DEVICE_CHECKLIST.md`'s
**v1.10 rows** (TP7, TP16, TP23, TP29, TP35, TP42), D79–D86 in `docs/DECISIONS_LOG.md` with D48's one
tap reversed on the picker, D59's Undo moved back to the strip and the Workout screen named as §4.0's
one exception, `docs/screenshots/workout.png` retaken for the README, version **1.10** on the app, the
extension and the tests, and the bundle regenerated. Everything through P7 is built and green. What
remains is the owner's: the device checklist (the v1.7 to v1.10 rows all need the phone), the Developer
Program, a release Xcode and the submission (`docs/APP_STORE.md` §1 and §6).

`docs/ITERATION_12_PLAN.md` is the v1.11 plan (milestones **N0–N7**), written 2026-09-16 from
the owner's note that the JSON screens *"feel like an instruction manual"*: every point where the
app hands text to a chatbot and takes its reply back becomes one screen in three states — **Ask**,
**Paste**, **Review** — under one rule, *show the result, not the format* (D87), with the trip as
three joined squares (D89), **Send the prompt** through the share sheet and **Copy the prompt**
beneath it (D88, the owner's J1), the built-in plans as a row of squares (D90), day by day offered
only when a reply comes cut short (D91), Progression's choices as pre-marked tiles and its review as
ladders (D92), today's exercises edited in place — §6.58's parked editor, unparked (D93) — a change
**said in words** and reviewed as a diff (D94, `PROMPT.md` §7), and the text behind the ··· at every
point as **Edit the text** with D77 kept (D95). The requirements were settled on the "The Round Trip"
artifact linked from the plan, J1–J7 chosen 2026-09-16. Nothing in it touches the on-disk contract, the pipeline, the formats,
the fixtures, the Workout screen or History. The plan was cut for a parallel build and built that way:
**N0–N1 the trunk**, **N2–N5 four independent tracks** with a file-ownership table, built in separate
worktrees at the same time, **N6 the merge** and N7 the documents. N0–N7 are built and green on
`v1.11-round-trip`. N1 laid the seam: SPEC §6.60–§6.68 and D87–D95, `Core/Trip.swift` (`TripStage`,
`TripStrip`, `TripButtons`), `TripStripView` and `RefusedBand` in `DaySquare.swift`, `PromptButtons` in
`Features/Shared` (which presents `UIActivityViewController` itself, so *sent* fires when the sheet
closes — shared or cancelled alike), `ExerciseEditSheet` with a value form over Core's
`PlanEdit.ExerciseFields`, the change prompt (`PROMPT.md` §7, `Prompts.change`, its marker known to the
importer), the mechanism sentence on the introduction's first page, every file the tracks fill registered
while empty, and a reserved TN block per track. The four tracks then landed a screen each: **N2** Add plan
as the trip (`Core/ImportTrip.swift`, `Core/DraftTrip.swift`) — Ask with Send / Copy and the built-ins as
four tiles, Paste, the plan's page as the review with **Use *name***, and a Refused that offers **Ask for
the whole plan** and, on a reply cut short alone, **Get it day by day**; **N3** Progression as two rows of
pre-marked tiles, no history switch, ladders on the review and **Start step 1** (`Core/ProgressionScreen.swift`,
`Core/ProgressionLadder.swift`); **N4** today's exercises edited in place (`Core/DayEdit.swift`,
`Core/ExerciseNames.swift`, `DayEditorView`) — reorder, delete, a row to the exercise sheet, **Add exercise**
over the names the app knows; and **N5** **Say what should change** (`Core/ChangeRequest.swift`,
`Core/PlanDiff.swift`, `ChangePlanView`), one sentence out, a whole plan back, a diff reviewed as
*2 changes* and **Apply** as an edit that keeps the progression. N6 merged them in order and took the
dead code out (`DraftPlanView`, `PromptText.copyStep` and `.mechanism`, `BuiltInPlans.buildYourOwn`,
`AddPlanRequest.builtIns`), with the owner's two readings — days matched **by name only**, and **Send the
prompt again** returning every screen to Ask — and `JSONPoint`'s real `.plan` and `.progression` kinds in
place of the tracks' stand-ins. N7 made the documents say so: SPEC checked against what shipped (§6.63 gains
D57's **Start here** on the built-ins row, §6.65 the calendar's **Start week 1**), TN1–TN38 landing where the
plan proposed them with TN39 added for VoiceOver on the strip, `docs/DEVICE_CHECKLIST.md`'s **v1.11 rows**
(TN15, TN16, TN22, TN31, TN39), the N7 lines in `docs/DECISIONS_LOG.md`, `docs/PRIVACY.md`'s chatbot bullet
rewritten for the share sheet, `docs/screenshots/add-plan.png` in the README, version **1.11** on the app, the
extension and the tests, and the bundle regenerated. What remains is the owner's: the device checklist (the
v1.7 to v1.11 rows all need the phone), the Developer Program, a release Xcode and the submission
(`docs/APP_STORE.md` §1 and §6).

`docs/ITERATION_13_PLAN.md` is the v1.12 plan (milestones **L0–L8**), written 2026-09-17 from the
owner's note after a review of the whole codebase — *"I want logic to be reused wherever possible, I
don't want logic duplicates anywhere"*. The rule is **one owner for each piece of logic** (D96): every
rule, parser, formatter, lookup and piece of text lives once, Core owns it unless it draws, and where
two copies disagreed SPEC decides, else the stricter rule, logged. `tools/reference_import.py` stays as
the sanctioned copy (the owner's choice: it is the fixtures' independent oracle). Nothing changes on
disk. L1 one parser per value, L2 one JSON grammar, L3 plans and the schedule, L4 the session and the
Workout screen, L5 the chatbot screens, L6 the other views, L7 tools and the tests' support, L8 the
documents. Dead code, misnamed files and long functions the review found are parked at the plan's end,
with two bugs first in line. L0–L1 are built and green on `v1.12-one-of-each`: L1 made
`TargetGrammar` (`Core/PlanImport.swift`) the one reader of reps, a hold and a weight — for the
importer, a progression step and the exercise sheet — with `PlanJSON.string` the one JSON escaper,
`TargetText.number` the one number, `RawJSON.jsonText` the one encoder, `Issue.isPlanInWords` the one
reading of a plan in words and `ProgressionScreen.defaultMode` the one default mode (TL1–TL5,
`JimmsBroTests/OneOwnerTests.swift`). Before L2 came **F**, fix-first, from a
2026-09-24 audit of the screens against each other (F1–F4 in `docs/DECISIONS_LOG.md`, TF1–TF5,
`JimmsBroTests/ScreenAuditTests.swift`), built and green on `fix-first`: **Edit the text** keeps the
progression, as Apply does (F1 — `PlanLibrary.replace` goes through `ChangeRequest.applied`); Skip
exercise, a swipe-delete on Plan detail and the day editor's Back ask first (F2); a sheet or the day
editor holding edits ignores the swipe and asks before discarding them (F3, `View.discardGuard` in
`RootView.swift`); and a set standing alone reads reps first — *"10 × 60 kg"* — everywhere (F4,
`StepCard.setText`). L2 is built and green on `v1.12-one-of-each`, fast-forwarded to F first:
`JSONGrammar` (`Core/JSONGrammar.swift`) is the one JSON parser — the importer's check before
Foundation decodes a paste, the offsets `JSONLocator` walks to mark a line, and the extraction's cut
(`JSONGrammar.valueEnd`) — in place of `StrictJSON`, `LocatorParser` and `PlanImport.valueEnd`; a
refusal carries its place (`JSONGrammar.Failure`), and the cut reads code points, as the grammar and
the oracle do (TL6–TL8). L3 is built and green on the same branch: a plan hands on its identity one way,
`Plan.carried(into:as:)` — `.edit` for every edit, Apply and Edit the text, `.newPlan` for a name-conflict
Replace, the anchor always going with its place — and one of each for the schedule: `Plan.dayIndex(named:)`,
`Weekday(_:calendar:)` with `WeekdayText` and `MonthText` (English whatever the phone's language),
`finished(on:…)` over sessions, `PlanSchedule.firstDay` through today and 62 days, `CycleSquare.of` with
`Plan.cycleDays` and `cycleNames` for a cycle as squares and words, and `ExerciseNames.known` as the one
exercise search (TL9–TL13). L4 is built and green on the same branch: the session and the Workout
screen say each thing once — the rest after a set is `RestResolution.betweenSets`, which the idle line
and a built-in day's estimate now ask; a step said away from its card is `StepCard.stepLine`, for the
strip's "Next: …", the rest's notification (which now carries the target and weight) and the Lock
Screen; the step that is on is `ActiveSession.currentStep` and the walk `ActiveSession.walk`, one reading
of its two stages; Skip exercise starts the walk through `advance`, as a skipped last set does; the counts
are `SessionBlocks.place` and `SessionStats`; last time is `Prefill.lastResult` over one scan; the limits
are `TargetGrammar.isWeight` and `.cleanName`; a step is a `SessionStep` and its target a `StepTarget`;
`ActiveSession` and `RestState` decode in Persistence.swift; and the Overview and Session detail draw
`SessionBlocks.blocks` (TL14–TL21). L5 is built and green on the same branch: the chatbot screens say
each thing once — a refused reply is one `TripRefusal` (`Core/TripRefusal.swift`, beside `Trip.swift`
because the extension compiles that one) with the fix a `TripFix`, `.chat` or `.paste`, and each screen's
way back its one argument, and a refusal that names no error is fixed at Chat (SPEC §6.60); the ··· is
`TripMenuItem`, drawn by one `TripMenu`; each screen type chooses its prompt and subject, so
`AppModel.progressionPrompt`, `outlinePrompt` and `dayPrompt` are gone; every text sheet is built in
`JSONPoint`, and Plan detail's Edit the text is a `.plan` fragment target saved as
`PlanEdit.Operation.replacePlanJSON`, the unit kept by `ImportResult.planKeepingUnits(of:)` (so
`ImportView(replacingPlanId:)` and `AppModel.replacePlan` are gone); a draft's day is tried once
(`PlanDrafting.preview`, held by `DraftTrip` from `pasted(_:settings:)`); and the refusal with its Details,
Worth knowing, the tidying and Paste are drawn once in `Features/Shared/TripParts.swift` (TL22–TL27).
L6–L8 are not built.

Three v1.2 rules are worth knowing before touching anything:

- **`Core/Persistence.swift` is the on-disk contract.** Identity is required; anything with a
  default is optional. Adding a field to `Settings`, `Plan` or `Session` means adding it to that
  file's decoder too, or every file already on the phone becomes "corrupt" and is moved aside.
  `examples/store/v1/` freezes a real file of each type; never regenerate one to make a test pass.
- **The app has one rest with three kinds** (`RestKind`): the warm-up, the rest between sets, and
  the walk between exercises. They share the countdown, the controls and the notification.
- **Every weight the app *offers* is snapped to a loadable increment** (`WeightRounding`);
  weights the user types are never touched.

## Hard rules

- Platform: SwiftUI, iOS 17.0+, Swift 5.9+, iPhone only, portrait only. No third-party dependencies. No backend. No accounts. Two targets since v1.2: the app, and `JimmsBroActivity`, the widget extension that draws the Lock Screen / Dynamic Island activity (`tools/add_activity_target.py` is how it got into the project).
- Xcode product name: `JimmsBro` (bundle id like `com.<owner>.jimmsbro`). Create the project inside this folder.
- Persistence: Codable JSON files in Application Support (SPEC §8). Not SwiftData. Not Core Data. Not UserDefaults for anything except trivial flags.
- All logic (import pipeline, step flattening, rest resolution, session state machine, prefill, stats, export) lives in plain Swift types under a `Core/` group with no `import SwiftUI`/`UIKit`, and is covered by unit tests.
- The rest timer is Date-based (`endsAt: Date`), never a decrementing counter (SPEC §6.4).
- Never crash on bad input. Bad paste → error with a path and a code. Corrupt file on disk → moved aside, app continues (SPEC §8.3).
- Do not build anything in SPEC §10 "Later" unless the owner asks.
- Where the docs are silent, pick the simplest behavior and record it in `docs/DECISIONS_LOG.md` (create it) with one line per decision.

## Working style

- Finish each milestone with its tests green before starting the next. Run the tests; do not declare a milestone done without running them. There are three routes and they check different things: `xcodebuild test` (the app, on a simulator), `swift test` (Core on the host — where the doc-pinning tests actually run), and `python3 tools/check_core.py` (Core with no Xcode at all). From v1.4 a milestone is also a Release build (`xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'`) and `python3 tools/check_release.py` (SPEC §6.25). CI runs the three routes and `tools/check_bundle.py` on every push, so a milestone that edits a bundled document regenerates the bundle in the same commit (`python3 tools/build_bundle.py`); v1.6's U1–U3 were red on that job until U5 did.
- Work on a branch, commit per milestone with the tests green, and write commit messages that say *why*. Never add an AI as a co-author — no `Co-Authored-By` trailer of any kind, whatever a harness suggests; the history was rewritten once (2026-09-08) to remove them.
- The repository is public under the MIT license (`LICENSE`), with a landing page at the top of `README.md` and CI in `.github/workflows/ci.yml` running the three routes on every push. Keep the README's landing section for people and its lower half for you; keep `docs/screenshots/` to what the README shows.
- Keep views thin. Views call into an `AppModel`/store; they do not parse, validate, or compute.
- Use the fixtures in `examples/` verbatim in tests. Do not edit fixtures to make tests pass; if a fixture looks wrong, say so.
- Use the iOS Simulator for visual checks. The owner installs on the physical iPhone (BUILD_PLAN §Device).
- If you cannot run Xcode where you are (for example a chat session without a Mac), still write the complete project files, and give the owner exact commands to run the tests locally (`xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'` — any installed iPhone works). Never claim tests passed that you did not run.
