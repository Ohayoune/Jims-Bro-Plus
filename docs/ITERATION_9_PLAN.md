# Jimm's Bro+ — v1.8 plan (iteration 9)

The owner's note, in their words, on 2026-09-13 after looking at v1.7's Today: *"The home
screen feels empty, while the text in the home screen contributes to a feeling of sensory
overload. A recurring problem in the app is that there is too much text, and too little use of
visual cues. I want the visual cues to be a sort of guide for the user. I want the user to feel
like everything is really simple."*

Both halves of the note are one defect. On v1.7's Today the things that matter are small and
made of words — one grey sentence carrying four facts, five exercise names in a footnote — and
the one big element is the void under them. Nothing on the screen says, before you read it, how
big today is, what shape it has, or where it sits in the week.

This plan is the first pass of a rule the owner wants applied screen by screen: **no words
without a cue**. It is applied to Today here; the Workout screen is the next candidate and is
not in this plan. The mock the owner iterated on is the **"Today, Simpler"** artifact —
https://claude.ai/code/artifact/710faaab-996a-404b-8f5f-26ec66346a26 — four phone frames: an
ordinary day, a rest day, and the rest day after tapping tomorrow and after tapping Friday. S1–S3
describe every frame in words, so the plan stands without it.

## The test every element must pass

**Does this help you press Start?** If not, it goes or it recedes. Run v1.7's card through it:

| On the card in v1.7 | Verdict | Why |
|---|---|---|
| The colour square and the name | stays, bigger | the identity of the day |
| "Planned for Mon" | goes | whoever holds the phone knows the day; the strip (D70) shows it anyway |
| "Push Pull Legs" | goes | chosen once; one tap away under ··· → Change plan |
| "5 exercises" | goes | the list under it is five rows |
| "39 min last time" | stays, as a clock and a number | the one fact you cannot see otherwise |
| The five names in 13-point grey | stay, as the body of the card at a readable size | what today is |
| The chevron on the list | goes | the list itself is the tap into the day (D61's block, unchanged in what it opens) |
| The gear and the ··· | stay, drawn lighter | they were competing with the title |
| Start | stays, the only blue thing above the tab bar | the point of the screen |

So Today is: a colour, a name, a time, a strip, a list, a button. No sentence anywhere. The
empty space stays empty on purpose — a simple screen has room in it, and filling the void with
decoration would trade one noise for another.

## What the note names

- **Preattentive cues** (Ware; Tufte's *small multiples*): colour, size and position are read
  before words are. A big green square beside "Push" says *which day* before "Push" is read;
  seven small squares say *where in the week* without a date on them.
- **Dual coding** (Paivio): a fact carried by a word *and* a mark is remembered and recognised
  faster than either alone. The rule below is dual coding made mandatory.
- **Recognition over recall** (Nielsen): "Start Tomorrow's Pull" names what a tap on the strip
  chose, so nobody has to remember which square they pressed.
- **Signifiers** (Norman): the play mark says a button starts something; the moon says a day is
  for sleeping; blocks say sets. Words on their own signify only to readers.
- **Progressive disclosure** (v1.7's line, unchanged): what leaves the card is one tap away
  under ···, never gone (D56 stands).

One line this plan does not cross: **nothing untrue** (D55). Every cue is drawn from a fact the
app has — the plan's cycle, an exercise's set count, a session's duration — and never from a
guess.

## Milestones

**S0–S4, in order.** Each ends with the full suite green on the three routes, a Release build
and `tools/check_release.py`, and one commit on `v1.8-cues`, off `main` once v1.7 (its branch
`v1.7-today`, plus the owner's review D66–D68 that is in the working tree as this is written)
has merged. SPEC amendments land before the code that depends on them. Each milestone is one
decision, **D69–D71** (numbering assumes the v1.7 review ends at D68 — if it takes more, shift),
recorded in SPEC §6 and `DECISIONS_LOG.md` by the milestone that lands it. Test cases take the
prefix **TS** in `TEST_CASES.md` — every single letter is taken — and the ids below are
proposals; TEST_CASES renumbers on landing as it did for every earlier plan.

Nothing in this plan touches `Core/Persistence.swift`: no field is added to `Settings`, `Plan`
or `Session`, so no file on the phone changes shape. The day the strip shows is a view-model
value that dies with the process (S2). Nothing touches the import pipeline, the plan format, the
prompts, the fixtures, the Workout screen, the rest, the Live Activity, History, or the empty
card (no plan yet).

---

## S0 — This plan, the branch, the mock

- Branch `v1.8-cues` off `main` after v1.7 merges.
- This plan, added to `tools/build_bundle.py`'s list with the bundle regenerated in the same
  commit (the v1.6 lesson).
- The mock is the **"Today, Simpler"** artifact linked above. It is not committed:
  `docs/screenshots/` stays what the README shows.
- No app code.

## S1 — Nothing without a cue (D69)

Every line of words on Today sits beside a mark that says the same thing without words, and
anything that has no such mark and does not help you press Start leaves the card.

Top to bottom, on every day of the plan, the same zones (§4.1 is rewritten to this):

1. **The day's name**, `largeTitle`, in ink, after the day's colour square (D65) — the square
   grows to match the title's cap height. On a rest day: *Rest* after a grey square (D71).
2. **The meta row**: the seven-day strip on the left (D70) and, on the right, a clock glyph
   and **39 min** *last time* in secondary — the minutes in ink, the two words in grey, because
   39 min is a fact about last time and not a forecast (D55). While a session is open: the
   clock and **23 min** *so far*. On a rest day: a moon where the clock was, and no minutes.
   The sentence of v1.7 (*"Planned for Mon · Push Pull Legs · 5 exercises · 39 min last time ·
   step 3 of 8"*) is gone; **the step count** (D44/D53's *"step 3 of 8"*) is the one fragment
   with nowhere to go, and it moves under ··· → **Plan a progression**'s neighbour as a
   non-tappable line, *"Step 3 of 8"*, only while the plan carries a progression.
3. **The exercise rows**, the first five and *"and N more"* (D61's limit), at body size in ink,
   each with **its sets as small blocks** at the row's right edge, in the day's colour at half
   strength: four blocks, four sets. A drop set counts as one block (a set is a set). While a
   session is open, the blocks of a logged set fill to full strength, so the card shows
   progress without a fraction. The block is still one tappable row that opens the day in Plan
   detail; the chevron goes — the list is the thing to tap.
4. **At most one message line** (D61, unchanged) — the one exception to the rule: it exists to
   be read, it is rare, and it carries its own buttons.
5. **Start**, in the bottom slot, with a play mark before the words: **▶ Start Today's Push**
   (the words are D70's). **▶ Resume Push · 23 min** while a session is open.

The gear and the ··· lose their filled circles and are drawn as grey glyphs in a hairline
circle, so the title is the heaviest thing at the top of the screen.

Core: `StartCard` (`Core/HomeCard.swift`) loses `subtitle` and gains `lastDuration:
TimeInterval?`, `elapsed` for the open session, and `rows: [PreviewRow]` where a row is a
name, a set count and, mid-session, a logged count; `HomeStart.buttonTitle` is D70's. The view
draws what Core hands it and computes nothing.

SPEC: §4.1 rewritten as above with the v1.7 text preserved in italics under it, as every
earlier release did; new §6.43 *Nothing without a cue (D69)* with the table from this plan's
first section.

Tests (proposed): **TS1** the card carries no plan name, no weekday and no count — a pin that
`StartCard` has no `subtitle` and `HomeStart` produces no string containing "Planned for", the
plan's name or "exercises"; **TS2** `rows` are the first five exercises with their set counts,
and the sixth is *"and N more"*; **TS3** mid-session, a row's logged count is the engine's;
**TS4** the step line exists only while the plan carries a progression; **TS5** (device) the
card at accessibility XL: name, strip, list and Start on screen, the list scrolling (U13's
rule).

Moves: the great-grandparent, who reads the card in one glance instead of one sentence; the
coach, who sees the shape of the session in the blocks before reading a name.

## S2 — The week is the strip (D70)

Under the name, on the left of the meta row, **seven small squares: the next seven days, today
first.** Each square is its day's colour (D65), grey for a rest day. The day the card shows is
drawn slightly larger. No dates, no letters, no month, no done-marks: this is not the calendar,
which stays in History (D63 stands) — it is the page dots under a carousel, and it says *where
in the week* in a centimetre.

**Tap a square and the card shows that day**: the name, the colour, the list, the minutes and
the button follow it. The button names *when*, so nobody has to count squares:

| Square | Button |
|---|---|
| the first | **Start Today's Push** |
| the second | **Start Tomorrow's Pull** |
| any later one | **Start Friday's Legs** — the weekday, in full |
| a grey one | **No exercise Today** / **Tomorrow** / **Thursday**, disabled, with a moon before the words (D71) |

Starting from a square other than today's is what **Another day** did from the ··· in v1.7,
without the chooser: the tap is the choice. So **Another day leaves the ···**, its chooser is
deleted if the strip was its only caller, and `Gates.anotherDay` goes with its row in §6.40's
table. **Change plan**, **Plan a progression** and **Discard workout** stay where they are.
Starting a different day while a session is open keeps O36's popup (*Keep going · Finish X and
start Y · Discard X and start Y*) — the strip is just a second way in.

**Not stored.** The shown day is a value in the view model. The phone put down and picked up
again shows today; so does a relaunch. Nothing joins `Settings`.

**The strip is drawn from the first plan, and every square is live from the first plan.** This
is a deliberate exception to D64's "earned" table, taken here rather than by accident: a square
you can see but cannot tap is worse than no square, the tap is harmless (it starts nothing;
Start still does), and the button names what the tap chose. The ··· keeps its gates. If the
owner wants the tap earned after the first workout, that is one row in §6.40 and one call to
`Gates`, and the plan says so rather than pretending the choice was not made.

**Weekday plans** take the seven days from the days' weekdays. **Rotation plans** take them from
the same anchored projection the calendar draws (D37: Today and the grid can never disagree) —
`CalendarProjection.entries` already projects a month; S2 adds `CalendarProjection.next(days:
from:)` for a run of days, and `WeekStrip.days(plan:sessions:today:)` in Core hands the view
seven entries of *day index or rest*, colour resolved by `DayColour`. A plan with no
resolvable day (`nothingScheduled`) draws seven grey squares and the disabled button, and the
··· still offers Change plan.

**Colour is never the only cue.** The shown square is larger, and the button names the day in
words, so the strip works in monochrome and for anyone who cannot tell green from orange.

SPEC: §4.1's meta row; §6.40's table loses Another day's row and gains *"The strip and its
tap: from the first plan"*; new §6.44 *The week is the strip (D70)*; §6.37's second bullet
("Another day … are the ···") amended.

Tests (proposed): **TS6** seven entries, today first, on a weekday plan (Mon Push, Wed Pull,
Fri Legs → Push rest Pull rest Legs rest rest from a Monday); **TS7** the same on a rotation
plan agrees with `CalendarProjection.entries` for the same seven dates; **TS8** `buttonTitle`
for offsets 0, 1, 4 and for a rest square at each; **TS9** `HomeStart.alternatives` never
contains Another day, and `Gates` has no `anotherDay` (pin); **TS10** the shown day is not in
`Settings` — `examples/store/v1/settings.json` decodes unchanged and the decoder gains no key;
**TS11** (device) the strip at accessibility XL wraps nothing and stays one row; **TS12**
(device) tap Pull on a Tuesday, background the app, return: the card still shows Pull; kill
and relaunch: it shows Tuesday.

Moves: the five-year-old, who taps a colour and gets that day; the great-grandparent, who
sees the week without a calendar.

## S3 — A rest day says rest (D71)

On a rest day the card says rest, and it says it in marks before words:

1. A grey square and **Rest** as the title.
2. The strip with its first square grey and large; the **moon** in the meta row where the
   clock would be, and no minutes.
3. In the body, where the list would be, **three blue z's rising to the right** — the system's
   `zzz` symbol, in the accent, centred in the card's empty half. Blue because it is the one
   thing on the card that says *do something*: tap the strip.
4. The button, disabled: a moon and **No exercise Today**.

This **reverses D57's rule on Today** — since v1.6 the card on a rest day headlined the next
workout ("Lower", *Planned for Thu*, **Start Lower**), because "Rest day" and "early" were
schedule-speak to someone standing in a gym. The strip is why the reversal is safe: the next
workout is one tap away on a square that is its colour, and the button then says **Start
Tomorrow's Lower**. Someone standing in a gym on a rest day taps once. Someone on the sofa sees
the truth. D57's rule stays for everything else it covered (the notification permission at the
first Log set, the intro, the unit on review, Start here).

`HomeStart.current`'s `.restDay` case keeps its payload (the next day's index, name, weekday
and distance) — the strip needs it — and the card it produces changes: no target for the
button, `isRest` true, `rows` empty. A missed workout (D37) still speaks on a rest day: *"Push
was due Monday"* with **Do it now**, which starts it exactly as before.

SPEC: §4.1's rest-day sentences; §6.29 (D57) gains a v1.8 note that its Today rule is
superseded by §6.45; new §6.45 *A rest day says rest (D71)*, with the reversal and the reason.

Tests (proposed): **TS13** on a rest day `StartCard.target` is nil, `isRest` is true, `rows` is
empty and `buttonTitle` is *No exercise Today*; **TS14** tapping the next workout's square on a
rest day yields that day's `target`, rows and *Start Tomorrow's …* / the weekday; **TS15** a
missed workout on a rest day keeps **Do it now** and its target; **TS16** (device) the z's and
the moon in light and dark, and VoiceOver reads the card as *"Rest. No exercise today. Seven
days: today rest, tomorrow Pull, …"*.

Moves: everyone who opened the app on a rest day in v1.6 and v1.7 and read *Planned for Thu*
in grey under a big **Lower**.

## S4 — Docs, checklist, bundle, screenshots, 1.8

- SPEC: the amendments above consolidated; §4.1 reads as S1–S3 with the *(v1.7 …)* italics
  under each changed rule.
- `TEST_CASES.md`: the TS rows, renumbered as they landed. `DEVICE_CHECKLIST.md`: a **v1.8
  rows** section (TS5, TS11, TS12, TS16, and Today on a rest day at accessibility XL).
- `BUILD_STATUS.md`; `DECISIONS_LOG.md` (D69–D71, one line each, and the D57 reversal named as
  a reversal); the v1.8 paragraph in `CLAUDE.md` and `AGENTS.md`.
- README: `today.png` retaken (the card with the strip and the blocks); a second capture is not
  added — the landing section stays two screenshots.
- `Core/Introduction.swift` (D47): its pages are pinned to real control names; a page that names
  **Another day** or *Planned for* changes with them (as this is written, none does — the pin
  test says so on landing).
- Version **1.8** on both targets; the bundle regenerated; Release build and `check_release.py`
  green.

---

## What this plan deliberately does not do

- **The Workout screen.** The same rule applied there is the next pass, planned after this one
  ships and the owner has lived with Today.
- **The empty card** (no plan yet): it is the first five minutes (D57) and its words were
  chosen for a stranger; it keeps them.
- **Done-marks in the strip.** A filled square for a day already trained this week is true and
  cheap, but it is a fact about the past on a screen that is about now; History has it. Parked.
- **A day from another plan on the strip.** Other plans on the strip is where the overload would
  come back; a day from another plan stays behind ··· → Change plan.
- **Letters under the squares** (M T W T F S S): considered and rejected because the button
  names the day, and seven letters are seven more words.

## Parked

- **One block per row.** If five rows of set-blocks read as noise on the phone, the fallback is
  one square per row in the day's colour — a bullet that cues without counting. Decide on the
  device, not in the mock.
- **Blocks that fill in History's rows** — the same mark, on the session row, showing sets
  done of sets planned. Belongs to History's own pass.
