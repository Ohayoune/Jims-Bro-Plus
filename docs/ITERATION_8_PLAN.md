# Jimm's Bro+ — v1.7 plan (iteration 8)

The owner's note, in their words, on 2026-09-13 after living with v1.6: *"The home page gives me
sensory overload. I want the app to give the individual less choices and be more forcing in its
approach towards how we want the user to use the app. The app feels somewhat like a settings
menu."*

This plan answers that note the way iteration 7 answered *"clunky, hard to understand, hard to
get started"*. It is smaller than v1.6 and it is mostly subtraction. The mock the owner should
look at first is the **"Jimm's Bro+ Today"** artifact — https://claude.ai/code/artifact/458034b6-5f7b-4f6a-b4cc-df7a62a6bd5d — seven phone
frames: v1.6's Home beside v1.7's Today on a workout day, a rest day, mid-workout, with no plan,
with the **···** open, and History with the calendar on top. T1 describes every frame in words,
so the plan stands without it.

## What the note names

The complaint has names in the literature, and naming them says what the app is allowed to do
about it:

- **Opinionated design** (37signals, *Getting Real*): the software takes a side on how it is
  meant to be used and offers one good way, not several equal ones.
- **Progressive disclosure**: what the moment needs is on the screen; the rest is one deliberate
  step away. This is the honest form of "forcing" — fewer choices *at once*, never fewer choices
  in total.
- **One primary action per screen** (SPEC §4.0's first rule; GOV.UK's "one thing per page";
  Apple's "focus on the primary task"). The rule has been on the books since v1.1. Home stopped
  obeying it by accretion, not by decision.
- **Hick's law**: the time to decide grows with the options in view. Three small buttons under
  Start are three decisions, however quietly they are drawn.
- **Defaults and forcing functions** (Norman; Thaler and Sunstein's choice architecture): the
  default path is the recommended path, and a side path costs one more tap.
- **Progressive unlocking** (game design): a control appears when it first has something to do.
  The app does this once already, with **Plan a progression** (D50); v1.7 makes it the rule.
- **A guided flow, not a hub**: a dashboard presents peers; a flow presents the next step. Home
  is a dashboard today.

One line the plan does not cross: **deferred, never unreachable** (D56 stands). Everything
Home offers in v1.6 is still offered in v1.7 — one tap later, in one place, and only when it
applies.

## The evidence

Home on an ordinary workout day in v1.6 (`JimmsBro/Features/Home/HomeView.swift`, SPEC §4.1),
counted from the code:

| On the screen | Tappable things |
|---|---|
| Start, in the bottom slot | 1 |
| Preview · Another day · Plan a progression | 3 |
| Week / Month, and ‹ › when expanded | 1–3 |
| The seven day cells, and **Start this** on a tapped today | 7–8 |
| The tab bar | 4 |
| **Total, before any notice** | **16–19** |

Plus, when they apply: the missed-workout notice with **Do it now** and **Dismiss** (D37), *"Your
progression has run its course"* with **Plan the next one** (D44), the notifications-off
sentence (D57), and the in-progress **···** with Discard. Two headlines compete — the day's name
at `largeTitle` and **This week** — and five type sizes share the screen, down to the 9 pt labels
inside the cells. SPEC §4.1 still opens *"three things, top to bottom, nothing else"*; each of
the three grew appendages, each justified alone (D37, D44, D50, D57, D59), and the sum is a
dashboard.

Why the whole app reads as a settings menu, not only Home:

- `RootView` gives **Home · Plans · History · Settings** equal rank. Plans and Settings are
  maintenance. The daily job has one peer it deserves: the record.
- Nearly every screen is a grouped `List` with chevrons, a **···** and system text — Settings.app's
  vocabulary, used consistently (R4 asked for consistency, and got it).
- One visual register: the accent, footnotes, capsules. Nothing on any screen is coloured by what
  it *is*, only by whether it is tappable (D59).

## What "forcing" means in this app

The app decides the **order**, never the **availability**:

1. Today's workout is the screen. Everything else is one tap away, in one place.
2. A control appears the first time it has something to do, and then it stays.
3. One message at a time.
4. The accent means "tappable" and nothing else; a day's colour means *which day*.
5. Nothing on Today moves between visits: the same five zones on every day of the plan.

The three users of iteration 7, re-checked against this plan: **the coach** loses nothing and
gains one tap to Plans; **the great-grandparent** gets the one-button screen the audit asked for,
with the exercise names still in front of Start (P5); **the five-year-old** gets a colour per day
(T5) — the first thing on any screen that is not a word.

## Milestones

**T0–T6, in order.** Each ends with the full suite green on the three routes, a Release build
and `tools/check_release.py`, and one commit on `v1.7-today`, off `main` once v1.6 (pull request
#2) has merged. SPEC amendments land before the code that depends on them. Each milestone is one
decision, **D61–D65**, recorded in SPEC §6 and `DECISIONS_LOG.md` by the milestone that lands it.
Test cases take the prefix **T** in `TEST_CASES.md`; the ids below are proposals, and
TEST_CASES renumbers on landing as it did for every earlier plan.

Two milestones were the owner's call and were put to them on 2026-09-13, the day the plan was
written: **T2** (how many tabs — three readings, one recommended) is **Reading A, Today ·
History**, and **T5** (a colour per day) is **go**. Both are built in order with the rest.

Nothing in this plan touches `Core/Persistence.swift`: no field is added to `Settings`, `Plan`
or `Session`, so no file on the phone changes shape. Nothing touches the import pipeline, the
plan format, the prompts, the fixtures, the Workout screen, the rest or the Live Activity.

---

## T0 — This plan, the branch, the mock

- Branch `v1.7-today` off `main` after PR #2 merges.
- This plan, added to `tools/build_bundle.py`'s list with the bundle regenerated in the same
  commit (the v1.6 lesson: U1–U3 were red on CI until U5 did).
- The Today mock is the **"Jimm's Bro+ Today"** artifact linked above; its frames are the states
  T1 names. It is not committed: `docs/screenshots/` stays what the README shows.
- No app code.

## T1 — Today is one card (D61)

Home becomes **Today**, and Today is the day's card and nothing else. Top to bottom, on every
day of the plan, the same five zones:

1. **The day's name**, `largeTitle`, in ink: *Push*. On a rest day, the next workout's name
   (D57, unchanged).
2. **One subtitle**, the fragments that have data, in this order: *Push Pull Legs · 5 exercises ·
   48 min last time · step 3 of 8*; on a rest day, *Planned for Thu ·* in front (D57). *In
   progress · 5 of 16 sets · 23 min* replaces it while a session is open.
3. **The exercise names**, the first five and *"and N more"*, exactly as now — and the block is
   one tappable row with a trailing chevron that opens the day in Plan detail. This is
   **Preview**; the button goes. *(P5: Start is never blind.)*
4. **At most one message line**, with its own actions, chosen in this order and never two at
   once: the missed workout (*"Pull was planned for Tue."* · **Do it now** · **Dismiss**, D37) >
   the progression that has run its course (**Plan the next one**, D44) > notifications off
   (D57). Each reads as it reads today; nothing else may join the list without a decision.
5. **Start**, in the bottom slot (D59): **Start Push**, **Resume Push · 23 min**, **Start Lower**
   on a rest day.

Gone from the screen: the calendar and the activity line (to History, T3); **Preview** (the
exercise block does it); **Another day** and **Plan a progression** (to **···**); the
Week/Month control; the tapped-day line. The screen does not scroll unless Dynamic Type makes
it, and then the exercise list is what scrolls while the name, the subtitle and Start hold
(U13's rule).

**The ··· menu**, top-right of Today, is the only place the day's alternatives live: **Another
day** (the plan's other days, the existing dialog), **Change plan** (the Plans list, pushed —
see T2), **Plan a progression** while D50 offers it, and, while a session is open, **Discard
workout** with its alert (D56). Nothing in the menu is itself a confirmation.

**The empty Today** (no plans): *No plan yet* as the headline; one sentence beneath — *"Choose a
built-in plan to start today, or have a chatbot write yours."*; **Choose a plan** in the bottom
slot, opening Add plan on the built-in picker (D46, with its **Start here** badge and, one tap
back, **Create with a chatbot** and **Paste plan**); and one quiet bordered button, **Try a short
practice workout**. Two choices where there were three; the paste route is inside the sheet the
button opens, where D57 already sends the reader.

Core: `HomeStart` (`JimmsBro/Core/HomeCard.swift`) grows `message: Message?` — one value,
chosen by the priority above — and `alternatives: [Alternative]`, the ··· items in order; both
are plain data the tests pin, and the view stops deciding either. `HomeActivity.line` is kept
for History (T3).

SPEC: §4.1 rewritten as **Today**, the v1.6 text kept in italics beneath; §4.0's "one primary
action" rule gains the sentence *"Today has one; its alternatives live in one ··· and nowhere
else"*; new §6.37.

Tests (proposed): **T1** `HomeStart.message` is nil, missed, finished or notifications and
never two — one case per priority pair; **T2** `alternatives` on a one-day plan omits Another
day, on a plan with a progression omits Plan a progression, and while in progress ends with
Discard; **T3** the exercise block's accessibility label reads *"Exercises: …, and N more. Opens
Push"*; **T4** the empty card's button title is *Choose a plan* and its one link *Try a short
practice workout*; **T5** (device) Today at accessibility XL keeps the name, the subtitle and
Start visible without scrolling on the smallest supported iPhone, in every state; **T6** the
screenshot hook produces `today.png`.

Moves: the great-grandparent (one button, nothing under it) and the coach (nothing lost, one tap
to Another day).

## T2 — How many tabs (D62) — **Reading A, chosen 2026-09-13**

Plans and Settings are the reason the app reads as a settings menu from its first screen: they
sit as peers of the daily job. Three readings were put to the owner; A was recommended and
**chosen**.

- **Reading A — two tabs: Today · History.** *(recommended)* Plans is reached from Today's
  **··· → Change plan**; Settings from a gear at the top-left of Today and of History, the same
  place on both (P1: zones do not move). The tab bar then says what the app is — a workout to do
  and a record of the ones done. Trade-off: the round-trip screen is two taps from launch instead
  of one, which the coach will notice once and the stranger never will, because the intro and
  the empty Today both lead there by the hand.
- **Reading B — three tabs: Today · Plans · History**, Settings behind the gear. Keeps the
  round-trip at one tap because it is the app's premise. Trade-off: Plans keeps its rank as a
  daily destination, which it is not, and the settings-menu reading survives at reduced strength.
- **Reading C — one screen, no tab bar.** Today is the app; **···** leads to History, Plans and
  Settings. The most forcing reading, and the one the audit's great-grandparent fails: a menu is
  not a visible way out (D56), and History — the second most-used screen — would sit behind a
  glyph.

Under A: `RootView.Tab` shrinks and `applyScreenshotArguments` follows it; the
intro's `Introduction.namedControls` still resolves (*History* stays, and *Home* was never
pinned); the README's landing text stops walking four tabs; and §4.0's tab rule is rewritten:
*"Tab bar with two tabs: **Today · History**. Today's bar carries a gear and a ···,
nothing else."*

Tests (proposed): **T7** a pin test that `RootView.Tab`'s cases match SPEC §4.0's list; **T8**
every `namedControls` entry still exists by name (Y13, re-run); **T9** (device) from a clean
install, Plans and Settings are each reached in two taps from Today, and the gear sits in the
same place on both tabs.

## T3 — The calendar lives in History (D63)

The calendar was always the record's: it shows what happened and what the plan expects, and the
one thing it did for *today* — **Start this** — Today does. `CalendarView` moves, its drawing
unchanged, to the top of History: the week strip, **Month**, the tapped-day line (*"Wed 10 ·
Legs · 52 min"*, tap again for the session; *"Sat 13 · Push · planned"*; *"Sun 14 · Rest
day"*), the week's line *"2 workouts this week · 1 h 32 min"* beneath it, then Metrics, Find an
exercise, Goals and the months as now. **Start this** goes: a workout starts on Today.

When History has no sessions it still shows the strip — the plan's projection is worth seeing
on day one — with *"No workouts yet"* under it.

SPEC: §4.1's calendar and activity paragraphs move to §4.10, edited for their new home; new
§6.38.

Tests (proposed): **T10** `HomeActivity.line`'s existing cases, re-homed; **T11** the tapped-day
line for today reads *planned* and carries no button; **T12** the projection with no sessions
still lists the week's planned days; **T13** (device) History, week and month, tap a done day
twice and land on the session.

## T4 — Controls are earned (D64)

The rule, made a table. A control appears the first time it has something to do, and once shown
it stays; the one exception is already on the books (**Plan a progression** leaves when a
progression is attached, D50). No control is removed from the app by this rule; it is delayed.

| Control | Appears when |
|---|---|
| **Month** (History's calendar) | a session exists that is older than the current week |
| **Metrics**, **Find an exercise** (History) | at least one session |
| **Goals** section (History) | at least one session |
| **Another day** (Today's ···) | the plan has more than one day |
| **Change plan** (Today's ···) | at least one plan |
| **Plan a progression** (Today's ···) | as D50: every exercise on the day has a session, and no progression is attached |
| The notifications-off line (Today) | as D57: after the first **Log set** |

Settings is not gated: a switch someone goes looking for must be there (D56).

Core: a `Gates` type (`JimmsBro/Core/Gates.swift`) with one static function per row, taking the
sessions, the library and a date — pure and testable — and the views ask it rather than
counting for themselves. SPEC: new §6.39 carrying this table verbatim, so that a future control
has to add a row before it may appear.

Tests (proposed): **T14–T20**, one per row, each at its boundary (zero and one session; a
session six days old on a Monday and the same session on a Sunday); **T21** a pin test that
every `Gates` function is named in SPEC §6.39.

Moves: the stranger's first week — History with a strip and one sentence, Today with a name,
five exercises and Start.

## T5 — A colour per day (D65) — **go, chosen 2026-09-13**

Parked from iteration 7, put to the owner with this plan and **chosen**: the one addition in a
plan of subtractions. Every plan day gets a
colour by its position in the plan's day list — six colours, none of them the accent (which
stays "tappable", D59), red (destructive) or yellow (warnings): green, orange, purple, pink,
teal, indigo, the system's so they follow dark mode. It is derived, never stored; reordering days
recolours them, which is the price of not touching the on-disk contract.

The colour appears in exactly four places, all of which say *which day* and none of which say
*tap here*:

1. A small filled square before the day's name on Today (not the name itself — headers are ink,
   D59).
2. The done-day fill in the calendar, in place of the accent, and the projected day's label
   likewise.
3. The leading square on a History session row.
4. The same square before the day's name in the workout header, so the Lock Screen activity,
   which already draws the name, can carry it too (D40's compact form has room for a colour and
   nothing else).

Nowhere else. Not the Start button, not the tab bar, not a background.

Core: `DayColour.index(dayIndex:)` (`JimmsBro/Core/DayColour.swift`) returns a palette
position; the view layer owns the mapping to `Color`. SPEC: §4.0 gains *"Colour says which day;
the accent says tappable"*; new §6.40 with the four places.

Tests (proposed): **T22** six days, six positions, the seventh wraps; **T23** a pin test that
the palette names no accent, red or yellow entry; **T24** (device) the same day is the same
colour on Today, in the calendar, in History and in the workout header, in light and in dark.

Moves: the five-year-old, and everyone who has opened History and seen a column of identical
grey rows.

## T6 — Docs, checklist, bundle, screenshots, 1.7

- SPEC: the amendments above consolidated; §4.1 is *Today*; the *(v1…)* italics preserved under
  each changed rule, as in every earlier release.
- `TEST_CASES.md`: the T rows, renumbered as they landed. `DEVICE_CHECKLIST.md`: a **v1.7 rows**
  section (T5, T9, T13, T24, and Today at accessibility XL in every state).
- `BUILD_STATUS.md`; `DECISIONS_LOG.md` (D61–D65, one line each); the v1.7 paragraph in
  `CLAUDE.md` and `AGENTS.md` made past tense.
- README: the landing section's screenshots (`home.png` retired for `today.png`, `history.png`
  retaken with the calendar) and the paragraph that walks the tabs.
- Version **1.7** on both targets; the bundle regenerated; Release build and `check_release.py`
  green.

---

## What this plan deliberately does not do

- **It does not remove any route.** Every action on v1.6's Home is reachable in v1.7 in at most
  two taps; T4 delays some until they apply.
- **It does not redesign Plan detail, Add plan or Settings.** They are the app's forms and are
  allowed to look like forms. If Today, two tabs and a colour per day do not lift the
  settings-menu feeling, the next candidates are Plan detail's day rows (a coloured header per
  day, the exercises as cards) and History's session rows (the day's colour and the exercise
  names, not only "28 min · 16 sets").
- **It does not add a streak, a ring or a score.** The week line in History is the whole of the
  app's opinion about how you are doing. The owner may want more later; it is a separate
  decision, and a different kind of app.

## Parked

Carried from iteration 7, still wanting design before code:

- **A pictogram per exercise** — a name-to-symbol table is fuzzy, and a wrong picture is worse
  than none; the colour per day (T5) is the half of that idea that can be done without guessing.
- **An in-app number pad** with plate arithmetic behind the weight.
- **One big Done for a rep set**, modelled on the timed set.
- **Opening the chatbot directly**, and the *"Looks like a plan. Add it?"* banner.
- **An introduction made of real screens.**
