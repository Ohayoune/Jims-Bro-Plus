# Jimm's Bro+ — v1.6 plan (iteration 7)

The owner's note, in their words: *"Something about it feels clunky, hard to understand, hard
to get started. I want my app to be useful for a professional and usable for a 5 year old and
his great grandparent."*

The evidence is `docs/UX_REVIEW_2026-09-09.md`: v1.5 walked on the simulators as a stranger
(a clean install, the intro, a built-in plan, a first workout) and as a returning user (three
weeks of history, every tab and sheet, accessibility-XL text, a plain-text paste). It found four
habits that compound — the app speaks gym-programmer, everything is text of one weight, the first
five minutes are a gauntlet, and the schedule model says things the person knows are false — and
twelve outright defects. This plan is the audit's ranked backlog turned into milestones.

The bar is the owner's three users. **The coach** wants density, speed and correctness and is
mostly served. **The great-grandparent** needs big targets, plain words, one thing at a time and
a visible way out of everything. **The five-year-old** needs pictures, colour and one giant button,
and is served today by exactly one screen: the timed set. Each milestone says which of the three
it moves.

Milestones **U0–U6, in order**. Each ends with the full suite green on the three routes, a
Release build and `tools/check_release.py` (v1.4's rule), and one commit on `v1.6-refinement`,
off `main`. SPEC amendments land before the code that depends on them. Each milestone is one
decision, D55–D59, recorded in SPEC §6 and `DECISIONS_LOG.md` by the milestone that lands it.
Test cases take the prefix **U** in `TEST_CASES.md`.

One milestone, **U4 — plain words**, changes the app's voice rather than its behaviour, and is
written up as two readings for the owner to choose between. It is not built until chosen; the
milestones after it do not depend on it.

---

## U0 — This plan, the branch, the review

- Branch `v1.6-refinement` off `main` (v1.5 is merged, tagged and pushed).
- `docs/UX_REVIEW_2026-09-09.md` committed as the review this plan answers, the way
  `CODE_HEALTH_REVIEW.md` was for v1.2. Its screenshots stay in the ignored `build/` folder,
  as the v1.1 review's did.
- No app code.

## U1 — Nothing untrue (D55)

Every sentence the app volunteers must be one the person could not contradict. Five places said
something false in the audit; all five are Core rules, so all five become unit tests
(`JimmsBroTests/UsabilityTests.swift`). Moves all three users: a false sentence costs the coach
trust and the other two their confidence.

- **A missed workout is one the plan actually expected.** `PlanSchedule.missed` walked up to
  seven days back through the projection and never asked whether the plan existed then, or
  whether a later completion had re-anchored the pattern over those days. It reported "Full
  Body B was due Sunday" three minutes after a fresh install, and "Pull was due Tuesday" after
  a day run out of order. The rule: a day is missed only if it is **after the plan's import
  day** and **after the plan's most recent completed session**, within the week. A plan with no
  completed workout has missed nothing.
- **"Nothing logged" outranks "First time".** `SessionStats.comparison` answered "First time"
  for an exercise with no history even when nothing was logged for it today; the Summary of a
  first workout said "First time" five times for four exercises the person never touched.
- **A calendar cell can tell the plan's days apart.** `CalendarText.short` cut every name to
  its first word, so Full Body A and Full Body B were both "Full…" and Upper A and Upper B both
  "Uppe…". Labels are now chosen **within the plan**: the first word when it is unique among the
  plan's days, else the initials of every word ("FBA" / "FBB", "UA" / "LB", "D1" / "D2"), else
  a number. The spoken cell still says the whole name.
- **The suggestion chip never contradicts the fields.** Two rules in `Prefill`: the "do that
  again" suggestion proposes what was done last time — last time's reps at last time's weight —
  never the plan's reps at last time's weight, which read "Try 5 × 100 kg" under "Last time
  10 × 100 kg"; and a chip that says exactly what the fields already show is not shown at all
  ("Try 4 reps · The plan's target" under a reps field reading 4). A progression's chip keeps
  showing, because its reason — which step this is — is the point of it.
- **The right sentence for a paste that is not JSON.** `IssueText` gave every `E_NOT_JSON` the
  same sentence, "the chatbot's reply looks cut off", including for a plan pasted in plain
  words, which is the most natural first paste there is. Two sentences now: no JSON at all →
  *"This is a plan in words. Send it to a chatbot with the prompt and paste back what it
  writes."*; JSON that will not parse → the cut-off sentence, unchanged.
- **The overview says a note once.** `OverviewView` printed each exercise's whole note on every
  set row; it now renders `StepCard.targetLine(notes: false)`, which already existed for the
  purpose, and the note stays on the exercise. (A view fix, landed here because it is one word.)
- **1.5 is 1.5.** `MARKETING_VERSION` and `docs/APP_STORE.md` said 1.4 for a repository tagged
  v1.5; both read 1.5, as `APP_STORE.md` step 8 describes, and `check_release.py` agrees.

## U2 — Nothing unreachable (D56)

Six places where the way forward, or the way out, was hidden or under something. Views, checked
on the simulator (`build/u2-*.png`), with a Core rule and a test wherever the view was deciding
something. Moves the great-grandparent most.

- **Every confirmation shows its way out.** Finish workout, Discard workout and Delete plan are
  presented from a menu, and on iOS 26 and later a `confirmationDialog` presented from a menu
  anchor draws as a popover that drops the cancel-role button: "14 sets not done. Finish
  anyway?" offered one red button and no visible way to say no. All three become **alerts** with
  two named buttons ("Finish workout" / "Keep going", "Discard" / "Keep going", "Delete" /
  "Cancel"). The list swipes keep their dialogs, which present as sheets.
- **Nothing sits on Log set.** The system keyboard toolbar's Done drew as a floating pill over
  the primary button's lower half, and a tap there did nothing. The toolbar goes; while a field
  is focused the **status strip** carries a Done button in its trailing slot (the same slot the
  rest controls use), and Log set commits whatever is typed. Zones do not move (D22).
- **An empty bottom action draws nothing.** `bottomAction` padded and painted its bar even
  when its content was empty, leaving a small white rectangle at the bottom of Add plan and
  Progression before anything was pasted. The inset is only added when there is a button.
- **The empty weight field looks like a field.** A placeholder, *"tap to type"*, in the
  secondary colour, and a soft outline while the field is empty. (The one-time explanation of
  *why* it is empty is U3's.)
- **Finish is not red.** "Finish workout" saves; only "Discard" destroys, and only it is red.
- **At accessibility text sizes the inputs come first.** At AX sizes the strip took forty
  percent of the screen and the reps and weight rows sat below the fold of a zone with no
  scroll indicator. At those sizes the set list shows the current row only and the strip drops
  its second line, so the inputs are on screen with the button.
- **The stage is said once.** While working, the header's stage title and the small line beneath
  it both read "Exercise 1 of 5 · Set 1 of 4". `WorkoutScreenModel.progressLine` is nil when it
  would repeat the stage, and the small line then carries only the elapsed time.

## U3 — The first five minutes (D57)

The path a stranger takes, made to ask for nothing it has not explained. Core rules with tests;
the screens checked on a clean simulator (`build/u3-*.png`). Moves the great-grandparent and
the five-year-old, and costs the coach nothing they will notice.

- **The warm-up is off until you turn it on.** A fresh install's `Settings()` has
  `warmUpSeconds = 0`; a settings file that predates the setting still reads 300, which is
  D32's behaviour for the phones that have it. The Settings footer already says what the row
  does. The owner's phone, which wrote the value in v1.2, is unchanged.
- **During a warm-up the primary button starts the set, it does not log one.** The button reads
  **Start first set** and ends the warm-up (`skipRest`); **Log set** appears once the set is
  under way. Between-set and between-exercise rests keep Log set, because by then a set has
  been done and logging straight out of the rest is the coach's flow. `WorkoutScreen.primary`
  gains the rest kind and a `.startSet` kind.
- **Notifications are asked for when they are about to matter.** Not at Start, over the first
  card, but at the first **Log set** or **Start timer** of the app's life — the moment the
  first rest, whose end the alert announces, is about to begin. The intro's rest page says the
  app will ask. The banner for a refusal is unchanged.
- **The first empty weight explains itself.** `InputDefaults.weightHint` — *"Type the weight you
  lift. The app remembers it from then on."* — under the weight row while the field is empty
  and the exercise has no history; gone the moment it has a value. The built-in plans' first
  note no longer has to carry that sentence in a line that truncates.
- **The unit is asked, not assumed.** `ImportResult.unitsStated` says whether the plan named its
  unit. When it did not — every built-in plan, and any pasted plan without `units` — the
  review sheet asks with a full-width **kg / lb** control above the days, defaulted from
  Settings; the choice is written into the plan and its JSON before it is saved.
- **The picker recommends.** Full Body carries a **Start here** badge while History is empty,
  and the sentence under the routines points at a control on the screen the reader is on.
- **Home leads with the workout on every day.** The headline is the day's name even on a rest
  day, the button is **Start Full Body B** (never "early"), and the schedule is one quiet
  subtitle: *"Planned for Fri · Full Body · 5 exercises"*. The calendar still shows the rest day.
  `HomeStart` changes; `StartCard`, the resolver, does not.
- **The Summary says what happens next.** One line under the headline: *"Next: Full Body B,
  Friday"*, from the same schedule the calendar draws, now that the rotation has advanced.

## U4 — Plain words (D58) — the owner's reading

The audit's largest finding is not a defect: the app's notation — "5 (4–6) · 100 kg · last
10 @ 100", "12 (8–12) · 24 kg", "AMRAP · 20 kg", "drop 1 of 2", the A / B badges, "kg ·
rotation", "Set as current plan" — is correct and is what a coach reads at a glance, and it is
also the single biggest reason the other two users cannot. This changes the app's voice, so it is
the owner's call. Two readings, and the second is recommended:

- **Reading A — compact stays, words are a tap away.** Notation unchanged; the first time a
  screen shows a group badge, a drop or an AMRAP, a one-line explanation appears beneath it, once
  per install. Smallest change; the numbers stay exactly as the owner reads them.
- **Reading B — words by default, compact as a setting.** `TargetText` grows a plain grammar
  used everywhere a stranger reads: the card's target line *"Aim 4–6 reps · 100 kg"*, the set
  row *"Last time 10 × 100 kg"* on its own line and never "@", *"paired with Tricep Pushdown"*
  for a group, *"then lighter, as many as you can"* for a drop, *"Use this plan"* for "Set as
  current plan", *"repeats every 7 days"* for "rotation". A **Compact notation** switch in
  Settings restores today's forms for the coach. The engine, the format, the prompts and the
  fixtures do not change; the strings the views render do, and the tests that pin them.

Whichever is chosen lands as its own milestone with the SPEC §4.0 rule rewritten to say which
words the app uses, and a pin test that the views use them.

## U5 — Hierarchy (D59)

Where the eye lands, and what looks tappable. Mostly views, checked on the simulator
(`build/u5-*.png`); the Core strings that change are tested. Moves the great-grandparent and
gives the coach two things they asked for in the audit.

- **Home**: Start moves to the bottom slot every other screen uses for its primary button;
  section headers are ink, not accent, so only tappable text is blue; the three footnote links
  become small bordered buttons; projected days on the month grid are a label in the secondary
  colour rather than an outlined box, so done days and today stand out.
- **The workout**: Undo sits on the row that was just logged (↺ beside the tick) rather than at
  the end of a wrapping line; the idle strip earns its space with the next set's rest — *"Rest
  2:30 starts when you log"* — instead of a blank band; Plan detail's **Start Legs** is a
  bordered button rather than a text link.
- **History**: rows read *"28 min · 16 sets · 13,920 kg lifted"*; a visible **Find an exercise**
  row under Metrics, because the search field is not shown on every iOS.
- **Settings**: duration presets (Off · 1 · 2 · 3 · 5 min) beside the steppers for the warm-up
  and the walk, and (60 · 90 · 120 · 180 s) for the default rest; the developer sentences
  rewritten for a stranger ("Re-running from Xcode…", "the prompt and future imports…", "said,
  never enforced").
- **Plans**: the repeat block's chips wrap instead of scrolling off the edge; an **Add exercise**
  row at the end of each day; Plan detail's subtitle says *"kg · repeats every 7 days"*.

## U6 — Docs, checklist, bundle

- SPEC §4.1, §4.4, §4.5, §4.9, §5.1, §5.3, §6.12 and §6.14 reconciled; §6.31–6.34 for
  D55–D57 and D59 (and D58 when chosen).
- `TEST_CASES.md` section **U**, per milestone as it lands; `DEVICE_CHECKLIST.md` gains the
  v1.6 rows; `BUILD_STATUS.md`, `DECISIONS_LOG.md`, README, `CLAUDE.md`/`AGENTS.md` updated;
  `ITERATION_7_PLAN.md` and `UX_REVIEW_2026-09-09.md` added to the bundle and
  `HANDOFF_BUNDLE.md` regenerated; `tools/check_bundle.py` and `tools/check_release.py` pass; a
  Release build compiles.

---

## Parked for v1.7 — the bigger bets

The audit's ideas that need design the owner should see first, not code:

- **A pictogram per exercise and a colour per day.** The system's figure symbols (strength
  training, core, rowing, running) next to every exercise name, and one colour per plan day
  used on Home, the calendar and the workout header. Recognition without reading — the
  five-year-old's whole request, and it helps everyone else find their place.
- **An in-app number pad** under the inputs, with plate arithmetic behind the weight (tap 100:
  "20 + 2 × 20 + 2 × 10"). Bigger keys than the system keyboard, nothing hides the exercise, and
  the keyboard collision cannot come back.
- **One big Done for a rep set** modelled on the timed-set screen: when the prefill is right, the
  whole set is one giant "Done · 10 × 100 kg" button with the steppers a tap away.
- **Opening the chatbot directly** with the prompt (URL scheme when the app is installed, the web
  page otherwise), and a *"Looks like a plan. Add it?"* banner when the app returns with the
  marker or a JSON fence on the clipboard.
- **An introduction made of real screens** — the intro's pages as live miniatures of the card,
  the rest and the summary, with one caption each — instead of four paragraphs.
