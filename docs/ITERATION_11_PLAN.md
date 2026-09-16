# Jimm's Bro+ — v1.10 plan (iteration 11)

The owner's notes, on 2026-09-14 after living with v1.9, in their words: *"Following what we made
with plan or an active day, I want to make everything symbols, and the app colorful … Reps should
be vertical bars one next to another … for the required range, you should have solid vertical bars,
and for the remaining bars in the recommended range you should have transparent vertical bars.
Remove the text at the top of the screen … Remove the text describing the exercise, and instead
have a question mark symbol … remove the set 1 of three … In between different exercises, the timer
should move up, but next to it there should be a circle that gradually fills up, turning from red to
green. Once full, a checkmark appears … Status bar should be smart and each 'step' should be
proportional to the median time it takes to complete one exercise … you should be able to sideways
swipe the screen into the current and next exercises … Should be a confirmation button before
changing a different day's exercise … Should just say 'change [day]'. Also, looks too much like a
settings menu. When there is a sequence of squarishes above one week, there should be a row below.
Also, make a sequence look more combined."*

Two things under the notes. **First**, the Workout screen is the one screen v1.7–v1.9 left in
words: Today, the ···, the picker and Plans all learned to speak in squares (D69, D75, D78), and the
screen you spend an hour on still says *"Exercise 2 of 5 · Set 2 of 3"* above a row that says
*"Aim 8–10 reps · 26 kg"*. The owner wants the same rule there — **no words without a cue**, and
then no words — with the reps drawn, not written. **Second**, colour. v1.7 gave each day a colour
and forbade it everywhere but four places (D65). The owner asked for a colourful app and then, over
four drawings, chose what colour should *mean* on the workout screen: not which exercise, but
**which state** — done is the day's colour, now is blue, not yet is grey. That is one rule for every
mark on the screen, and it is what makes the page colourful without a second palette.

The requirements were settled over two mocks: round 1, *"Workout in Symbols"* —
https://claude.ai/artifact/V49usY7oPtizg3Xbq9ZHfw — read the notes and asked Q1–Q14; round 2,
*"Symbols, Round Two"* — https://claude.ai/artifact/HXHE2R3QtKy2xmGjo4FwEb — was redrawn four
times on the owner's corrections (*"looks the same, ugly, only two colours"*; *"so many bars feels
unnecessary"*; *"remove the plus and minus for the set, the upper end of the range transparent,
incompleted exercises grey, current set blue, a reserved colour, finished sets the colour of the
day"*) and is the page this plan builds. Every phone on it works. Where the owner left a choice to
the plan (the marks' hierarchy on the bar, the pace rule, the walk's minimum, a superset's page, the
button's colour) the choice is made below and named as the plan's, with the alternative in one line.

## The example this plan speaks in

Push Pull Legs, Push green. Today is **Wednesday 16 September**, Push: Barbell Bench Press
4 × 6–8 at 80 kg, Incline Dumbbell Press 3 × 8–10 at 26 kg, Lateral Raise 3 × 12–15 at 10 kg,
Tricep Pushdown 3 × 10–12 at 30 kg, Plank 3 × 30–45 s. Bench is done; the owner is on Incline's
second set, having logged 10 on the first; last time the second set was 9.

## Milestones

**P0–P7, in order.** Each ends with the full suite green on the three routes, a Release build and
`tools/check_release.py`, and one commit on `v1.10-symbols`, off `v1.9-swaps` at v1.9 (3dc52f1) —
or off `main` once v1.9 is fast-forwarded onto it. SPEC amendments land before the code that
depends on them. Each milestone is one or two decisions, **D79–D86**, recorded in SPEC §6 and
`DECISIONS_LOG.md` by the milestone that lands it. Test cases take the prefix **TP** in
`TEST_CASES.md` (TQ was v1.9's) — the ids below are proposals, and TEST_CASES renumbers on landing
as it did for every earlier plan.

**This plan touches the on-disk contract once**, in P3: one optional field, `restBetweenExercises`,
on `Plan`. It is decoded with a default of nil, so every `plans.json` already on a phone and every
frozen file in `examples/store/v1/` reads as it did; a test proves the frozen plan decodes without
it. The plan format gains the same field (§2's plan table, §3.6's fallback chain) and the prompt
asks for it, so one new fixture joins `examples/` through `tools/generate_fixtures.py` and
`tools/reference_import.py`. Nothing else touches the pipeline, the fixtures, the sessions, the
swaps, Today, the calendar, History, the Summary or Settings. **The five zones stay** (§4.5, D22):
only their contents change, which is what makes every milestone below a change to
`WorkoutScreen.model` and a unit test rather than a new screen.

| Milestone | Decision | Lands |
|---|---|---|
| P0 | — | this plan, the branch, the mocks |
| P1 | D79, D80 | three states, three colours; the header is the bar |
| P2 | D81 | the exercise in symbols: the ?, the dots, the card of cells, Save |
| P3 | D82 | the walk: a count-up and a ring; `restBetweenExercises` |
| P4 | D83 | pages: swipe to the next and previous exercise |
| P5 | D84 | a bar that learns your pace |
| P6 | D85, D86 | Change *day* in squares, with a button; squares that join |
| P7 | — | docs, checklist, bundle, 1.10 |

---

## P0 — This plan, the branch, the mocks

`docs/ITERATION_11_PLAN.md` (this file) on `v1.10-symbols`, the file added to
`tools/build_bundle.py` and the bundle regenerated in the same commit (CI checks it), and the
paragraph in `CLAUDE.md` and `AGENTS.md` that introduces v1.10 — ending *"P0 is written; nothing
else is built"* until P7 rewrites it. The mocks stay artifacts; nothing is copied into the repo but
the two links above.

---

## P1 — Three states, three colours (D79), and the header is the bar (D80)

### D79 — three states, three colours

On the Workout screen and the Lock Screen activity, every mark that stands for a set or an
exercise is in one of three colours, and the colour says its **state**:

| State | Colour | Where it shows |
|---|---|---|
| **Done** — logged, or skipped and then given a result | the day's colour (§6.41) | the bar's done sets, the filled dots, a logged set's cells when reopened, a finished exercise's dot by its name |
| **Now** — the current set, and only it | **blue**, the accent | the bar's one blue tick, the ringed dot, the card's cells, the reps number, the current exercise's dot by its name |
| **Not yet** — every set and exercise ahead, and a skipped set | grey (`secondarySystemFill`) | the bar's track, the hollow dots, the cells of an exercise looked at ahead |

The owner's words: *"incompleted exercises grey, current set blue (a reserved colour), and
finished sets the colour of the day."* Three consequences:

- **Blue is reserved on this screen.** §4.0's *the accent says tappable* holds everywhere else;
  on the Workout screen the accent says *now* and nothing else is blue. The primary button is
  **ink** (label colour on the system background — black in light, white in dark); ⌄, ···, the ?
  and the name's link are the secondary label colour; the suggestion chip, the empty-weight outline
  and the strip's Undo are ink or grey. *(The plan's choice, C2 on the mock; the alternative is the
  day's colour on Log set, one line in SPEC. Blue on the button is the one answer that is ruled
  out, because it would unreserve the colour.)*
- **The day's colour gains a fifth meaning-place** (§6.41): on this screen it says *happened*, as
  the calendar's fill says it — a logged set fills in the colour of the day it belongs to, so the
  bar fills with Push's green as Push goes. The reserved green of §4.0 (*this happened*, v1.1) was
  already the first day's colour; on this screen the day's colour takes that job for every day.
- **Grey has one job.** Not "disabled", not "secondary": *not yet*. Nothing on the screen is
  disabled, since every control is earned before it appears (§6.40).

`Core/WorkoutMarks.swift`: `enum MarkState: String { case done, now, todo }`, and a
`MarkState.of(step:session:)` that every model below calls, so the rule is written once and pinned
by one test. The view layer maps a state to a `Color` in `DaySquare.swift` beside the day colours
(T23 reads it), compiled into the widget extension too: done → the day's colour (grey when the day
has none, as History draws it), now → `.accentColor`, todo → `Color(.secondarySystemFill)`.

The ring (P3) is red, amber and green and is none of these: it is a duration, not a set, and its
colours are a traffic light. Yellow past the top of a range (P2) is a warning, as §6.41 keeps it.
A test holds the three state colours apart from both.

### D80 — the header is the bar

Zone 1 loses its words. What leaves: the stage title (*Exercise 2 of 5 · Set 2 of 3*), the
percentage, the elapsed · progress line, and the **Exercises** button. What stays: the day's square
at the left, ⌄ and ··· at the right. Between them, the **bar**:

- **One segment per block**, in the order the day runs them, with a 3 pt gap between segments so
  an exercise is the bigger unit; **a hairline tick at each set** inside a segment. Done sets fill
  from the left in the day's colour, the current set is one blue stretch, the rest is the grey
  track. Skipped sets count as done for the fill (§6.15, D34 kept that) and draw in grey with no
  tick moved, so the bar never says a skipped set happened.
- **A caret** beneath the segment being looked at — the current one until P4 lets the finger move
  it.
- **The elapsed time**, 11 pt monospaced, under the bar's right end. *(The plan's choice, C6: it is
  the one number the Lock Screen shows that the screen would otherwise lack; dropping it is one
  line.)*
- **Widths**: by set count until P5 gives each block its own pace, so a 4-set block is a third
  longer than a 3-set one from the first workout.
- **Tap the bar** to open the Overview (§4.8), which was the Exercises button's job. The whole
  header row is the target, 44 pt tall; a VoiceOver user hears the stage in words —
  `WorkoutStage.title` stays exactly as it is, spoken, and printed nowhere on the screen. §6.40's
  table gains the bar's tap as its second ungated control, beside the strip: it is the only way to
  the Overview and needs no history.

*(The owner wrote "a visual marking at each of the different set percentages … a smaller visual
marker for each exercise" — sets the larger mark. The plan draws exercises as the larger unit
because five gaps read and sixteen notches do not, the reading the owner reviewed through four
draws without correction; round 1's notches-and-dots is the alternative, one line in SPEC.)*

The Lock Screen activity's bar takes the same states — done in the day's colour where it drew the
accent, grey ahead — and nothing else about it changes; the compact Island still has room for a
colour and nothing else (D41) and keeps drawing its figure in the day's colour.

Core: `Core/WorkoutBar.swift` — `struct WorkoutBar { segments: [Segment] }`,
`Segment { blockIndex, weight: Double, sets: [MarkState], caret: Bool }`, built by
`WorkoutBar.of(session:showing:pace:)`; `WorkoutScreenModel` gains `bar: WorkoutBar` and loses
nothing yet — `stage`, `completion`, `elapsed` and `progress` stay on the model for the activity,
the spoken line and the tests, and the view stops drawing them. `Features/Workout/WorkoutView.swift`
zone 1 becomes `BarView` (a `Canvas`, one draw call, no per-set views: a 16-set day is one shape).

SPEC: §4.5 zone 1 rewritten; §6.15 (*the stage in words is spoken and printed on the Lock Screen,
not on the screen*); §6.17 (the activity's bar colours); §6.40's table (the bar's tap, ungated);
§6.41 (the fifth place: *happened* on the Workout screen, and the accent reserved for *now* there,
as an exception to §4.0 named as one); new §6.52 *Three states, three colours (D79)* and §6.53 *The
header is the bar (D80)*.

Tests (proposed): **TP1** `MarkState.of` for every step state — pending ahead is `todo`, the
current step `now`, logged `done`, skipped `todo`, a skipped step given a result `done`;
**TP2** the state colours are three, none is red, amber or yellow, and done with no day colour is
grey (extends T23); **TP3** `WorkoutBar.of` on the example: five segments with 4/3/3/3/3 ticks,
Bench's four sets done, Incline's first done and second now, thirteen todo, the caret on Incline;
**TP4** a skipped set fills the bar but draws `todo`; **TP5** `WorkoutScreenModel.zones` is the same
five in the same order in every state (extends O50), and the header's spoken line is
`WorkoutStage.title`; **TP6** (ui) no text in zone 1 but the elapsed time; **TP7** (device) the bar
at 16 sets on a 6.1-inch screen: ticks visible, gaps visible, the blue tick findable at arm's
length, in light and dark.

---

## P2 — The exercise in symbols (D81)

Zone 2, top to bottom:

1. **The name**, 22 pt bold, opening the exercise's history as it does today, led by a dot in the
   exercise's state (D79) — blue while it is the one being done, the day's colour once every set
   is logged, grey ahead. In a superset block the name is the *current step's* exercise, changing
   as the round alternates, which is what the row label did (§4.5, *"each row names its
   exercise"*).
2. **The ?** at the name's right, a 24 pt circle in the secondary colour, opening a popover with
   the exercise's notes and, for an exercise changed mid-workout (D42), *"was Barbell Row"* as its
   first line. **Present only when there is something to show** — an exercise with no notes and no
   change has no ?, because a ? that opens nothing is a control that leads nowhere (D56). The
   target line leaves the screen: the range moves into the card, the notes behind the ?, *"paired
   with …"* into the dots, which draw the pairing.
3. **The dots**, one per step of the block, centred: filled in the day's colour when done, a blue
   ring with a blue centre for the current one, a grey ring ahead, a grey ring with a slash for a
   skipped one. A drop (§3 of the format) is a step and so a dot; a superset's rounds are its steps
   in order. **Tap a filled dot** to change that set: the card shows what was logged, the inputs
   take it, and the primary reads **Save** (`.editSet`, the Overview's sheet made inline — the
   sheet stays for the Overview and Session detail). **Tap a grey dot** to do that set now
   (`jumpTo`, as tapping an upcoming row did). A slashed dot is `jumpTo` too; *Add result* for a
   skipped set stays in the Overview (D27). The blue dot does nothing. The dots are 18 pt with
   10 pt between, the row 44 pt tall (P6's rule).
4. **The card**, the one card on the page, showing the set the dots point at: its range and weight
   at the left in two lines (**8–10** and *26 kg*; **30–45** and *sec* for a timed set; a single
   number when the range is one), and at the right its **cells**, one per rep:
   - **a target**: solid to the minimum, translucent — the colour at 24 %, no outline — to the top
     of the range; a range with no top shows the minimum alone; a caret beneath the cell of the reps
     in the field, so the number and the cells never disagree; past the top of the range the extra
     cells are yellow, translucent (a warning, not a state); a 2 pt line above the cell you reached
     last time (`SetRow.lastTime`'s number, now a mark);
   - **a logged set**: solid to what was done, yellow solid past the range;
   - **a timed set**: one cell per 5 seconds, rounded up, so 30–45 s is nine cells with six solid;
   - a gap after every fifth cell, so 12–15 counts at a glance; cells wrap onto a second line when
     a range is long, 8 × 22 pt each with 3.5 pt between, 320 pt of width holding twenty.
   The card is white on the wash (P1's ground), the only shadow on the page; on an exercise looked
   at ahead (P4) its cells are grey; on one behind, the day's colour.
5. **Undo** returns to the strip: *Set logged · Undo* while the rest after it runs (§4.6's v1.2
   place), since D59's row is gone; after the rest, the set's dot is the way. `undoStep` stays on
   the model; the strip reads it.

**The set rows leave.** `WorkoutScreenModel.rows` becomes `dots: [SetDot]` and `card: SetCard`;
`StepCard.setRows`, `rowLabel` and `targetLine` in `InputRules.swift` stay for the Overview and
Session detail, which still speak (§4.8). `Wording` and **Settings → Compact notation** (D58) stay
for the screens that still have sentences — the Overview, the Summary, History, the Lock Screen —
and no longer reach the Workout screen, which has none; SPEC §6.34 says so in one line.

Core: `Core/RepCells.swift` — `struct RepCells { cells: [Cell] }`, `Cell { fill: solid | faint,
over: Bool, caret: Bool, last: Bool, group: Int }`, built by `RepCells.target(_:reps:lastTime:)`,
`RepCells.logged(_:result:)` and `RepCells.timed(…)`; `Core/WorkoutScreen.swift` — `SetDot { step,
state: MarkState, skipped: Bool }`, `SetCard { range: String, weight: String?, cells: RepCells,
colour: MarkState }`, `PrimaryAction.Kind.save`, and an `editing: Int?` on the model that
`WorkoutScreen.model(…, editing:)` takes from the view, never stored, as Today's `shownOffset` is.
`SessionEngine` needs nothing new: `.editSet` and `.jumpTo` exist.

SPEC: §4.5 zone 2 and zone 5 (Save) rewritten with *(v1.1–v1.9: …)* italics; §4.6 (Undo back in
the strip during the rest); §6.34 (Compact notation's reach); new §6.54 *The exercise in symbols
(D81)*, with the cells' rules as a list, because they are the format of a mark and will be asked
about.

Tests (proposed): **TP8** `RepCells.target` for 8–10 at 10 reps: ten cells, eight solid, two faint,
the caret under the tenth, one group gap after the fifth; at 12 reps: two yellow cells past the top;
a range of 8 alone: eight solid and no faint; a range with no top: the minimum alone; **TP9**
`RepCells.logged` for 12 on 8–10: ten solid and two yellow; for 6: six solid and four faint, none
yellow; **TP10** `RepCells.timed` for 30–45 s: nine cells, six solid; for 50 s logged: ten, the
tenth yellow; **TP11** `SetCard` carries the last-time line under the cell last time reached, and
none when there was no last time; **TP12** the dots on the example: four done, one done, one now,
one todo per block, a skipped step slashed, a superset's rounds in order; **TP13** tapping a filled
dot yields a model with `editing`, the inputs holding the logged result and the primary **Save**,
and Save applies `.editSet` and returns to the current set; **TP14** the ? is offered only with
notes or a change, and its text leads with *was …*; **TP15** (ui) zone 2 has no sentence: the name,
the dots, the card's range and unit; **TP16** (device) cells at accessibility text sizes wrap and
the inputs and the button stay on screen (extends D56's row).

---

## P3 — The walk: a count-up and a ring (D82)

Between exercises the strip changes shape, and only then. The owner: *"the timer should move up,
but next to it there should be a circle that gradually fills up, turning from red to green. Once
full, a checkmark appears. The circle represents the minimum time to take between exercises (as
declared in the plan guide). When you tap the circle it gives you a really short explanation."*

- **The count-up.** The walk counts from 0:00, as v1.1's *moving on · 0:42* did, in the strip's
  large figure; it is Date-based (`startedAt`, §6.4) like every timer. *(The plan reads "move up"
  as counting up, not as moving higher on the screen — the zones do not move, D22.)*
- **The ring**, 58 pt, at the strip's left: fills clockwise over the **minimum** and turns from red
  through amber to green as it fills; full, it becomes a green disc with a white check, and the
  count-up keeps going in the secondary colour so you still see how long you have stood there. The
  alert (§6.4) fires when the ring fills, where today's fires when the countdown ends — same
  moment, same `endsAt`. **Tap the ring** for one sentence: *"At least 2:00 between exercises.
  Your plan's minimum — when the ring is full, you're ready."* (`RestText.ringExplanation`, Core).
- **−30 / +30 / Skip leave this kind of rest**: a count-up has nothing to skip, and Log set — or
  Start timer — already ends the walk, as it ends every rest (§4.6). The warm-up and the rest
  between sets keep their countdown, their controls and their words. *(The owner named the circle
  for the walk; C5 on the mock offers one ring for all three kinds, and it is one line in SPEC
  because `RestKind` already makes the three one thing.)*
- **The minimum comes from the plan** — *"as declared in the plan guide"* — with the setting as
  the fallback: a new optional `restBetweenExercises` on the plan, whole seconds, in
  `RestResolution.after`'s between-exercise branch before `Settings.transitionRestSeconds`.
  `docs/ITERATION_3_PLAN.md` meant this in v1.2 and never built it. Zero means straight through, as
  the setting's zero does.

**The format** (`docs/PLAN_FORMAT.md`): §2's plan table gains `restBetweenExercises` (optional,
seconds); §3.6's fallback chain gains the step; §4 validates it as it validates `restSeconds`
(a non-negative integer; a string of digits accepted by the same leniency; `E_REST_NEGATIVE`
reused). **The prompt** (`docs/PROMPT.md` §1 and §5, the two lines that ask for `restSeconds`):
one clause more — *"restBetweenExercises: whole seconds to walk between exercises; if unspecified,
120"*. **The fixtures**: one new file, `rest_between_exercises.json`, a plan with the field, in
`manifest.json` with its expected value, produced by `tools/generate_fixtures.py` and read by
`tools/reference_import.py`, which learns the field in the same commit so the Python and the Swift
agree. **The contract** (`Core/Persistence.swift`): `Plan.restBetweenExercises: Int?` decoded with
`container.optional`, so a `plans.json` without it is unchanged; the frozen plan in
`examples/store/v1/` is not regenerated and a test decodes it.

Core: `RestState` for `.betweenExercises` keeps `startedAt` and `endsAt` (= start + minimum);
`TimerDisplay` gains `direction: up | down` and `fraction: Double`; the strip's `.blockDone` kind
carries the ring; `RestResolution.after` reads the plan first. The Live Activity shows the count-up
for this kind — its timer already takes a range (`timerRange(now:)`); it gains a direction.

SPEC: §4.6's table (the walk's length: *the plan's, then the setting*); §4.7 rewritten for the ring
and the count-up, with −30/+30/Skip leaving it; §6.3 (the fallback chain); §6.4 (a count-up is a
Date too); new §6.55 *The walk: a count-up and a ring (D82)*; PLAN_FORMAT §2, §3.6, §4; PROMPT §1,
§5.

Tests (proposed): **TP17** `RestResolution.after` between blocks: the plan's 90 before the
setting's 120, the setting when the plan has none, zero from either meaning straight through;
**TP18** the fixture imports with `restBetweenExercises` 90 and `"90"` alike, `-1` refused with
`E_REST_NEGATIVE` at `restBetweenExercises`, and the manifest's expectation matches
`reference_import.py` (extends the manifest test); **TP19** the frozen v1 plan decodes with nil,
and a plan with the field round-trips; **TP20** the strip between exercises: direction up, fraction
0 at start, ½ at half the minimum, 1 and a check at the minimum and after, the count-up continuing
past it, no −30/+30/Skip, Log set present throughout; **TP21** the alert is scheduled for `endsAt`
as it was (extends the notification test); **TP22** `RestText.ringExplanation` names the minimum
in m:ss; **TP23** (device) the ring's hue at 0, ½ and 1 reads red, amber and green on a Push day
and on a Pull day beside the orange, in light and dark; the check appears at the minimum, the
count-up keeps going.

---

## P4 — Pages: swipe to the next and previous exercise (D83)

Zone 2 becomes a pager, one page per block, the current page shown until the finger moves it.
The owner: *"sideways swipe the screen into the current and next exercises (should indicate where
you are in the progress bar, but the progress bar doesn't move. If you go to something completed,
it makes what was completed a bit more translucent, and if you go into the future, a grey
something indicates)."*

- **The bar's fill never moves; the caret does.** Looking at any page, the done sets are still the
  day's colour and the current set still blue — the bar is the record. The caret sits under the
  page being looked at.
- **A page behind**: every dot filled, the name's dot in the day's colour and a check where the ?
  was, the card showing the block's last set at 70 % opacity — *"a bit more translucent"* — and
  its cells in the day's colour. Tap a dot to change that set (P2's Save). Zone 3 is empty; zone 5
  reads **↩ Back to Incline Dumbbell Press**, which returns to the current page.
- **A page ahead**: grey dots, a grey card showing its first set's target, the name's dot grey.
  Zone 5 reads **▶ Do this now**: it jumps to the block's first pending step (`jumpTo`), and the
  block you were on waits its turn as **Do later** leaves it (D28). *(Round 1's Q10; the plan says
  yes, because a page you can look at but not start is a control that leads nowhere.)*
- **The next page peeks** 12 pt at the edge, which is the phone's way of saying *swipe*; no ‹ ›,
  no page dots — the bar's caret is the page indicator.
- **A superset block is one page**, its rounds the dots, its name the current step's — since a
  block is what the engine advances through (`StepBuilder.flatten`). *(The owner's "better
  handling between different current exercises" was put to them as R8; the reading here is one
  page per block, and two pages that the log slides between is the alternative, one line in SPEC.)*
- **During a rest** the page is the one the rest leads to, as the card already is (§4.7).

Core: `WorkoutScreen.model(…, showing: Int?)` — the block being looked at, nil for the current
one, held by the view and never stored; the model's `bar.caret`, `dots`, `card`, `inputs` (absent
off the current page) and `primary` (`.back`, `.doNow`) follow from it, so the page states are a
unit test. `PrimaryAction.Kind` gains `back` and `doNow`. Nothing in `SessionEngine` changes:
`jumpTo` is what Do this now sends.

SPEC: §4.5 zone 2 (the pager) and zone 5 (Back, Do this now); §6.6 unchanged (`jumpTo` is v1.1's);
new §6.56 *Pages (D83)*.

Tests (proposed): **TP24** `model(showing: 0)` on the example: the caret on Bench, dots all done,
the card its fourth set logged, no inputs, primary **↩ Back to Incline Dumbbell Press**;
**TP25** `model(showing: 2)`: the caret on Lateral Raise, grey dots, the card its first target,
primary **▶ Do this now**, and applying it makes Lateral Raise's first step current with Incline's
two pending steps still pending; **TP26** the bar's fill is identical for `showing` 0, nil and 2;
**TP27** a superset block is one page whose name follows the current step; **TP28** (ui) the swipe
moves one block per gesture, the edge peeks, and a page behind is at 70 %; **TP29** (device) a
swipe during a rest, and Log set from the current page after swiping away and back, both work; the
Lock Screen does not change when a page is looked at.

---

## P5 — A bar that learns your pace (D84)

The owner: *"Status bar should be smart and each 'step' should be proportional to the median time
it takes to complete one exercise, with a min and max limit. (Only once a history is established)."*

- **A block's stretch of the bar is as long as that exercise usually takes you.** Its duration in
  a past session is from its first step's `startedAt` to its last step's `loggedAt`, plus the walk
  after it (the rest of kind `.betweenExercises` that followed, which the next block's first
  `startedAt` bounds) — so the segment holds the ring too. The **median** over past sessions of the
  same exercise, by name, from the sessions on the phone (`SessionStep.startedAt` and `loggedAt`
  have been written since v1.2, D19; nothing new is stored).
- **History counts from the third time.** An exercise done fewer than three times before uses the
  day's average time per set × its sets; a day with no history at all is by set count, as P1 drew
  it (every exercise the same per set).
- **Held between ½× and 2× the day's average stretch**, so one long exercise cannot squeeze four
  others into slivers and a quick one is still findable.
- **Timed sets count their seconds**, as they count them now; a changed exercise (D42) uses the
  name it now has; a skipped block uses its sets.

*(The rule is the plan's — round 1's Q7 and R9 were not answered — and it is one function, so
another count or another clamp is a two-line change.)*

Core: `Core/Pace.swift` — `Pace.weights(day:history:)` → `[Double]`, one per block; pure, tested
on fixtures; `WorkoutBar.of` takes it. The Live Activity's bar stays by set count (D41: room for a
figure and a fill, not for a pace).

SPEC: §6.53 gains the widths' rule; new §6.57 *A bar that learns your pace (D84)*.

Tests (proposed): **TP30** `Pace.weights` on a day with no history: proportional to set count;
**TP31** with three past sessions: Bench's median of 14, 12 and 15 minutes → 14, Plank at 4, and
the walk after each counted in; **TP32** an exercise done twice uses the day's average per set;
**TP33** the clamp: a 40-minute block on a 7-minute average is held at 14, a 1-minute one at 3.5;
**TP34** a renamed exercise's history is found by its current name, a skipped block by its sets.

---

## P6 — Change *day* in squares, with a button (D85), and squares that join (D86)

### D85 — the picker, redone

The owner: *"Should be a confirmation button before changing a different day's exercise. Should
have the option to change to a different day, custom day at the bottom, and also change the
specifics of today. Should just say 'change [day]'. Also, looks too much like a settings menu."*

The sheet Q4 built (§6.50) keeps its three kinds and changes its shape:

- **Its name is the day it changes**: the ··· item and the title both read **Change Push**, after
  the day the strip is showing, with the day's square before it; the line *"For Wednesday 16
  September only. The plan does not change."* stays under the title, as the one sentence that is
  needed (D55: nothing untrue).
- **Squares, not rows.** This plan's days as one **joined strip** of 58 pt tiles under the plan's
  name — the day being changed marked *today* in its tile — then every other plan's days as a strip
  of outlined tiles under its name (the outline as §6.50 draws it), then one dashed tile,
  **Custom**, at the bottom. No section headers, no grouped list: the strips are the sections.
- **A tap marks; the button confirms.** A tapped tile takes an ink ring and a check; the primary
  button at the bottom is disabled and reads **Change Push** until something is marked, then names
  the effect with both squares — **Push → Pull** — or, for Custom, **Write a day for Wednesday**,
  which opens Q5's sheet (§6.50's *day just for Wednesday*) with Save reading **Use for Wednesday**
  as it does. Nothing changes before the button is pressed; the picker pops to Today on it, as it
  did on the tap. *(This reverses D48's one-tap on this sheet on the owner's ask: a day changed by
  accident is the case the button is for.)*
- **Today's exercises**, one card under the strips: the shown day's square and name, its exercises
  with their set blocks, a chevron. Tapping it opens Q5's sheet **pre-filled with the day as it
  stands** (D77's pre-fill, with the day's JSON) and Save reading **Use for Wednesday** — the
  owner's *"change the specifics of today"* through the sheet that exists, as a day of its own
  (`.own(day)`), the plan untouched. *(An in-place editor — swap, drop, add — is parked; it is a
  second screen, and the sheet already accepts any edit the format allows.)*

Core: `DayChoices` (`Core/ChangeDay.swift`) gains the button's title (`ChangeDayText.confirm`) for
a marked choice and the disabled state; `HomeStart.alternatives`' item title becomes *Change
<day>*. The sheet is `ChangeDayView` redrawn with `CycleStrip` (below) at tile size.

### D86 — squares that join

The owner: *"When there is a sequence of squarishes above one week, there should be a row below.
Also, make a sequence look more combined."*

- **Seven to a row.** A cycle longer than seven wraps at seven, the second row under the first, in
  the Plans list's symbol, on the plan's page and in the ··· (§6.49, §6.51). No weekday letters:
  a rotation's rows are not weeks, and a letter above a rotation's square would be untrue (D55).
- **The squares touch**, 2 pt apart, the row's first and last corners rounded and the inner ones
  square, so a cycle reads as one thing; a rest day is a grey square in the strip, not a gap.
  Today's square is outlined in ink as the calendar outlines it. The picker's strips (D85) are the
  same drawing at tile size.
- **Today's week strip stays apart** (§6.44): its squares are days you tap one at a time.

Core: `PlanText.squares` gains `rows(of: 7)`; the view is one `CycleStrip` in `DaySquare.swift`
that `CycleSymbol`, the plan page (which drops its `WrapLayout`) and `ChangeDayView` all use.

SPEC: §4.1's ··· (the item's name); §6.50 rewritten for the button, the strips and the card; §6.49
and §6.51 for the joined rows; new §6.58 *Change day in squares (D85)* and §6.59 *Squares that join
(D86)*.

Tests (proposed): **TP35** the ··· item and the sheet's title read *Change Push* after the shown
day, *Change Pull* after a swapped one; **TP36** `ChangeDayText.confirm`: disabled *Change Push*
with nothing marked, *Push → Pull* with both names, *Write a day for Wednesday* for Custom;
**TP37** marking writes nothing; confirming writes the swap Q4 wrote, and the pattern's own day
still deletes it (extends TQ26); **TP38** Today's exercises opens the sheet pre-filled with the
day's JSON and Save produces `.own(day)` (extends TQ28); **TP39** `PlanText.squares.rows(of: 7)`:
a 10-day cycle is 7 + 3, a 7-day one row, a 14-day two full rows, a weekday plan one row; **TP40**
(ui) the strips have no section headers and the cycle's squares touch; **TP41** (device) a 10-day
cycle in the Plans list, on the page and in the picker reads as one thing at the list's size and
the tile's.

---

## P7 — Docs, checklist, bundle, 1.10

- SPEC: the amendments above consolidated, with *(v1.9 …)* italics under each changed rule;
  §4.5's five zones rewritten once, top to bottom, as the page now is.
- `TEST_CASES.md`: the TP rows, renumbered as they landed. `DEVICE_CHECKLIST.md`: a **v1.10 rows**
  section (TP7, TP16, TP23, TP29, TP41).
- `BUILD_STATUS.md`; `DECISIONS_LOG.md` (D79–D86, one line each, the D48 reversal on the picker,
  the D59 move of Undo and the §4.0 exception named as such); the v1.10 paragraph in `CLAUDE.md`
  and `AGENTS.md` rewritten for what shipped. `docs/PRIVACY.md` names no fields, so
  `restBetweenExercises` changes nothing in it.
- README: `docs/screenshots/workout.png` retaken — it is the one screenshot this release changes,
  and the landing section shows it.
- Version **1.10** on every target (`MARKETING_VERSION`, six places) and in `docs/APP_STORE.md`;
  the bundle regenerated (`tools/build_bundle.py`); Release build and `check_release.py` green.

---

## What this plan deliberately does not do

- **Colour per exercise.** Drawn in round 2's second draw and replaced by the owner with the three
  states. The day's colour stays the only colour that names anything.
- **The states outside the Workout screen.** Today's set blocks, the Summary and History keep D65's
  rule — the day's colour says *which day*, full for done and half for to-do on Today — because
  before a workout everything on Today would be grey. C3 on the mock is open; if the owner wants
  the states there, it is a plan of its own.
- **A + cell, or − / + for sets.** Both drawn and both removed by the owner. **Skip set** in the
  ··· is the way to do fewer, and the plan's day the way to do more.
- **Words on the workout screen.** The exercise's name, the range and its unit, the button, the
  strip's figure and the next exercise's name are the words left; each is a name or a number.
  VoiceOver hears the sentences Core still writes.
- **A ring between sets** and **the warm-up's ring**: one line in SPEC each, C5.
- **Weekday letters over a cycle**; **an in-place editor for today's exercises**; **two pages for
  a superset**: the alternatives named in P6, P6 and P4.
- **The tab bar, Today's card, the calendar, the Summary, Settings**: untouched, which is what
  keeps this release to one screen and one sheet.

## Parked

- **The states everywhere** (C3): Today's blocks turning the day's colour as the workout goes
  would make Today and the workout one drawing; it needs the Summary and History to agree first.
- **A rep target per set drawn as cells on Today's card**, where the blocks are now one per set.
- **The in-place editor** for a day's exercises: swap ⇄, drop −, add +, reorder — under the
  Today's exercises card, when the JSON sheet proves too far for the common change.
- **A superset as two pages** the log slides between, if one page per block reads wrong on the
  phone.
