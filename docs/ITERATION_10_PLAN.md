# Jimm's Bro+ — v1.9 plan (iteration 10)

The owner's notes, on 2026-09-14 after living with v1.8's strip, in their words: *"After finishing
another day's workout today, [it] should shift today's colour to the colour of the other day
(without changing the plan itself), while keeping a small grey dot below today … a slowly pulsing
yellow outline of another day, which indicates that there is a question … The three buttons up top
should bring two options; change plan, and change exercises … The change plan page should have each
plan's squarishes … My goal is to have the option to constantly interact with the app through JSONs
in different points, with JSONs that only change a small part of the total plan."*

Three things under the notes. **First**, a rotation today re-anchors the moment any workout
finishes (D37): do Wednesday's Legs on Monday and tomorrow becomes whatever follows Legs, and the
whole week slides. The owner calls that *changing the plan*. What they want instead is a **swap**:
an override on two dates, the pattern untouched, and a question on the strip about the day whose
workout was taken. **Second**, the ··· and the Plans list are asked to speak in the strip's language
— a square for a day, a row of squares for a plan — so choosing a plan or a day is a tap on a
colour, which is D69 carried past Today. **Third**, the JSON sheet, which D43 built once for every
size, is asked to be a place you go on purpose: named, pre-filled, and honest about where the text
lands.

The requirements were settled in two rounds of questions (1–17 in words, 18–30 as drawings) on the
**"Swapping Days"** artifact — https://claude.ai/code/artifact/37184c95-17a2-4bf3-9bbd-d7a1640d016b —
eight phone frames on one example plan. Q1–Q6 describe every frame in words, so the plan stands
without it. Where the owner left a choice to the plan (Slide, the JSON points) the choice is made
below and named as the plan's.

## The example this plan speaks in

Push Pull Legs, a rotation of seven — Push · Pull · Legs · Rest · Push · Pull · Legs — anchored so
Monday is Push. Push is green, Pull orange, Legs purple (§6.41). Today is **Monday 14 September**;
the plan expected Push; the owner tapped Wednesday's square and finished **Legs**.

## Milestones

**Q0–Q7, in order.** Each ends with the full suite green on the three routes, a Release build and
`tools/check_release.py`, and one commit on `v1.9-swaps`, off `main` at v1.8 (d9bab05). SPEC
amendments land before the code that depends on them. Each milestone is one decision, **D72–D78**,
recorded in SPEC §6 and `DECISIONS_LOG.md` by the milestone that lands it. Test cases take the
prefix **TQ** in `TEST_CASES.md` (every single letter is taken; TS was v1.8's) — the ids below are
proposals, and TEST_CASES renumbers on landing as it did for every earlier plan.

**This plan touches the on-disk contract once**, in Q1: one new file, `swaps.json`, beside
`plans.json`. No field joins `Settings`, `Plan` or `Session`; `examples/store/v1/` gains a frozen
`swaps.json` and a backup that carries one, and keeps the backup that does not. Nothing touches the
import pipeline's rules, the plan format's fields, the fixtures, the prompts, the Workout screen, the
rest, the Live Activity, or what Today shows while a session is open (the owner's 11). The calendar
in History is not redrawn (the owner's 9): it reads the same projection, so a swapped day shows
there as what it now is, and nothing else changes on it.

| Milestone | Decision | Lands |
|---|---|---|
| Q0 | — | this plan, the branch, the mock |
| Q1 | D72, D73 | the swap in Core: `DaySwap`, `swaps.json`, the projection, completion, missed; Slide |
| Q2 | D74 | the swap on Today: the dot, the ring, the long press, the question block |
| Q3 | D75 | the ···: two items with symbols; progression leaves Today's menu |
| Q4 | D76 | Change *day*'s exercises: this plan, other plans, a day just for that date |
| Q5 | D77 | the JSON sheet, redone at every point |
| Q6 | D78 | Plans: the list with a circle, the plan's page with the cycle |
| Q7 | — | docs, checklist, bundle, 1.9 |

---

## Q0 — This plan, the branch, the mock

`docs/ITERATION_10_PLAN.md` (this file) on `v1.9-swaps`, the file added to `tools/build_bundle.py`
and the bundle regenerated in the same commit (CI checks it), and the paragraph in `CLAUDE.md` and
`AGENTS.md` that introduces v1.9 — as S0 did for v1.8, ending *"Q0 is written; nothing else is
built"* until Q7 rewrites it. The mock stays an artifact; nothing is copied into the repo but the
link above.

## Q1 — A day swapped, not a plan changed (D72), and Slide (D73)

**The rule.** When a workout finishes on a date the active plan's pattern expected a different
day — or rest — the plan is not moved. Two dates are written down instead:

- **today**: what the pattern said (*Push*) and what happened (*Legs*);
- **the day whose workout was taken** — the next date the pattern projects Legs, Wednesday —
  what the pattern said (*Legs*) and, **applied at once**, the default: *today's* day, Push.
  This date carries a **question**, open until answered, gone once the date is past.

Nothing in `Plan` changes: not the cycle, not `cyclePosition`, not `cycleAnchor`. D37's line *"the
pattern moves only when a workout finishes"* is amended to *"…when the workout it expected
finishes"*: `PlanSchedule.advance` (`Core/PlanLibrary.swift`) runs only when the finished day is
the **pattern's own** day for that date — a refresh of the anchor that changes nothing on the grid.
A finished day that matches the date's *swap* (Push on Wednesday, after the swap) moves nothing and
writes nothing: it is what the date said. A finished day that matches neither writes a new swap.

**The answers.** The question offers, in this order, as `SwapQuestion.options`:

| Option | Wednesday becomes | Then |
|---|---|---|
| **Rest** | rest | Legs is not repeated; Push does not happen this week, and the app says nothing about it (the owner's 22) |
| **Push** — *today's* day, the default | Push | a true swap; nothing is lost |
| **Legs** — keep | Legs | Legs twice this week, Push not at all; the app says nothing |
| **Slide** — rotations only (D73) | what the pattern says once it carries on from Legs | Tuesday Rest, Wednesday Push, Thursday Pull, Friday Legs … |

Two of them merge: when today was a rest day, *today's* day **is** rest, and the block offers Rest
and Keep (and Slide). When today's own day was already done today before the off-day workout, the
*today's* option is not offered either — today's colour is taken — and the default is Rest (the
owner's 8).

**D73 — Slide carries on from the workout you did.** The owner asked which of two readings, and
whether both; the plan chooses one, because two slides is one feature too many. Slide is D37's
re-anchor, applied when chosen rather than when the workout finished: `PlanSchedule.advance` for
Legs on Monday, so the pattern continues *after Legs* — Rest, Push, Pull, Legs — which is what the
app did in v1.8 after every off-day workout. The other reading (everything one day later: Push,
Pull, Legs, Rest from Tuesday) differs only in where this week's rest falls, and both weeks agree
from the next one on. Slide is offered on **rotations only**: a weekday plan's days are pinned to
weekdays, and there is nothing to slide. A slide remembers the position and anchor it replaced
(`slideUndo`), so reopening the question and choosing otherwise puts them back; while the question
is open, that is the only way the anchor moves.

**The type.** `Core/DaySwap.swift`:

```swift
struct DaySwap: Codable, Equatable, Identifiable {
    enum Slot: Codable, Equatable {
        case rest
        case day(name: String)                 // a day of the active plan, by normalised name (§6.9)
        case borrowed(planId: UUID, name: String)   // Q4: a day of another plan
        case own(Day)                          // Q4: a day written just for this date
        case slide                             // D73: no override; the re-anchored pattern decides
    }
    var id: UUID
    var planId: UUID          // the active plan when it was written
    var date: Date            // start of the local day it is about
    var original: Slot        // what the pattern said for that date: .rest or .day
    var replacement: Slot     // what the date is now
    var askedOn: Date?        // the date whose off-day workout raised it; nil when chosen from Q4's picker
    var answered: Bool        // false: the ring pulses; true: it is faint
    var slideUndo: SlideUndo? // the cyclePosition and cycleAnchor a slide replaced
}
```

Identity — `id`, `planId`, `date`, `original`, `replacement`, `answered` — is required; `askedOn`
and `slideUndo` are optional (§8.2's rule). A day is named, not indexed, so a plan whose days are
reordered keeps its swaps and a renamed day loses its swap the way it loses its colour (§6.41). A
`.day` whose name no longer exists resolves to `.none` in the projection, as a dead cycle entry
does (§6.12). One swap per date per plan; writing a date that has one replaces it; a replacement
equal to the original deletes it.

**Where it lives.** `swaps.json` in Application Support, a `VersionedFile<SwapsPayload>` beside
`plans.json` (`Store/StoreFiles.swift`), read by `Store.load` into `StoreSnapshot.swaps`, written by
`Store.saveSwaps`, set aside when unreadable like every other file (§8.3) — and **a missing file is
no swaps**, so v1.8's phones open without a word. `PlanLibrary` holds `swaps: [DaySwap]` beside
`plans` and `sessions`; deleting a plan deletes its swaps; Delete all data removes the folder as it
does. The backup (§8.5) gains an optional `swaps` key: a backup without it restores with none, and
`examples/store/v1/` freezes a `swaps.json` the app wrote and a backup that carries one, beside the
v1.7 backup that does not. Sessions do not change: the done day's session is the ordinary one.

**The projection reads swaps.** `CalendarProjection.entries`, `next(days:from:)` and
`week(containing:)` (`Core/CalendarProjection.swift`) take `swaps: [DaySwap]` with no default, so
no caller can forget them and the compiler is the pin. For a date in the future (or today, unfinished)
with a swap for the active plan: `.rest` → `.rest`; `.day(name)` → `.projected(planId:dayIndex:)`
by name; `.borrowed` → `.projected` with the *other* plan's id and index (the case already carries a
plan id — nothing new for a borrowed day); `.own(day)` → a new `DayEntry.own(Day)`; `.slide` → the
pattern, which the slide already re-anchored. Past dates keep D37's rule: `.completed` or `.none`.
`PlanSchedule.entry(_:on:)` and `next(_:today:)` read the same function, so Today's card behind the
first square honours a swap made for today from Q4's picker. `HomeStart.current` reads
`library.swaps`; the History calendar passes them too, and draws `.own` as a planned day with no
colour, in ink — nothing else on the grid changes (the owner's 9).

**Completion, exactly.** In `PlanLibrary.completeSession()`, after the session is appended, for a
session of the active plan on date *d* with day *X*: let *base* be the pattern's slot for *d*
(without swaps) and *slot* the projected slot for *d* (with swaps).
1. *X == base* → `PlanSchedule.advance` as today; a swap for *d* whose replacement is *X* stays.
2. *X == slot*, *X ≠ base* → nothing moves, nothing is written.
3. otherwise → write *d*: `original: base, replacement: .day(X), askedOn: nil, answered: true`
   (unless today's base day was finished on *d* already, in which case *d* keeps what it has); and
   if *X* is a day of this plan, find the next date within the horizon (§6.12, 62 days) whose
   *projected* slot is *X* and write it: `original: .day(X), replacement: today's option (base, or
   .rest), askedOn: d, answered: false`. No such date within the horizon → no question, only *d*.
Discarded sessions write nothing. A session of another plan writes nothing (the owner's 8). A
weekday plan follows the same three cases with *base* from its weekdays.

**Missed** (`PlanSchedule.missed`) reads the projected slots, so Monday's Push, moved to Wednesday,
is not "due Monday"; a Wednesday Push not done by Thursday is *"Push was due Wednesday"*, and its
**Do it now** starts the swapped day. A date whose replacement is `.rest` is never missed. A missed
`.own` or `.borrowed` day is named by its own name.

**Answering.** `PlanLibrary.answer(swap: UUID, with: Slot)` sets `replacement` and `answered:
true`; `.slide` also calls `advance` for the done day on `askedOn` and stores `slideUndo`; leaving
`.slide` restores it first. `AppModel.answerSwap(_:with:)` persists `swaps.json` and, for a slide,
`plans.json`. The question is reachable while `date` is today or later; past dates are history.

**What the strip gets.** `WeekStrip.Square` gains four facts:
`original: DayColour?` with `hasDot: Bool` (a date whose slot is not the pattern's; the dot is the
pattern's colour, grey when the pattern said rest), `outline: Bool` (a borrowed or own day, Q4),
`ring: Ring` (`.none`, `.asking`, `.answered`), and `question: SwapQuestion?` on the shown square's
card. `spoken` reads *"Wednesday, Push, question"* while the ring asks. `WeekStrip.days` takes
`swaps:`.

SPEC: §6.8's completion bullet and §6.12's D37 paragraph amended (*"the workout it expected"*, and
a swap where a re-anchor was); new §6.46 *A day swapped, not a plan changed (D72)* with the table
above and the three completion cases, and §6.47 *Slide carries on from the workout you did (D73)*;
§8.1's file list gains `swaps.json`, §8.5's backup gains `swaps`; §6.41's "derived, never stored"
gains the sentence that a swap is stored and a colour still is not.

Tests (proposed): **TQ1** Legs on a Monday expecting Push writes two swaps, Wednesday's answered
false with the default Push, and `cyclePosition`/`cycleAnchor` unchanged; **TQ2** the projection
for Monday…Sunday reads Legs (completed), Pull, Push, rest, Push, Pull, Legs; **TQ3** the same
workout on a Thursday rest day: Thursday's original is `.rest`, the question's default is `.rest`,
and its options are Rest, Keep, Slide; **TQ4** Push already done Monday, then Legs: Monday keeps
its Push, Wednesday's options are Rest and Keep (and Slide), default Rest; **TQ5** each answer's
projection — Rest, Push, Legs — and that Keep or Rest raise no missed message on Tuesday; **TQ6**
Slide re-anchors exactly as `advance` would have on Monday, `slideUndo` holds the old values, and
answering Push afterwards restores them; **TQ7** Push on Wednesday after the swap moves nothing
and writes nothing; Push on Monday, as expected, calls `advance`; **TQ8** a session of another
plan, or a discarded one, writes nothing; **TQ9** the missed rule: no "Push was due Monday" after
the swap; "Push was due Wednesday" on Thursday when the swapped Push was not done; **TQ10**
`swaps.json` round-trips, a missing file is no swaps, an unreadable one is set aside, the frozen
`examples/store/v1/swaps.json` decodes, the v1.7 backup restores with none and the new one with its
swaps, and deleting a plan deletes its swaps; **TQ11** weekday plan: Legs on Monday (a Push day),
Friday's Legs becomes Push, no Slide offered; **TQ12** (pin) `CalendarProjection`'s three functions
have no default for `swaps`; **TQ13** a day whose name left the plan projects `.none`, and the
past keeps D37's rule.

## Q2 — Today shows it (D74)

The marks, as drawn on the mock's first three frames, all from Core facts (D69):

1. **The dot.** Under a square whose day is not the pattern's, a 5-point dot in the pattern's
   colour — Push green under Monday's Legs — and grey when the pattern said rest. One rule for a
   swap the workout made and one Q4's picker made: *this day was something else*.
2. **The long press** on such a square: a small callout, the pattern's square and *"was Push"*
   (or *"was rest"*). No double tap — it fights the single tap and VoiceOver's activate gesture.
3. **The ring.** A yellow outline on the date that carries a question, pulsing slowly (2.4 s) while
   unanswered, **still under Reduce Motion**, and faint and still once answered, until the date is
   past. Yellow is the warning colour (§6.41) and no day's; a question is the one other thing that
   may wear it. The ring is not a colour alone: the block beneath says the question in words, and
   VoiceOver reads the square as *"Wednesday, Push, question"*.
4. **The question block**, on the ringed square's card, where the rows would be: the heading
   *"Wednesday's Legs is done. Make Wednesday:"* (*"Sunday's Legs is done. Make Sunday:"* on a
   rest-day swap), then the options as **large squares with their word beneath** — Rest · Push ·
   Legs — the chosen one marked with a check, and beneath them, on a rotation, the **Slide** row:
   an arrow, three small squares for that day and the two after it as Slide would make them, an
   ellipsis, and the word. **The button follows the marked option** — *▶ Start Wednesday's Push*,
   *☾ No exercise Wednesday*, *▶ Start Wednesday's Legs* — so the choice is in words as well.
   One tap chooses and closes; the ring turns faint; the ordinary card returns. **Long press** on
   the square brings the block back with the current choice marked.
5. The card's title is what the day now is (*Push*, green); the meta row keeps its clock or moon
   for that day; the message line (§4.1's fourth zone) is not the block's and keeps its priority.

Nothing else on Today moves. Today's own square after an off-day workout is what §6.44 already
says — the done workout's colour — now with the dot. The rest card (D71), the empty card, Nothing
scheduled and the card while a session is open are untouched.

Core: `SwapQuestion` (`Core/DaySwap.swift`) — `heading`, `options: [Option]` (each `slot`,
`colour: DayColour?`, `word`, `isChosen`), `slide: SlidePreview?` (three `DayColour?`), and
`HomeStart.question` on the shown square's card, with `buttonTitle`, `buttonMark` and
`buttonEnabled` following the chosen option through `WeekStrip.buttonTitle`. The view
(`WeekStripView`, `HomeView.swift`) draws the dot, the ring and the callout, and a `SwapQuestionView`
draws the block; neither decides anything.

SPEC: §4.1's zones 2 and 3 amended (the dot, the ring, the block in the rows' place); §6.44 gains
the dot, the ring and the long press; new §6.48 *Today shows the swap (D74)* with the five points
above; §6.40's table records the dot, the ring and the block as facts, not controls (ungated).

Tests (proposed): **TQ14** `WeekStrip.days` after TQ1: Monday `hasDot` with `original` green,
Wednesday `ring == .asking`, the rest plain; after answering, `.answered`; on Thursday, none;
**TQ15** `SwapQuestion` words for a workout day and a rest day, and the slide preview's three
colours agree with the re-anchored pattern; **TQ16** the shown card's button follows each option;
**TQ17** `spoken` reads "Wednesday, Push, question" while asking; **TQ18** (device) the ring pulses
on the phone and is still with Reduce Motion on; **TQ19** (device) long press on today's square
shows "was Push"; long press on an answered square reopens the block; **TQ20** (device) the block
at accessibility XL keeps its four options on screen and the button in the bottom slot.

## Q3 — The ··· speaks in squares (D75)

On a day's card, with no session open, the ··· holds **two items and nothing else**:

| Item | Symbol | Opens |
|---|---|---|
| **Change plan** | one glyph made of the plan's cycle, seven tiny squares in their colours | the Plans list (Q6) |
| **Change Wednesday's exercises** — the shown day, named | the day's square | Q4's picker |

**Progression leaves Today's menu** — *"progression will just be in history"* (the owner's 23):
**Plan a progression** and the *"Step 3 of 8"* line go, `HomeStart.offersProgression`,
`Alternative.planProgression`, `stepLine` and `Gates.planProgression` with them (§6.40's table
loses the row, and T21's count goes from five to four). History's Progression row (D67) is the one
way, and Today's message line still says when a progression has run its course, with **Plan the
next one** — a message is not a menu item. D50's *offer* on Today is the part reversed; its words
in `PromptText` and the Copy prompt are not.

**The rows are no longer tappable** (the owner's 13): the exercise block is the preview and the
menu is the way to the day — `HomeStart.exerciseLabel` loses "Opens Push" and the block loses its
button. **While a session is open** the menu is v1.8's — Change plan and Discard workout — and
nothing about the running day changes from Today (the owner's 11).

**The symbol.** `CycleSymbol` in `DaySquare.swift` (compiled into both targets, as `DaySquare` is)
draws `[DayColour?]` as one image: one row, squares of equal size, a cycle longer than fourteen
drawn as its first fourteen and a trailing mark. Core hands the colours: `HomeStart.Alternative`
becomes `.changePlan(cycle: [DayColour?])`, `.changeExercises(dayName: String, colour: DayColour?)`
and `.discardWorkout`. The menu is still a SwiftUI `Menu` whose items are `Label`s with the image
in `.renderingMode(.original)`. **If the simulator shows the symbol in one grey**, iOS has decided,
and the ··· becomes a small sheet of our own with the same two rows — the mock said so, and the
landing commit records which it was.

SPEC: §4.1's ··· paragraph rewritten; §6.26's D50 offer marked reversed on Today; §6.40's table;
new §6.49 *The ··· speaks in squares (D75)*; `Core/Introduction.swift`'s pages checked for a page
that names **Plan a progression** or tells the reader to tap the list (the pin test says).

Tests (proposed): **TQ21** `alternatives` on a day's card are exactly Change plan (with the plan's
cycle colours) and Change *day*'s exercises (with the shown day's name and colour), in that order;
with a session open, Change plan and Discard workout; **TQ22** (pin) `HomeStart` has no `stepLine`
or `offersProgression`, `Alternative` no `planProgression`, `Gates` four functions, and §6.40's
table matches; **TQ23** `CycleSymbol`'s colours are `DayColour` per cycle entry and a 31-day cycle
draws fourteen and the mark; **TQ24** (device) the menu's symbols show their colours — or the
fallback sheet does.

## Q4 — Change *day*'s exercises (D76)

**The picker**, pushed from the ···, titled *"Change Wednesday's exercises"* with the line *"For
Wednesday 16 September only. The plan does not change."*: this plan's days first, under its name
(*Push Pull Legs · this plan*), each a square and a name; then every other plan under its own name,
its days the same way (a section only when there are other plans); and last, one row —
**"Write a day just for Wednesday"** — the owner asked for better words than *custom temporary*.
A tap writes a swap for the date (`askedOn: nil, answered: true`) and pops to Today, whose card
now shows it; the pattern's own day removes the swap.

- **A day of this plan** → `.day(name)`.
- **A day of another plan** → `.borrowed(planId:name:)`. It keeps its own plan's colour, and the
  strip draws it **outlined in that colour** rather than filled (the owner's 24): Upper is green
  in Upper Lower as Push is here, and the outline says *not from this plan*. Its session is that
  plan's session — `planId` the other plan's, coloured by it in History — and it moves neither
  plan's anchor. This reverses v1.8's "a day from another plan stays behind Change plan", on the
  owner's ask, and the day is one date, not a plan on the strip.
- **A day just for Wednesday** → Q5's sheet with a day template; Save reads **Use for
  Wednesday**; the text goes through `PlanEdit.fragment(_:as: .day)` and the importer, so a day the
  app would refuse to import is refused here with the same sentence, and a nameless one is named
  *"Wednesday's own day"*. The swap holds the `Day` itself (`.own(day)`); nothing joins the plan.
  The strip draws it **outlined in ink**, with no colour, and `HomeStart.rows` are its exercises.
  Its session is the active plan's with the day's own name — a name no plan has, so History draws
  it grey, as it draws a renamed day (§6.41) — and `advance` ignores it (§6.8: not in the cycle).

`AppModel.startDay` gains a way to start a `Day` that is in no plan (`startOwnDay(_:on:)`, through
`PlanLibrary`), with D17's switch popup as every start has. Nothing on the Workout screen knows the
difference.

SPEC: §4.1's ··· (the picker as the second item's destination); §6.44's "a day from another plan"
line reversed; new §6.50 *Change a day's exercises (D76)* with the three kinds and their marks;
§6.41's four places gain the outline as a fifth mark that says *not this plan*, still *which day*.

Tests (proposed): **TQ25** the picker's sections: this plan first, others by name, the own-day row
last, and no others section with one plan; **TQ26** choosing Pull writes `.day(Pull)` answered, and
choosing Legs (the pattern's own) deletes the swap; **TQ27** a borrowed day projects
`.projected(otherId, index)`, its square is outlined in its plan's colour, and its finished session
moves neither anchor; **TQ28** an own day: a fixture day pasted with prose around it is accepted,
one with no exercises is refused with the importer's sentence, the swap holds the `Day`, the square
is outlined with no colour, and its session's name gives no colour; **TQ29** (device) the outlined
square beside filled ones at the strip's size reads as a square, in light and dark.

## Q5 — The JSON sheet, redone (D77)

`JSONFragmentSheet` is kept — one sheet for every size (D43) — and given four things it lacked, at
**every point where a fragment is edited**: an exercise in the plan, a day in the plan, exercises to
add, a day to add, and Q4's day just for a date. (The whole plan keeps the Add plan screen and a
progression its own; a chatbot prompt per fragment is parked below.)

1. **Named.** The title says what the JSON is — *One exercise*, *One day*, *Exercises to add*, *A
   day to add*, *A day just for Wednesday* — and a line beneath says where it lands and for how
   long: *"Bench Press, exercise 3 of 5 in Push"*, *"Added at the end of Push"*, *"For Wednesday 16
   September. Not saved to Push Pull Legs."*
2. **Pre-filled.** An edit opens on the current text, as now; an addition opens on the smallest
   valid example — one exercise, one day of one exercise — so a change is one number and a paste
   replaces the box.
3. **The error at the line.** The pipeline's path (`days[1].exercises[2].sets[0].reps`) is found
   in the text and that line is marked, with the sentence beneath it in words (*"reps: write a
   number, or a range like 6-8"*). `Core/JSONLocator.swift` walks the text as JSON, tracking
   offsets, and answers the path's line or nothing — when it finds nothing (prose around the JSON,
   a fence, a shape it cannot follow) the sentence still shows under the box and no line is
   marked. It never marks the wrong line.
4. **Save says its effect.** *Replace Bench Press*, *Replace Push*, *Add to Push*, *Add to Push Pull
   Legs*, *Use for Wednesday* — never a bare Save.

Core: `JSONPoint` (`Core/JSONPoint.swift`) — `kind`, `title`, `place`, `template`, `saveTitle` —
built from the plan and the target; `FragmentTarget` (`JSONFragmentSheet.swift`) becomes a thin
map to it, and the sheet takes a `JSONPoint` and the commit. The Paste button, the fence and prose
leniency, and the refusal that keeps the text (§6.19) stay.

SPEC: §6.19 gains the four points and the locator's honesty rule; §4.3's JSON bullet names the new
titles.

Tests (proposed): **TQ30** every `JSONPoint` template parses through the pipeline as its own kind;
**TQ31** titles, places and save words for each of the five points on the example plan; **TQ32**
`JSONLocator` finds the line for `days[0].exercises[1].sets[0].reps` in a rendered day, for
`exercises[2].weight` in a rendered plan, and answers nil for a fenced fragment with prose and for a
path into a missing key; **TQ33** (device) the marked line and the sentence at accessibility XL.

## Q6 — Plans: the list with a circle, the page with the cycle (D78)

**The list** (`PlansView.swift`), each row: a chevron at the **left**, the plan's `CycleSymbol`, its
name, and beneath the name **how often** — *6 days a week* for a seven-day cycle or a weekday plan,
*3 days every 10* otherwise, *every day* for a cycle of one; and at the **right** a circle. **The
circle marks; the button confirms** (the owner's 15): tapping a circle marks it and a button appears
in the bottom slot reading **Use Upper Lower**; tapping the button makes the plan active and pops to
Today, which now runs it. With the active plan's own circle marked there is no button. Tapping the
row anywhere but the circle opens the page. **Use this plan** leaves Plan detail's ··· — this is the
one way (D66's rule) — and Add plan, swipe to delete with its alert, and the import's own "Use this
plan" (§6.8: importing asks) stay. `PlanText.howOften(_:)` in Core says the words.

**The page** (`PlanDetailView.swift`), top to bottom:

1. Name; *kg · repeats every 7 days* as now.
2. **The cycle as squares**, in order, each with its name beneath and the current position marked
   in ink — where D59's chips were; `RepeatBlock.chips` becomes `RepeatBlock.squares(_:)` handing
   `(colour, name, isNow)`. Weekday plans show Mon…Sun with the name or *rest* beneath, as now.
3. **The whole cycle again as rows**, repeats included (the owner's 16): a square and a name, each
   **closed until tapped**; a rest entry is a row with a grey square and nothing to open. An open
   day is today's section, unchanged — the exercise rows and their sheet, Edit mode's reorder and
   delete (D29), **Add exercise**, the bordered **Start**, and the header's menu (Rename day ·
   Duplicate day · Add exercise · Edit day as JSON). The exercise line keeps v1.8's words. The
   same day opened twice shows the same exercises twice.
4. The ··· keeps Rename, Copy JSON, Edit JSON, Add day from JSON, Delete — and loses Use this plan.

Nothing Plan detail can do is removed (the owner's 30); only the shape changes. `PlanPage.rows(_:)`
in Core lists the cycle's entries as rows, so the view opens what it is handed.

SPEC: §4.2 rewritten (the row, the circle, the button); §4.3's first bullet (squares for chips) and
its "Days" bullet (closed until tapped, the whole cycle); the ··· bullet loses "Set as active"; new
§6.51 *Plans speak in squares (D78)*.

Tests (proposed): **TQ34** `howOften` — "6 days a week" (seven-entry rotation), "4 days a week"
(weekday plan), "3 days every 10", "every day", "1 day a week"; **TQ35** `RepeatBlock.squares`
colours and names follow `DayColour` and the position; **TQ36** `PlanPage.rows` on the example is
Push, Pull, Legs, rest, Push, Pull, Legs, with the third and seventh opening the same exercises;
**TQ37** (pin) `PlanDetailView` has no Use this plan and `PlansView` has the circle and the confirm
button; **TQ38** (device) the page at accessibility XL: the squares row wraps and the open day keeps
Start on screen; **TQ39** (device) mark a circle, leave without confirming, return: nothing changed.

## Q7 — Docs, checklist, bundle, 1.9

- SPEC: the amendments above consolidated, with *(v1.8 …)* italics under each changed rule.
- `TEST_CASES.md`: the TQ rows, renumbered as they landed. `DEVICE_CHECKLIST.md`: a **v1.9 rows**
  section (TQ18, TQ19, TQ20, TQ24, TQ29, TQ33, TQ38, TQ39).
- `BUILD_STATUS.md`; `DECISIONS_LOG.md` (D72–D78, one line each, the D37 amendment and the D50
  reversal on Today named as such); the v1.9 paragraph in `CLAUDE.md` and `AGENTS.md` rewritten
  for what shipped (`docs/PRIVACY.md` names no files, so `swaps.json` changes nothing in it).
- README: no screenshot changes — the ordinary card is unchanged, and the strip's marks appear only
  after a swap.
- Version **1.9** on every target (`MARKETING_VERSION`, five places) and in `docs/APP_STORE.md`;
  the bundle regenerated (`tools/build_bundle.py`); Release build and `check_release.py` green.

---

## What this plan deliberately does not do

- **Two slides.** One rule for Slide (D73); the other reading is one line in SPEC saying why not.
- **JSON for the week's swaps, or for sets mid-workout.** The owner's 11: nothing during an active
  workout changes. The swaps have a block, not a text.
- **A chatbot prompt per fragment** ("write one exercise in this shape"). Parked, below.
- **Marks on the calendar.** The dot and the ring are the strip's; the grid shows a swapped day as
  what it now is, and nothing more (the owner's 9).
- **Colour in the tab bar, on Start, or anywhere §6.41 forbids.** The symbol and the outline are
  two more marks that say *which day*; none says *tap here*.
- **The Workout screen's no-words pass.** Still the next candidate after this one.

## Parked

- **A prompt for a fragment.** The sheet could copy a prompt asking a chatbot for exactly this
  shape — one exercise, one day — the way Copy prompt asks for a plan (`PromptText`). It is
  `docs/PROMPT.md` §6 when the owner wants it, and the sheet's third button.
- **A question that expires unanswered** could say so once, on the strip's card, the morning after.
- **Reordering the plan's days from the page** — the squares row as a drag handle.
