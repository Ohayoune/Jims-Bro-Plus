# Iteration 2 — the refinement release (v1.1)

Written 2026-09-05 from SPEC v1, the current code (M0–M7, 97 tests green), `docs/UX_REVIEW.md`, and a second
independent review that drove the app in the simulator. This is a proposal. Nothing in it is accepted until
SPEC §1 and the relevant sections are amended; the docs stay the contract for whichever agent builds it.

## 0. One paragraph

v1.1 adds almost no capability. It makes the five things you do every session effortless: start the
intended workout, log a normal set in one tap, fix the last set while the rest runs, see what is left,
and minimize and come back without losing your place. It also stops the app from ever looking like it
did something it did not. Visual polish comes last and is applied to a layout that has stopped moving.

## 1. Principles for this release

Each principle is a rule the implementing agent can check, not a mood.

| # | Principle | Rule for this app | Source |
|---|---|---|---|
| P1 | One layout per task | Logging, resting and timed work share one screen with fixed zones. The primary button never changes position. | HIG consistency; NN/g heuristic 4 |
| P2 | Never hide what the task needs | Exercises (overview), undo, skip and finish are reachable in every workout state, including rest. | NN/g on minimalism: remove decoration, not task content |
| P3 | Undo beats confirmation for frequent reversible actions; concise confirmation for irreversible ones | Log set gets Undo. Deletes confirm, consistently, everywhere. No dialog on the happy path. | NN/g heuristic 3 (user control and freedom); HIG |
| P4 | Never report success that did not happen | A Save that changes nothing is a bug. A failed write shows Retry and keeps the data. | NN/g heuristics 1 and 9 |
| P5 | Label what the value does not explain | `10` and `80` get "Reps" and "kg" labels. A volume number is labelled Volume. Units alone are not labels. | Recognition over recall |
| P6 | Reachable and accessible by default | Primary action bottom-anchored above the keyboard; keyboard has Done; every target ≥ 44 pt; Dynamic Type reflows rather than shrinking numbers. | Apple design tips; HIG Dynamic Type |
| P7 | Docs first, Core first, green per milestone | Amend SPEC and TEST_CASES before code. Core logic tested before any view. No milestone is done without running the tests. | CLAUDE.md, unchanged |
| P8 | Judge by tasks, not taste | §6 lists the acceptance tasks. A milestone passes when the tasks pass on the phone. | Usability testing practice |

Where SPEC v1 §4.0 conflicts with P2 or P5 (the "no labels" and "one primary action, everything else in ···"
rules), §4.0 is rewritten in R2. Both reviews independently reached that conclusion.

## 2. What the two reviews agree on, and the one fork

Consensus (both reviews, confirmed against the code on 2026-09-05):

- Rest and the between-exercise "done" screen replace the workout instead of sitting inside it. During rest the
  `···` menu is gone (it belongs to `StepCardView`), so overview, skip, finish and corrections are unreachable.
- The "done" screen is a mandatory tap between every pair of exercises and makes the block duration the
  largest thing on screen.
- No undo exists anywhere. Correcting a typo is Skip rest → ··· → Overview → row → sheet → Save.
- The two input rows are unlabelled.
- Log set floats mid-screen with over half the screen empty below it; no keyboard dismissal; no haptic on log.
- Editing a skipped set through the overview or session detail silently does nothing (`SessionEngine.editSet`
  returns early unless the step is logged; both views open the sheet anyway).
- Save failures are swallowed (`try?`), and `persistCompletedSessions` marks a session persisted before its
  write is known to succeed.
- Carry-forward prefill overrides explicitly varied targets (50 → 60 → 70 kg prefills 50 for set 2).
- Home spends its space on a month of projected dots and a hidden tap-to-cycle sparkline while saying nothing
  about the workout behind Start; calendar taps do not open the session.
- Import reads as a data-file editor; the preview cannot show whether the chatbot produced the right exercises;
  a second import never offers to become active; Plan detail's specified Replace action is missing.
- Deletion asks for confirmation in one place and deletes directly in three others.
- The app speaks two visual languages (bare stacks on Home and Workout; grouped lists elsewhere).
- New features should be few: the per-exercise chart, "Do later", basic plan editing, backup restore.

The fork: **what the workout screen is.**

| Option | Shape | Pros | Cons |
|---|---|---|---|
| A. Stable step card (review 1) | Current exercise expanded with its set rows, inputs and action in fixed slots; rest as a strip inside the same screen; an Exercises button opens the full overview as a sheet | Keeps the guided one-tap model that is this app's reason to exist (D1, D11, D19); presentation-only refactor, engine phases largely intact; less scrolling with a bar in one hand | You still open a sheet to see the whole day |
| B. Full scrolling list (review 2) | The overview becomes the main screen: every exercise, every set row, logging in place; rest as a bottom bar | Industry pattern (Strong, Hevy); the whole workout is always visible | Changes the product model from "runs your workout" to "a list you fill in"; more to rebuild; the one-tap prefilled log is easier to lose in a long list |

**Recommendation: A**, with the full overview one visible tap away at all times. A is what the owner asked
for in spirit (quiet, guided) with the context and controls that were missing. If A still feels cramped after
the R2 walkthrough on the phone, B is a presentation change on the same Core and can be revisited.

Second, smaller fork: **what happens between exercises.** Review 1 keeps D14's "no alert, you decide when
you've walked over" and only removes the tap. Review 2 runs a real rest countdown with an alert between
blocks. Recommendation: review 1's version, because D14's rationale was the owner's and still holds; the
alerting variant is listed under Later.

## 3. Decisions to re-open (SPEC §1)

Amend the table in SPEC §1 before any R1/R2 code. Proposed text:

| # | Now | Proposed | Why |
|---|---|---|---|
| D11 | Prefill carries the current session's last weight forward; changing the weight re-prefills reps | Carry-forward applies only to **straight** exercises (all main-set target weights equal or absent). For **varied** exercises (targets differ across sets) prefill is: last session at the same set index → the set's target → empty. Reps initialize once per step and are never rewritten by a weight change. | A pyramid should look like a pyramid after set 1. Predictable beats clever. |
| D14 | Between exercises: full-screen done screen, count-up stopwatch, Continue | Between exercises the next set's card appears **immediately**. A status strip shows "Bench Press done · 9:40 · try 82.5 kg next time" and a small "moving on 0:42" until the next log. No alert, no countdown, no Continue. | Removes one tap per exercise and keeps context; keeps D14's "you decide when to move" rationale. |
| D18 | Home is one Start card, a month calendar, a tappable sparkline | Home leads with the workout: day name, plan, exercise preview, and a button that names the action ("Start Push", "Start Pull early", "Resume Push · 23 min"). A week strip expands to the month. One activity line ("2 workouts this week") replaces the sparkline. | Start is currently blind. Hidden tap-to-cycle is not quiet, it is undiscoverable. |
| D19 | Every set is timed; shown after the fact | Unchanged in storage. Set durations are shown only in the overview rows, session detail and Summary details, never as a hero number and not on the rest strip. | Rep-set timing includes walking and fiddling; it must not outrank a deliberately timed plank. |
| D22 (new) | — | The workout is **one screen with fixed zones**: header, exercise block with the current exercise's set rows, labelled inputs, status strip, bottom-anchored primary action. Working, resting, timed and between-exercise states change the strip's contents, never the zones. | P1, P2. |
| D23 (new) | — | **Undo** after Log set and Skip set, available until the next log/skip, while the rest keeps running. | P3. |
| D24 (new) | — | A failed write is **shown** with Retry and never marks the data as saved. A completed session that could not be written stays in `active-session.json` and is recovered on the next launch. | P4. |
| D25 (new) | — | Every delete of a plan or session **confirms** with one concise dialog; Delete all data keeps its explicit confirmation. No silent swipe-deletes. | Consistency; file deletion has no undo stack. |
| D26 (new) | — | Plans arrive through **Add plan**: Paste plan, Create with a chatbot (three numbered steps), Import file. The JSON editor is a detail, not the front door. The review step shows the actual exercises and targets, plain-language errors first, and a "Set as current plan" choice. | The chatbot round-trip is the product's premise and the screen never explained it. |
| D27 (new) | — | Skipped sets can be **recovered**: "Do this set" (jump back) or "Add result" (log after the fact). Both work in the live overview and in history. | The current sheet's Save is a no-op. |

§4.0 is rewritten in R2 to: one primary action per screen, bottom-anchored; secondary actions may be visible
buttons when a task needs them during the primary task (Exercises, Undo, rest ±30); labels are allowed where a
value does not explain itself; no decorative dividers, badges or cards-in-cards; large numbers only for values
you act on right now (the input values, a running countdown).

## 4. Scope

**In**, in this order: R0 truthfulness, R1 Core for the new loop, R2 workout screen, R3 Home and Add plan,
R4 visual system and Summary, R5 narrow additions, R6 device checklist v2.

**Out** of v1.1 (stays in SPEC §10): Live Activity, Apple Watch/Health, sync, in-app chatbot, social,
badges/streaks, nutrition, recovery scores, themes, an analytics dashboard, plate math, warm-ups, session
notes, automatic progression, the compact text plan format, localization, iPad, landscape. Also out: the
"real rest with alert between exercises" variant, and a "Start set" tap for exact rep timing.

**Preserved untouched**: local files, no accounts, Date-based timers, per-event persistence of the active
session, the import pipeline and every fixture in `examples/`, supersets, drops, timed sets with warning
beeps, bodyweight, progression advice, export, the four tabs.

## 5. Milestones

Sizes are relative to BUILD_PLAN's, for one agent. Each milestone: amend docs → Core → tests green → UI →
simulator screenshots into `build/` → DECISIONS_LOG entries. New test IDs continue TEST_CASES numbering
(G49+, I35+, K18+, L36+, M8+, N11+, O44+, J25+, F15+, H24+).

### R0 — Truthful behavior and finished workflows (½–1 day)

No layout changes. Everything here is "the app already claims to do this."

Docs first: SPEC §8.3 gains a "Writes that fail" paragraph (D24); §4.4 gains the activation choice; §4.8 and
§4.10 gain "Add result" for skipped sets (D27); D25 added. §4.1's "tap again → session detail" and §4.3's
Replace are already specified; those are bugs.

Core / Store:
- `SessionEngine.editSet` accepts a **skipped** step: result set, status → logged, `loggedAt` set if nil,
  advice recomputed, no phase change, no timer. `PlanLibrary.editSession` does the same for history.
- `jumpTo` on a skipped step resets it to pending before entering working (so "Do this set" is a plain jump).
- `AppModel` gets `saveFailure: SaveFailure?` (what failed, the error, a retry). Every `try?` around
  `store.save`/`deleteSession`/`clearActiveSession` becomes a caught error that sets it.
- `persistCompletedSessions` inserts an id into `persistedSessionIds` only after the write succeeds, and
  clears `active-session.json` only when every completed session is on disk. On launch, an active session
  whose phase is `.completed` is written to `sessions/` and cleared (recovery).
- `AppModel.save(plan, makeActive:)` is driven by the user's choice from the preview.

UI:
- Import preview: a "Set as current plan" toggle, default on. Plan detail `···` gains **Replace**
  (opens Add plan targeting this plan's id; saving replaces it and keeps it active if it was).
- Home calendar: tapping a completed day opens the session (a short chooser when a day has two); a projected
  today keeps "Start this"; rest days keep the line.
- Overview and Session detail: skipped rows show **Do this set** (live only) and **Add result**.
- Deletes: swipe-to-delete in Plans and History and the Plan detail menu confirm ("Delete Push Pull Legs?").
- A save-failure alert: "Couldn't save the workout. It's still here; try again." **Retry** / **Later**.
  Retry is also attempted automatically on the next successful write and on launch.

Tests: G49 editSet on skipped → logged, loggedAt set, advice recomputed, no timer effects; G50 jumpTo skipped
→ pending then working; K18 `save(session:)` throws → id not in persisted set, active file kept, Retry
succeeds and clears it; K19 launch with a completed active session → moved to `sessions/`; K20 plans write
failure surfaces `saveFailure`; L36 import with makeActive on/off; L37 Replace from Plan detail keeps id and
active state; N11 activation toggle default; O44 calendar tap opens the session; O45 two sessions on one day
→ chooser; O46 Add result on a skipped row survives reopening; O47 every delete path confirms.

Exit: the three silent no-ops (skipped edit, failed save, second import not active) are gone; the suite is
green on the iPhone 16 simulator.

### R1 — Core for the new workout loop (1–2 days)

Same branch as R2, but its tests go green first and the app must still build at the end (TransitionView
deleted, a temporary banner in its place).

Docs first: D11, D14, D19, D22, D23 in §1; §4.5–§4.8 replaced by one "Workout screen" section (written
now, built in R2); §6.3 block-end rule; §6.5 prefill precedence and removal of the dynamic reps rule;
§6.6 events; §7 `ActiveSession`. TEST_CASES F7/F9, G-section rows that assert `.transition`, and I-section
rows that assert carry-forward on varied targets are rewritten deliberately, with the old expectation noted.

Core:
- **Block end**: `.transition` phase removed. After the last step of a block, phase → `working(next)`
  immediately and `ActiveSession.blockDone: BlockDone?` records `(finishedBlock, at, nextStep, advice)`.
  Cleared by the next log, skip, jump or an explicit `dismissBlockDone` event (replaces
  `continueTransition`). Persisted, so Resume shows the strip with the right "moving on" time. A v1
  `active-session.json` holding `.transition` decodes into `working(nextStep)` + `blockDone`.
- **Undo**: `undoLog(step)` is valid only for the most recently logged or skipped step and only if nothing
  was logged after it. It restores pending, clears result and `loggedAt`, sets `startedAt = now`, clears
  `blockDone`, cancels the rest notification, recomputes the exercise's advice, and enters `working(step)`.
  Not available once the session is completed (history editing covers that). The UI captures the logged
  values before applying so the inputs come back filled.
- **Prefill** (§6.5 revised): `SessionExercise.hasVariedTargets` (main-set target weights not all equal).
  Varied → last session at the same set index → target → empty. Straight → unchanged. `RepsDraft.changeWeight`
  removed; reps initialize once per step.
- **Progress text**: `StepCard.progress` → "Exercise 2 of 5 · Set 2 of 3", "· drop 1 of 2",
  "A · round 2 of 3 · Incline Press" for superset members. The header's "Set 5 of 22" (which counts drops)
  is replaced by this.
- **Set rows**: `StepCard.setRows(session, step, history) -> [SetRow]` — for the current exercise (or the
  current superset round's members): set number, status, logged text ("10 @ 80"), target text, last-time
  text, `isCurrent`. Pure and tested; the view only renders it.
- **Strip text**: `StepCard.blockDoneLine` → "Barbell Bench Press done · 9:40 · try 82.5 kg next time".
- `AlertPlaying` gains a `.logged` feedback kind so the haptic on Log set is testable through the protocol.

Tests: F15 block end → working(next) + blockDone, no notification; G51 blockDone cleared on the next log;
G52 dismissBlockDone; G53 old `.transition` file decodes; G54–G58 undo: valid on the latest step, no-op after
a later log, cancels the rest notification, restores pending and clears advice, works after skipSet and for a
drop step; G59 undo is a no-op when completed; I35 50/60/70 kg → set 2 prefills 60 after logging 50;
I36 straight sets still carry forward; I37 varied with last-session history at index k; I38 reps not rewritten
on weight change; I39 setRows for straight, superset and drop cases; I40 progress text; K21 `blockDone`
round-trips.

Exit: both runners green (`xcodebuild test` and `python3 tools/check_core.py`).

### R2 — Workout screen rebuild (2–3 days)

Docs first: the new §4.5 "Workout screen" (written in R1) is the contract; §4.0 rewritten as in §3 above.

Zones, top to bottom, identical in every state:

1. **Header**: elapsed · progress ("Exercise 2 of 5") · **Exercises** (opens the overview sheet) ·
   **minimize** (chevron) · `···` (Skip set, Skip exercise, Finish workout). Rename exercise leaves the
   mid-workout menu; it stays in Session detail.
2. **Exercise block**: name (link to history), target line with notes, then the current exercise's set rows
   from `setRows`: done rows "✓ 10 @ 80", the current row highlighted with its target and last-time value,
   upcoming rows with targets. Tap a done row → edit sheet; tap an upcoming row → jump. Supersets list the
   round's members. "Last time" appears once, in the rows, not as a separate line and a "Last 80 kg" line.
3. **Inputs**: small-caps labels **REPS** and **KG/LB** above the values; − value +; weight row hidden for
   bodyweight; "82.5 suggested" chip under the weight. Timed sets show the timer in the reps slot; the weight
   row stays. Numbers keep one size across Dynamic Type; the layout reflows instead.
4. **Status strip** (always present, may be empty): during rest a progress line, `2:26`, −30 / +30, Skip,
   and "Set logged · **Undo**" for the rest duration; at zero "Rest over · +0:12" until the next log;
   between blocks the blockDone line and "moving on 0:42"; for timed sets the running/warning state.
5. **Primary action**: bottom-anchored with `safeAreaInset`, above the keyboard, full width. Reads
   **Log set** in working and resting states (logging during rest ends the rest), **Start timer** /
   **Done** / **Stop** for timed sets. A keyboard toolbar with **Done**; `.success` haptic on log.

Minimize dismisses the cover; Home shows "Push in progress · 23 min" with Resume; timers and notifications
keep running (already Date-based); Resume returns to the identical state. The overview sheet keeps its
current content and is reachable from every state.

Tests: O48 zones present and in the same order in working, resting, timed and between-block states;
O49 Log set during rest logs and ends rest; O50 Undo restores the inputs and the row; O51 Exercises opens
during rest; O52 minimize then Resume restores step, inputs and rest remaining; O53 keyboard Done dismisses;
O54 labels present and read by VoiceOver; O55 set rows: done/current/upcoming; O56 six-exercise day needs
zero Continue taps; O57 `.logged` feedback recorded once per log; O58 accessibility XL: no clipped zone,
numbers unchanged in size; O59 the strip between blocks shows advice and moving-on time; O60 timed set uses
the same primary slot. Manual H24: minimize, lock, rest notification fires, Resume.

Screenshots `build/o9-*`, `o9c-*`, `o32-*` replaced. Exit: the owner runs the sample Push day on the iPhone
and tasks T2–T6 in §6 pass without coaching.

### R3 — Home and Add plan (1–2 days)

Docs first: §4.1 (D18 revised), §4.2, §4.4 (D26), §5.1, §5.2, §6.13 removed or moved to History.

Home:
- Start card: "**Push**", "Push Pull Legs · 5 exercises · 48 min last time" (each fragment only when it has
  data), the first five exercise names, then **Start Push** / **Resume Push · 23 min** / on a rest day
  "Rest day · Pull is next" with **Start Pull early**. "Preview" opens the day in Plan detail; "Another day"
  opens a compact chooser.
- A 7-day strip with today's dots and a disclosure to the month grid; cells ≥ 44 pt; taps behave as in R0.
- One line, "2 workouts this week · 1 h 32 min". The sparkline and the home-metric setting are removed
  (`Sparkline` and `HomeMetric` code deleted; `ExerciseHistory.series` stays for R5).

Add plan:
- Entry point renamed **Add plan** on Plans and the empty Home. Three rows: **Paste plan** (primary when the
  clipboard has text), **Create with a chatbot** (steps: 1 Copy prompt, 2 paste it into your chatbot with your
  workout, 3 come back and paste the reply; "Copied" resets after two seconds; the draft survives app
  switches), **Import file**. The text editor is behind "Show text".
- **Review plan** replaces the modal-over-modal: days as compact rows that expand to exercises with per-set
  targets ("50 / 60 / 70 kg"); material warnings (unit mismatch, load removed, grouping changed) in yellow;
  cleanup warnings behind "Details (3)"; the "Set as current plan" toggle; **Save plan**.
- Errors lead with a sentence: "Bench Press, set 2 needs a rep target." Path and code under Details; the
  fix-it prompt unchanged. Core gains `IssueText.friendly(issue, plan context)` with a sentence for every
  E_ code in PLAN_FORMAT §4 and a generic fallback.
- Onboarding: "Try a short practice workout" next to "Try the full sample". `PracticePlan.json` (three
  straight-set exercises, one bodyweight, 60 s rest) is a new Resource, imported through the normal pipeline.
  `examples/` and the manifest are not touched.

Tests: L38 start-early target on a rest day; M8 every E_ code has a non-empty friendly sentence; N12 Copied
resets; O61 Home card wording per schedule state; O62 exercise preview; O63 week strip expands; O64 activity
line; O65 Add plan rows and default primary; O66 review shows per-set targets; O67 material vs cleanup
warnings; O68 friendly error first, details behind; O69 practice plan imports and activates; O70 draft
survives backgrounding.

### R4 — Visual system, Summary, Plan detail, accessibility (1–2 days)

- One design language: grouped/inset lists on every screen (content is list-shaped); one horizontal margin;
  a 4/8/12/20 spacing scale; three type tiers (input numbers, body, small-caps labels and secondary).
- Accent: keep the blue or pick one committed colour; add a green reserved for done rows and PRs.
  `StepButton` becomes a `Button` with a pressed state.
- Summary (§4.9): "**Workout saved**" · Push · 48 min · 16 of 18 sets · "Volume 12,400 kg" (omitted when 0);
  per exercise one readable comparison ("2 more reps at the same weight", "+2.5 kg", "first time") and a
  compact table when weights vary; set durations behind Details; Done.
- Plan detail: compact day rows with disclosure; exercise summaries show per-set variation
  ("3 × 8–12 · 24 / 26 / 28 kg") instead of the first target repeated.
- Accessibility: 44 pt calendar cells; Dynamic Type reflow; VoiceOver pass on the new workout screen, with
  the exercise-name link verified operable.

Tests: J25 comparison text for the comparable, non-comparable, varied-weight and first-time cases;
O71 volume omitted when zero; O72 Plan detail per-set variation; O73 calendar cell ≥ 44 pt; O74 pressed state;
O75 one list style per screen (snapshot); re-run O17–O19.

### R5 — Narrow additions (after R0–R4; each optional, in this order)

1. **Do later** (1 day): `deferExercise(exerciseIndex)` moves the block's pending steps after the last
   pending step of the day; overview shows the new order; `···` and the exercise block get "Do later".
   G61–G64.
2. **Basic plan editing** (2 days): edit exercise name, sets, targets, weight, rest, rep range; reorder
   exercises; duplicate a day. `PlanEdit` operations produce a new `Plan` that is re-normalized and
   re-validated by the existing pipeline; `sourceText` is regenerated so Copy JSON and export reflect the
   edit. L39+, C-section additions.
3. **Exercise chart and PR marker** (1 day): Swift Charts line of `topWeight` over date with reps annotated,
   in `ExerciseHistoryView`; exercise search in History; "PR" on a set that beats the previous best, on the
   Summary and in history. J26–J28. (Moves the chart out of SPEC §10.)
4. **Backup restore** (1 day): Settings → Import backup → validate → counts → Replace all / Merge. K22+.

Live Activity stays out until device use shows rest checks while locked are frequent.

### R6 — Device checklist v2 (owner + agent)

Re-run H3–H23, K16–K17 and O20–O28 on the new screen. Add H24 (minimize, lock, notification, Resume),
O76 (workout at accessibility XL, one-handed), O77 (VoiceOver through one full exercise), K23 (write
failure simulated with a debug launch argument that makes the store directory read-only; the app keeps the
data and Retry succeeds after the flag is removed). Record results in `DEVICE_CHECKLIST.md`.

## 6. Acceptance tasks

A milestone is done when its tasks pass on the iPhone with the sample plan, without coaching.

| Task | Passes when | Milestone |
|---|---|---|
| T1 Start the intended workout | Home names the day and the plan; one tap starts it; on a rest day the button says which day starts early | R3 (R0 for the calendar) |
| T2 Log a normal set | One tap, values prefilled, haptic, row fills in, rest starts in the strip | R2 |
| T3 Correct the last set while resting | Undo (one tap) or tap the done row (two taps); the rest keeps running | R2 |
| T4 Recover a skipped set | Add result saves; the value is there after reopening the session | R0 |
| T5 See what is left, then minimize and resume | Exercises opens in any state; minimize, switch tabs, Resume returns to the same step and remaining rest | R2 |
| T6 Run a pyramid | 50 → 60 → 70 kg prefills each set's own target after logging the first | R1 |
| T7 Import a second plan | Review shows the exercises; material warnings are readable; the plan is active if you said so | R0, R3 |
| T8 Tap a calendar day | A completed day opens the session; two sessions offer a choice | R0 |
| T9 Large text and VoiceOver | All of T2–T5 at accessibility XL and with VoiceOver | R2, R4 |
| T10 A failed write | Data stays, Retry works, nothing says "saved" until it is | R0, R6 |
| T11 Read the Summary | Name, duration, sets and one comparison per exercise are understood in a few seconds | R4 |

## 7. Order and process

Why this order: R0 is small, needs no design decisions, and removes every place the app lies, so trust is
restored before anything moves. R1/R2 is where the clunkiness lives and where the walkthrough happens; Home
and Import (R3) matter less per session and would otherwise be redesigned around a workout screen that was
about to change. Visual polish (R4) is applied once to layouts that have stopped moving. Features (R5) come
only after the everyday loop feels effortless.

Process for the implementing agent:

1. On approval, add one line to `CLAUDE.md`/`AGENTS.md` (both, identically) pointing to this file and
   stating "v1.1: milestones R0–R6 in order; SPEC amendments per ITERATION_2_PLAN §3 land before code."
2. Each milestone starts with the SPEC and TEST_CASES edits, committed on their own. Rewritten expectations
   note the previous behavior so the change is deliberate, not a test made to pass.
3. Core before views; both runners green; simulator screenshots into `build/` with the same `-ui*` debug
   arguments; every deviation in `DECISIONS_LOG.md`.
4. After R2, stop for the owner's phone walkthrough (T2–T6) before starting R3.
5. When the docs are final, regenerate `HANDOFF_BUNDLE.md` and the design-package zip so the bundle matches
   the folder.

Fixtures in `examples/` and `manifest.json` are never edited. `PracticePlan.json` lives in Resources only.

## 8. Risks

- **Removing the `.transition` phase** touches F/G tests, resume (K16) and the persisted `ActiveSession`.
  Mitigation: tolerant decoding of the v1 file (G53), and R1's tests green before any view changes.
- **Undo and notifications**: undo must cancel `rest-timer` and never leave a stale notification. G56 and the
  device check H24 cover it.
- **Prefill change** alters I-section expectations on purpose. Any fixture-driven test that disagrees is
  checked against the amended §6.5, not adjusted to pass.
- **Set timing (D19) gets longer** without the Continue gate. Accepted; the number is demoted everywhere.
- **Scope creep in R5**: each item is optional and stops on its own; none starts before R4 is green.

## 9. Owner decisions needed before R1

1. Workout screen: stable step card (recommended) or full scrolling list.
2. Between exercises: strip with no alert (recommended, keeps D14's rationale) or a real rest with an alert.
3. Reps rule: initialize once and never rewrite (recommended) or keep the dynamic re-prefill from D11.
4. Deletes: confirm everywhere (recommended) or an undo toast with deferred file deletion.
5. Sparkline: remove (recommended) or move to History with an explicit metric picker.
6. Tabs: keep four (recommended for this release).

Answer these in SPEC §1 and the agent builds what the docs say.
