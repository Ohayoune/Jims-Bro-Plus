# Jimm's Bro+ — v1.5 plan (iteration 6)

The owner's notes after living with the app on the phone, in their words:

1. *"Should make the progression button clearer, currently hidden, but don't make the button
   too obvious."*
2. *"Copy prompt button should be a bit clearer. Maybe a short explanation of the mechanism."*
3. *"The progression should be by performance instead of by calendar. Maybe a legacy calendar
   increase, but should include the progression steps."*
4. *"Goals or milestones — also be a feature."*
5. *"Before progression is made there should be a history for each exercise. The first time
   using the app should also include a history."* — **not now**, by the owner's decision on
   2026-09-08 (the reading offered was a sheet of current numbers per exercise, typed, never
   counted as a workout; it is kept at the end of this file for when it is wanted).
6. *"When people first use the app there should be a welcome screen explaining how to use the
   app."* — built in v1.4 as the introduction (D47, SPEC §6.24).
7. *"Also should add an effort target feature in the plan, showing how many reps/seconds to be
   away from failure."*
8. *"Main concerns include making the JSON too big. If the JSON is too big, it might be hard
   for people on free plans to use. Realistically, people should already have a plan ready
   before pasting the JSON. Maybe include several different JSON entrances and a master
   JSON."*

Milestones **Z0–Z6, in order**. Each ends with the full suite green on the three routes, a
Release build and `tools/check_release.py` (v1.4's rule), and one commit on
`v1.5-refinement`, off `main`. SPEC amendments land before the code that depends on them.
Each feature is one decision, D50–D54, and one Core type that a view only renders.

Four of the notes read more than one way, and the readings lead to different builds. Each was
written up under **the reading**, with the alternative it was chosen over, and the owner chose
on 2026-09-08: achievement-based steps, a goal per exercise, the outline-then-days flow, and
no current-numbers feature for now. The milestones below are the chosen readings.

---

## Z0 — This plan, the branch, and the decisions

- Branch `v1.5-refinement` off `main` (v1.4 is merged and pushed).
- D50–D54 are written into SPEC §6 and `DECISIONS_LOG.md` by the milestone that lands them.
- No app code.

## Z1 — Clearer, not louder (notes 1 and 2, D50)

Two controls the owner could not find, and one mechanism the app never explains.

- **The Progression row** in Plan detail stays a row — no badge, no button — but says what it
  is: a second line under "Progression", *"A chatbot plans your next steps from what you have
  lifted"*, and the accent chevron that every other row that opens a screen has. Home's start
  card gains one quiet footnote link, **Plan a progression**, in the row that already holds
  Preview and Another day, shown only when the plan has no progression and every exercise on
  the card's day has a logged session to plan from. It goes away the moment a progression is
  attached. That is the whole of "not too obvious".
- **Copy prompt**, in Add plan and in Progression, becomes the accent-filled small button its
  step deserves, and the step's own text explains the mechanism once: *"Copy the prompt. It
  tells the chatbot the exact format the app reads, so its reply pastes straight back in."*
  The section's footer says the other half: *"The app never talks to the chatbot itself; you
  carry the text both ways."* No new screen; two sentences where the buttons are.
- Tests: the sentences are Core strings (`PromptText`), so the intro's pin (Y13) can name them
  and a rename cannot leave the intro behind; Home's link is a `HomeStart` field with a rule.

## Z2 — An effort target (note 7, D51)

"How many reps or seconds to be away from failure." `PLAN_FORMAT.md` §5 kept RPE and RIR out
of the format on purpose — "put them in notes" — and the owner has now asked for exactly this
one, because it changes how a set is done rather than describing it.

- **The field**: `inReserve`, a whole number 0–20, at exercise or set level with the usual
  exercise-level default; `rir` accepted as an alias. It means *reps* in reserve on a rep set
  and *seconds* in reserve on a timed set, which is why one field and not two. Anything else →
  `E_IN_RESERVE_INVALID`. Missing → none, and nothing is shown. `SetTarget.inReserve`,
  optional in `Persistence.swift`; the session snapshot carries it (D7).
- **Where it shows**: the workout card, under the target, as *"2 in reserve"* — body text,
  not a number you act on (§4.0); `TargetText.summary` in Plan detail and the review adds
  "· 2 in reserve"; the exercise edit sheet (D29) gets a stepper for it; the JSON template
  (D43) includes it blank.
- **The prompt** gains one rule: *"inReserve: how many reps (or seconds, for holds) short of
  failure each set should stop, e.g. 2. Omit when I do not say."* `PROMPT.md` and the pin
  (M9) follow. The reference implementation and `generate_fixtures.py` gain the field and
  four fixtures (valid, alias, invalid, on a timed set); the manifest grows by four.
- Advice (§6.11) does not read it — reps in reserve is for the person, not the algorithm — but
  the Progression prompt's history lines carry it, so the chatbot knows the sets were not to
  failure.

## Z3 — A plan in several pastes (note 8, D52)

The owner's main concern. Today's prompt asks for the whole plan in one reply, and a six-day
plan is 4–5,000 characters of JSON — over what a free chatbot tier will write in one message,
and a long paste to carry. X3's **Add day from JSON** already accepts one day at a time; what
is missing is a flow that starts that way on purpose, and a prompt that asks for it.

**The reading** — *a master and its days*: Add plan's chatbot section gains a second way,
**Build it day by day**, for long plans and free chatbots. 1 **Copy the outline prompt**: the
chatbot answers with the plan's *outline* only — name, units, schedule, the day names and the
repeat block, no exercises — which the app reads as a draft with empty days. 2 For each day,
**Copy day prompt** (it carries the outline and the day's name, so the chatbot writes just that
day) and paste the reply into its slot. 3 **Save plan** when every slot is filled; the whole
thing then goes through the ordinary import once, so the app holds nothing it would refuse. The
draft survives leaving the app, as the editor's text does. *Chosen over* a prompt line asking
the chatbot to split long replies itself (it will not, reliably) and over trimming the example
in the prompt (it is the format).

- `PlanOutline` (Core): the master's importer — the plan's header fields and its days' names
  and weekdays, through the same normalise rules, with `E_NO_EXERCISES` deliberately not
  raised. `Prompts.outline` and `Prompts.day(outline:dayName:)`, both under the marker rule.
- `PlanDraft` (Core): the outline plus a day fragment per slot, assembled into one plan for
  the ordinary import; stored as `draft.json` in the store, optional, removed on save.
- The whole-plan prompt stays the default; the day-by-day way sits beneath it in the same
  section. **Add day from JSON** stays where it is for the case where a plan is already
  saved and one day was cut short.

## Z4 — Progression by performance (note 3, D53)

"The progression should be by performance instead of by calendar. Maybe a legacy calendar
increase, but should include the progression steps." v1.3's progression (D44) is a list of
weeks and the calendar turns the page; a week you miss is a week the plan skips.

**The reading** — *steps you earn*: a progression is a ladder of **steps** per exercise (what
the weeks were), and an exercise moves to its next step when a workout **achieves** the current
one — every logged set at or above the step's reps, within the one-rep tolerance the advice
already uses (§6.11); a hold held for its seconds. Miss it and the step repeats next time, and
the card says so ("Step 3 again"). The calendar stops mattering. **By calendar** stays as the
per-progression choice at planning time, for the owner's "legacy" case, and both modes show
the ladder. *Chosen over* advancing one step per completed workout whatever happened (that is
the calendar with extra steps) and over keeping calendar weeks with only a steps view added.

- `Progression.mode` (`performance` | `calendar`), optional on disk — absent reads as calendar,
  which is what every existing progression is — and `ProgressionEntry.step`, the current step
  in performance mode, advanced when a session completes (`library.apply(.finish)`), never by
  editing history later (recorded as a decision). The on-disk names `weeks` and
  `progressionWeek` are kept for the files already written; the words on screen are *step*.
- **The reply** (`PROGRESSION_FORMAT.md`): `steps` in place of `weeks`, with `weeks` read as an
  alias (`W_PROGRESSION_WEEKS_ALIAS`, cleanup) so a reply to the old prompt still imports.
  **The prompt** (`Prompts.progression`) asks for steps and says the rule: *"one step is one
  workout's targets; I move to the next step when I hit the current one."* PROMPT.md §3 and
  the pin (W37) follow.
- **The ladder on screen**: Progression's screen shows every exercise's steps in one line with
  the current one bold, and "Step 3 of 8 · 2 tries" where a step has repeated; Home's subtitle
  reads "step 3 of 8" (the lowest current step among the day's exercises); the chip's reason
  reads "Step 3 of 8 of your progression". Finished when every exercise is past its last step;
  Home offers **Plan the next one**, as now.
- Prefill (§6.5 rule 0), the Summary's line and Session detail's first line keep working with
  the word changed.

## Z5 — Goals and milestones (note 4, D54)

**The reading** — *a goal per exercise*: a target you name — a weight × reps, seconds, or reps
on a bodyweight exercise — with an optional date. *Chosen over* milestones that live only
inside a progression (a goal outlives any one progression) — though a progression's last step
that meets a goal is shown as reaching it, so both readings meet in the middle.

- `Goal` (Core): exercise name (matched by §6.9, independent of plan), the target, the date,
  and `reachedAt`. Stored in `goals.json`, a new file in the store (§8.1), optional in the
  backup document (§8.5) so a v1.4 backup still restores.
- **Where**: History → an exercise → **Set a goal**; Plan detail's exercise sheet → Goal; and a
  **Goals** section at the top of History listing each with its progress — *"Barbell Bench
  Press 100 kg × 5 · best 82.5 × 5 · by 1 Dec"* — progress being the best logged set that
  meets the reps, against the target weight (or seconds, or reps).
- **Reached**: the first logged set that meets it. The Summary says *"Goal reached: Bench Press
  100 kg × 5"* in the reserved green, like a PR (D30); the goal stays listed as reached, with
  the date, until you remove it.
- **The chatbot knows**: the Progression prompt includes the goals for the plan's exercises
  (*"Goal: Barbell Bench Press 100 kg × 5 by 1 Dec"*), so the steps it plans climb towards
  them. The one thing the app does not do is set weights from goals itself: the chatbot plans,
  the app runs (D12).

## Z6 — Docs, checklist, bundle

- SPEC §4, §5, §6.26–6.30 and §8 reconciled; `PLAN_FORMAT.md` §2, §4 and §5 for `inReserve`;
  `PROGRESSION_FORMAT.md` for steps; `PROMPT.md` for the three prompts and the rule.
- `TEST_CASES.md` gains section **Z** (v1.5), per milestone as they land.
- `DEVICE_CHECKLIST.md` gains v1.5 rows; `BUILD_STATUS.md`, `DECISIONS_LOG.md`, README,
  `CLAUDE.md`/`AGENTS.md` and `HANDOFF_BUNDLE.md` regenerated; `tools/check_bundle.py` and
  `tools/check_release.py` pass; a Release build compiles.

---

## Parked — your numbers, before there is history (note 5)

"Before progression is made there should be a history for each exercise. The first time using
the app should also include a history." The built-in plans have no weights (D46), so the first
session asks for them; Progression's prompt sends the last six sessions of each exercise and
has nothing to send for an exercise never done.

The reading offered, not built. *Current numbers*: a **baseline** per exercise — the weight and reps (or
seconds, or reps on a bodyweight exercise) you can do now — entered by you, never counted as
a workout. *Chosen over* requiring an import from another app (most people have none) and over
writing a fake session into History (a lie the chart would draw).

- `Baseline` on the plan, keyed by normalised exercise name (§6.9), optional in
  `Persistence.swift`: weight, work, and the date entered.
- **Where it is entered**: the review sheet — for a built-in plan or a pasted one — gains
  **Enter your current numbers**, optional, a list of the plan's exercises with a weight and a
  reps field each (reps only when bodyweight; seconds when timed); Plan detail's menu has the
  same as **Current numbers**; and Progression's planning screen lists the exercises that have
  neither a session nor a number and offers the same sheet. The intro's **Choose a plan** path
  reaches the review sheet, which is where the note's "first time" lands.
- **What it does**: prefill rule 2½ (§6.5) — after last time, before the plan's target — so the
  first card is not empty; the suggestion chip's reason reads "Your current numbers"; the
  Progression prompt sends *"Current: 60 kg × 8 (entered, not logged)"* for an exercise with
  no session. Never in History, PRs, the chart or Metrics.
- **The rule for Progression**: Copy prompt is enabled only when every exercise the prompt
  would plan has a logged session or a number; until then the screen names the ones that have
  neither and offers the sheet. That is the note's "before progression is made there should
  be a history for each exercise", made literal.
