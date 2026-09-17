# Jimm's Bro+ — v1.11 plan (iteration 12)

The owner's notes, on 2026-09-16 after v1.10, in their words: *"I want to change how the interface
for the user looks like when they are trying to interact with the JSON. Currently, it feels like an
instruction manual. I don't want the user to have to think as much while using it … specifically,
the different times the user interacts with the JSON, such as creating a plan, adding progression,
or in the future trying to edit something specific in the plan."* And, on the build itself: *"For
the implementation system, everything feels slow. I am wondering if there is any way to parallelize
parts of the implementation when possible."*

Two things under the notes. **First**, the five JSON screens are the last screens left from v1.1's
design. They were built as forms with footers — seven sentences and seven controls on Add plan, nine
and nine on Progression's planning screen, the same three numbered steps and *"you carry the text
both ways"* on three screens — before the owner chose one card with earned controls for Today (D61,
D64), no words without a cue (D69), and squares with a button that confirms for Plans and Change day
(D78, D85). The reader has to read the whole form to find the one thing to tap, and that reading is
the thinking the owner wants gone. **Second**, the text is the screen at the fragment points: the
sheet opens on a monospace editor pre-filled with a day's JSON, so changing today's exercises means
reading JSON even when nothing is wrong. The rule this plan applies everywhere is **show the result,
not the format**: three states, one control each, the same three at every point — **Ask**, **Paste**,
**Review** — and the text itself behind the ··· for the day it is needed.

The requirements were settled on one mock, *"The Round Trip"* —
https://claude.ai/artifact/6ty8Tm6w75cP9wREaH7rGb — which draws every point in every state (every
phone on it works) and asked J1–J7. The owner chose on 2026-09-16: **J1 both buttons** (Send the
prompt through the share sheet, Copy the prompt beneath it — the one place the owner went against
the mock's pick of Share alone); **J2** the trip strip stays; **J3** the built-in plans as a row of
squares under the button; **J4** day by day offered on refusal only; **J5** Progression's two choices
as pre-marked tiles on the Ask screen, no history toggle; **J6** today's exercises edited in place;
**J7** the text behind the ··· at every point, D77's marks kept. Where the mock left something to the
plan (the diff's matching rule, what Apply keeps, the Refused state's buttons per error) the choice
is made below and named as the plan's, with the alternative in one line.

## The example this plan speaks in

Push Pull Legs, the built-in one, Push green, Pull orange, Legs purple; the cycle Push Pull Legs Push
Pull Legs rest. Today is **Wednesday 16 September**, Push: Barbell Bench Press 4 × 6–8 at 80 kg,
Overhead Press 3 × 8–10 at 40 kg, Incline Dumbbell Press 3 × 8–12 at 26 kg, Lateral Raise 3 × 12–15
at 10 kg, Tricep Pushdown 3 × 10–12 at 30 kg, Overhead Tricep Extension 3 × 10–12 at 20 kg. The
owner has three Push sessions in History. The progression asked for is 6 steps, advanced when the
target is hit. The change said in words is *"Swap the barbell bench press for dumbbells. Pull is too
long, drop one exercise."*, and the chatbot's reply replaces Barbell Bench Press with Dumbbell Bench
Press 4 × 6–8 at 32 kg and drops Hammer Curl.

## Milestones, and why four of them run at once

**N0–N7.** N, not O: *O0* reads as a number. Each milestone ends with the full suite green on the
three routes (`xcodebuild test`, `swift test`, `python3 tools/check_core.py`), a Release build and
`tools/check_release.py`, and one commit on `v1.11-round-trip`, off `v1.10-symbols` at v1.10
(33e7d50) — or off `main` once v1.9 and v1.10 are fast-forwarded onto it. Decisions **D87–D95**
are recorded in SPEC §1's table and §6, and in `DECISIONS_LOG.md`, by the milestone that lands them.
Test cases take the prefix **TN** in `TEST_CASES.md` (TP was v1.10's); the ids below are proposals,
and TEST_CASES renumbers on landing as it did for every earlier plan.

The owner asked for a faster build. The earlier plans were a chain: each milestone touched the same
screens, the same SPEC sections and the same test file as the one before it, so nothing could start
until the previous commit was green. This release is different in shape — four screens that share
almost nothing — and the plan is cut to match: **a trunk, then four tracks, then a merge.**

- **N0 and N1 are the trunk**, sequential and first. N1 lands *everything the tracks would
  otherwise fight over*: every SPEC amendment, every decision row, the test section with one
  reserved block per track, the one new prompt, the shared Core types, the extracted sheet, and
  **every new file the tracks will fill, registered in the Xcode project by
  `tools/add_sources.py` while empty.** The project file is the classic kind (no synchronized
  groups), so two branches that each add a file conflict in `project.pbxproj` — the trunk adds
  them all once, and the tracks add none.
- **N2, N3, N4 and N5 are the tracks**, each on its own branch off N1's commit, each in its own
  git worktree, each owning a fixed list of files (the table under N1) and touching nothing else.
  A track edits its own block of `TEST_CASES.md` and nothing else in `docs/` — SPEC is already
  amended, DECISIONS_LOG already written — and never `BUILD_STATUS.md`, `CLAUDE.md` or the bundle.
  Each ends green on the three routes on its own simulator. They can be built by four agents at
  once or by one agent in any order; nothing in one depends on another.
- **N6 is the merge**, sequential: the four branches onto the trunk in order N2, N3, N4, N5, the
  full suite and a Release build after each, dead code out, and `BUILD_STATUS.md` once. **N7** is
  the documents.

**How to run the tracks at once.** From the trunk at N1's commit:

```bash
git worktree add ../jimmsbro-n2 -b v1.11-n2 v1.11-round-trip
git worktree add ../jimmsbro-n3 -b v1.11-n3 v1.11-round-trip
git worktree add ../jimmsbro-n4 -b v1.11-n4 v1.11-round-trip
git worktree add ../jimmsbro-n5 -b v1.11-n5 v1.11-round-trip
```

One simulator per track — `xcrun simctl clone "iPhone 17" "iPhone 17 n2"` and so on, or four
different installed iPhones — because two `xcodebuild test` runs installing the same bundle id on
one simulator trip over each other; DerivedData is per worktree already. In Claude Code, one session
per worktree (the desktop app's *spawn a task* gives a fresh worktree; or one session with a subagent
per track, `isolation: "worktree"`); in Codex, one agent per worktree with the same instruction:
*"Build N3 of `docs/ITERATION_12_PLAN.md`. Read N1's file table, your own section and the SPEC
sections it names. Touch only your files and your test block. End with the three routes green."*
While iterating, `swift test --filter <Class>` and `python3 tools/check_core.py` are the fast loop
(no Xcode); `xcodebuild build-for-testing` once and `test-without-building -only-testing:JimmsBroTests/<Class>`
for reruns; the full three routes once at the end. Merge on the trunk:

```bash
git merge --no-ff v1.11-n2 && git merge --no-ff v1.11-n3 && git merge --no-ff v1.11-n4 && git merge --no-ff v1.11-n5
```

Expected conflicts: none in code (disjoint files), none in `project.pbxproj` (N1 added every file),
and at most the neighbouring blocks of `TEST_CASES.md`, which resolve by keeping both. A track that
finds it needs a file N1 did not register says so and adds it with `tools/add_sources.py` — that is
the one merge conflict the plan accepts, and it is mechanical.

**This plan does not touch the on-disk contract.** No field on `Settings`, `Plan`, `Session`,
`Progression` or `DaySwap` changes; `examples/store/v1/` is untouched; no fixture changes. The plan
format and the progression format do not change. The pipeline does not change: every paste and every
edit below goes through `PlanImport.run`, `PlanEdit` and `PlanDrafting` as they are. The Workout
screen, the Lock Screen, History, the calendar, the Summary, the CSV import and Settings are untouched.
The one new prompt (§7 of `PROMPT.md`, D94) is a new prompt, not a change to an old one.

| Milestone | Decision | Lands | Runs |
|---|---|---|---|
| N0 | — | this plan, the branch, the bundle | trunk |
| N1 | D87, D89, D95 | the SPEC amendments; `Trip`, the strip, the prompt buttons; the sheet extracted; every file registered; the test blocks | trunk |
| N2 | D88, D90, D91 | Add plan: Ask, Paste, Review, Refused; built-ins as a row; day by day on refusal | track |
| N3 | D92 | Progression: tiles, the ladders, Start step 1 | track |
| N4 | D93 | today's exercises, edited in place | track |
| N5 | D94 | say what should change | track |
| N6 | — | the merge, dead code out, `BUILD_STATUS.md` | trunk |
| N7 | — | docs, checklist, bundle, 1.11 | trunk |

---

## N0 — This plan, the branch, the bundle

`docs/ITERATION_12_PLAN.md` (this file) on `v1.11-round-trip`, the file added to
`tools/build_bundle.py` and the bundle regenerated in the same commit (CI checks it), and the
paragraph in `CLAUDE.md` and `AGENTS.md` that introduces v1.11 — ending *"N0 is written; nothing
else is built"* until N7 rewrites it. The mock stays an artifact; nothing is copied into the repo
but the link above.

---

## N1 — The trunk: the amendments, the seam, the files (D87, D89, D95)

Sequential and first. Nothing here is a screen; everything here is what four screens will share.

### D87 — show the result, not the format

Every point where the app hands text to a chatbot and takes its reply back is one screen in
**three states, one control each, the same three everywhere**:

- **Ask.** The trip strip (D89) with *Prompt* lit, and two buttons in the bottom slot: **Send the
  prompt**, the accent one, which opens iOS's share sheet with the prompt as text — the ChatGPT app
  and the Claude app take shared text into a new message, and Copy is one row down in the sheet for
  a chatbot in a browser — and **Copy the prompt** beneath it, quieter, which copies (J1). Both move
  the screen to Paste.
- **Paste.** The strip with *Paste* lit, and one button: the system paste button (`PasteButton`),
  large, alone. It needs no permission alert and does nothing when the clipboard holds no text,
  which is the "primary when the clipboard has text" rule without reading the pasteboard (O3). The
  paste runs the pipeline and the screen becomes Review or Refused.
- **Review.** What the app drew from the reply, in the app's own language — the plan as the Plans
  page draws it, the progression as ladders, the change as old and new — and one button that names
  the effect: **Use Push Pull Legs**, **Start step 1**, **Use for Wednesday**, **Apply 2 changes**.
  No "Save". The review screens that exist (`PlanReviewSheet`, `ProgressionReviewSheet`) are kept
  and redrawn, not replaced.
- **Refused.** The friendly sentence (`IssueText.friendly`, D26) in a red band under the strip,
  with the strip lit where the fix is — *Chat* when the reply must be asked for again, *Paste* when
  the paste was the prompt itself or nothing — and buttons that send the trouble back: **Ask for the
  whole plan** (the fix-it prompt, `Prompts.render(errors:)`, through the same share sheet, with
  Copy beneath) for a reply the pipeline refused; **Send the prompt** again when the prompt itself
  was pasted (`E_PROMPT_PASTED`) or nothing was; and, on a reply that came cut short, **Get it day
  by day** (D91). The path and the code stay behind *Details* as D26 put them.

And what leaves: **every footer**, the three numbered steps, *"Show text"*, *"Import file"* and
*"Build it day by day"* as rows, *"Copied"* as a state, the "Use this plan" toggle, and **the word
JSON from every title and placeholder** — the sheet is *One exercise*, *One day*, *The plan*, and
"the text" when it must be named at all. The one sentence the app still owes a first-time user —
that the app never talks to the chatbot itself, you carry the text — moves to the introduction's
first page, *A plan, then Start* (D47, `Core/Introduction.swift`), said once. *(This reverses D26's
"three ways in" as the front door of Add plan, and D50's mechanism sentence on the screens; both are
named in DECISIONS_LOG.)*

**The stage is Core data.** `Core/Trip.swift`:

```swift
/// D87: a chatbot round trip's screen, as data. Each point has its own screen type in its own
/// file (ImportTrip, ProgressionScreen, ChangeRequest); this is what they share.
enum TripStage: Equatable, Sendable { case ask, paste, review, refused }

/// D89: the strip — Prompt, Chat, Paste — as three marks in the Workout screen's states.
struct TripStrip: Equatable, Sendable {
    static let names = ["Prompt", "Chat", "Paste"]
    var marks: [MarkState]                       // always three
    static func of(_ stage: TripStage, fixAt: Int = 1) -> TripStrip
    // ask → [now, todo, todo]; paste → [done, done, now]; review → [done, done, done];
    // refused → done up to fixAt, now at fixAt, todo after (fixAt 1 = Chat, 2 = Paste)
}

/// D87: the bottom slot. Views draw it; they never compose it.
struct TripButtons: Equatable, Sendable {
    var primary: String
    var secondary: String?
    static func ask() -> TripButtons          // Send the prompt / Copy the prompt
    static let paste = TripButtons(primary: "Paste", secondary: nil)
    static func effect(_ title: String) -> TripButtons
}
```

`MarkState` is v1.10's (`Core/WorkoutMarks.swift`, D79): done, now, todo. On these screens *done*
is drawn in ink, not a day's colour, because there is no day yet; `DaySquare.swift` gains
`TripStripView(strip:)` — three joined squares with the words beneath, `MarkState.done` as ink,
`.now` the accent, `.todo` `secondarySystemFill` — the joined drawing of `CycleStrip` (D86) at
strip size, with a glyph in each square (a document, a speech bubble, a clipboard; a check once
done). The Refused band is `RefusedBand(sentence:)` in the same file.

**The prompt buttons** are one view every track uses, `Features/Shared/PromptButtons.swift`:
`PromptButtons(text: String, subject: String, sent: () -> Void)` — a `ShareLink(item:subject:)`
styled as the primary button (**Send the prompt**), `Clipboard.write` under a soft button (**Copy
the prompt**), and `sent()` on either, which is what moves the caller to Paste. `ShareLink`'s
completion is not observable in SwiftUI, so *presenting* the sheet counts as sent: the owner who
cancels the sheet finds the Paste state with an empty clipboard, where the button does nothing, and
the ··· has *Send the prompt again* — the alternative, holding Ask until the share completes, needs
UIKit and a delegate, and is named here as the alternative.

### D89 — the trip strip

Three joined squares at the top of every Ask, Paste and Refused screen, the current one lit,
the ones behind in ink with a check, the ones ahead grey, and one word beneath each — *Prompt*,
*Chat*, *Paste* — a word beside its cue (D69). It replaces the numbered sentences, and it is the
same strip on every point, so the second screen that shows it needs no explaining. On Add plan
it is large and centred with nothing else on the screen; on Progression and on Say what should
change it is small above the button, under the choices.

### D95 — the text behind the ···

The JSON is not gone. Every one of these screens has a ··· (`QuietGlyph`, D69), and its last item
is **Edit the text**, which opens the sheet exactly as D77 left it — named, pre-filled, the error
marked at its line, a Save that says its effect (`JSONFragmentSheet`, `JSONPoint`). Add plan's ···
also holds **Open a file** (the old Import file, `fileImporter`) and, on the review, **Keep without
using** (the old toggle's other half). §6.40's table gains the rows: the ··· itself appears with the
screen; *Edit the text* is never gated. Nothing in the sheet changes; only the door moves.

### The seam the tracks build on

- **`ExerciseEditSheet` extracted** from `PlanDetailView.swift` (line 353) into
  `Features/PlanDetail/ExerciseEditSheet.swift`, unchanged, and given a second initializer beside
  the operation form: `ExerciseEditSheet(exercise: Exercise, units: WeightUnit, save: (Exercise) -> [Issue])`,
  the value form, which N4 edits a day outside the plan with. Both forms edit the same fields (name,
  set count, reps, rep range, weight, rest, in reserve) and one test proves they agree.
- **`ProgressionModel.progressionPrompt`** loses `includeHistory:` (always on — J5); the parameter
  goes now so N3's screen and N5's tests do not race on the signature.
- **`PROMPT.md` §7 — the change prompt** (D94's text, written here so N5's pin test has something
  to pin): marker `JIMMSBRO-CHANGE-PROMPT-V1`; *"Change the plan below as I ask, and reply with the
  WHOLE plan as ONE complete JSON object in a single code block tagged json, in exactly the same
  format, with nothing changed that I did not ask for. Keep every exact name you do not change."*;
  `{{request}}` verbatim under **WHAT TO CHANGE**; `{{plan}}` as the plan's canonical JSON
  (`PlanJSON.render`), not the listing, under **MY PLAN** — the reply must be a whole plan, and the
  listing loses rest, notes and in reserve. `Prompts.change(plan:request:settings:)` renders it.
  §6's behaviour notes gain a line: the marker and no fenced block is `E_PROMPT_PASTED` as for §1.
  `COPY_PASTE_NOTES.md` gains a line: this prompt is not shortened; a cut plan would be a wrong plan.
- **Every new file, empty but for a doc comment, registered** with `tools/add_sources.py`:
  `Core/Trip.swift` (filled here), `Core/ImportTrip.swift`, `Core/DraftTrip.swift`,
  `Core/ProgressionScreen.swift`, `Core/ProgressionLadder.swift`, `Core/DayEdit.swift`,
  `Core/ExerciseNames.swift`, `Core/PlanDiff.swift`, `Core/ChangeRequest.swift`;
  `Features/Shared/PromptButtons.swift` (filled here), `Features/Home/DayEditorView.swift`,
  `Features/PlanDetail/ChangePlanView.swift`, `Features/PlanDetail/ExerciseEditSheet.swift`
  (filled here); tests `JimmsBroTests/TripTests.swift` (filled here),
  `RoundTripImportTests.swift`, `RoundTripProgressionTests.swift`, `DayEditTests.swift`,
  `PlanDiffTests.swift`. `tools/check_core.py`'s file list, if it enumerates Core, gains the Core
  ones. `DraftPlanView.swift` stays until N6 deletes it.
- **`TEST_CASES.md`**: a new section *## TN. v1.11 — The round trip* with five `###` blocks, N1–N5,
  each holding its reserved ids as one placeholder row *"(filled by N2)"*; the tracks fill their
  own block only.

**File ownership.** The contract that makes N2–N5 safe to build at once:

| Track | Owns (and nothing else) |
|---|---|
| N2 | `Features/Import/ImportView.swift`, `BuiltInPlansView.swift`, `DraftPlanView.swift` (emptied), `Store/DraftModel.swift`, `Core/ImportTrip.swift`, `Core/DraftTrip.swift`, `JimmsBroTests/RoundTripImportTests.swift`, its TEST_CASES block |
| N3 | `Features/PlanDetail/ProgressionView.swift`, `Store/ProgressionModel.swift`, `Core/ProgressionScreen.swift`, `Core/ProgressionLadder.swift`, `JimmsBroTests/RoundTripProgressionTests.swift`, its block |
| N4 | `Features/Home/ChangeDayView.swift`, `Features/Home/DayEditorView.swift`, `Core/ChangeDay.swift`, `Core/DayEdit.swift`, `Core/ExerciseNames.swift`, `JimmsBroTests/DayEditTests.swift`, its block |
| N5 | `Features/PlanDetail/PlanDetailView.swift` (the ··· item only), `Features/PlanDetail/ChangePlanView.swift`, `Core/PlanDiff.swift`, `Core/ChangeRequest.swift`, `Core/Prompts.swift` (`change` only), `Store/AppModel` — one method, `applyChange` — `JimmsBroTests/PlanDiffTests.swift`, its block |
| trunk only | `Core/Trip.swift`, `DaySquare.swift`, `Features/Shared/PromptButtons.swift`, `ExerciseEditSheet.swift`, `JSONFragmentSheet.swift`, `Core/JSONPoint.swift`, `Core/Introduction.swift`, `RootView.swift`, `project.pbxproj`, every `docs/` file but the TN blocks, the bundle |

A track that needs something in the trunk's column (a new `JSONPoint` kind, say) does not take it:
it writes the smallest version it can inside its own files and leaves a line for N6.

SPEC (all of it lands here, before any track): §1's table, rows D87–D95; §4.4 *Add plan* rewritten
as the three states, the built-ins row and the ···; §4.3's ··· gains **Say what should change** and
names *Edit the text*; §6.19 the sheet reached from the ··· (D95), its titles without "JSON";
§6.21 Progression: the planning screen as tiles, no toggle, Apply keeps a progression (D94's note);
§6.26 the introduction's first page carries the mechanism sentence; §6.28 the door moved to the
Refused state (D91); §6.40's table, the new rows; §6.50 and §6.58: the card opens the editor (D93),
§6.58's parked line replaced; new §6.60 *Show the result, not the format (D87)*, §6.61 *Send the
prompt, Copy the prompt (D88)*, §6.62 *The trip strip (D89)*, §6.63 *Built-in plans as squares
(D90)*, §6.64 *Day by day on refusal (D91)*, §6.65 *Progression: tiles and ladders (D92)*, §6.66
*Today's exercises in place (D93)*, §6.67 *Say what should change (D94)*, §6.68 *The text behind the
··· (D95)*, each with *(v1.10 …)* italics under the rule it changes. `DECISIONS_LOG.md`: D87–D95,
one line each, and the reversals named — D26's front door, D50's sentence, D52's door, §6.58's
parked editor, D43's "Replace drops it" for Apply. `PROMPT.md` §7. Nothing in SPEC says "N2" or
"track": SPEC describes the app, the plan describes the build.

Tests (proposed, `TripTests.swift`): **TN1** `TripStrip.of` for the four stages and both `fixAt`
values, always three marks; **TN2** `TripButtons.ask()` reads *Send the prompt* / *Copy the prompt*,
`.paste` has no secondary, `.effect("Use Push Pull Legs")` carries the title; **TN3** the value form
of `ExerciseEditSheet` and the operation form produce the same exercise for the same edits (name,
count, reps, range, weight, rest, in reserve) — through `PlanEdit` on a one-exercise plan for the
operation form; **TN4** `Prompts.change` renders the marker, the request verbatim, the plan's
canonical JSON, and no history; pasting it back is `E_PROMPT_PASTED`; **TN5** (pin) SPEC §6.60
names the three states and §6.62 the three words, and the introduction's first page contains the
mechanism sentence while `Prompts.render(settings:)` does not; **TN6** (pin) `TEST_CASES.md` has
the five TN blocks and `project.pbxproj` references every file in the list above.

---

## N2 — Add plan: Ask, Paste, Review, Refused (D88, D90, D91) — track

Reads: N1, SPEC §4.4, §6.28, §6.60–§6.64. Owns the files in N1's table. `ImportView` is
rewritten; `PlanReviewSheet` in the same file is redrawn; `DraftPlanView` is emptied to a stub
(N6 deletes it); `BuiltInPlansView` becomes the row.

### D88 — Send the prompt, Copy the prompt

The Ask state of Add plan: the strip large and centred, the two buttons, and under a hairline the
built-ins row (D90). `Core/ImportTrip.swift` is the screen: `struct ImportTrip` with `stage`,
`strip`, `buttons`, `review: Plan?`, `refusal: Refusal?` and the transitions —
`sent()` → paste; `pasted(result: ImportResult)` → review or refused; `fix()` → paste (the fix-it
prompt goes out through `PromptButtons` first); `builtIn(plan)` → review; `Refusal` carries the
sentences, `fixAt`, and `offersDayByDay: Bool` — true for the code whose sentence reads *looks cut
off*, false otherwise — and `buttons` reads *Ask for the whole plan* / *Get it day by day* for it,
*Send the prompt* / *Copy the prompt* for `E_PROMPT_PASTED` and for nothing pasted, *Ask for the
whole plan* / nil for the rest. The view holds an `ImportTrip` and draws it; `runImport` and the
name-conflict alert (O6) stay as they are.

**The review** is `PlanReviewSheet` redrawn as the plan's page: the unit — the segmented kg / lb
above the days only when the plan named none (D57, unchanged) — the cycle as `CycleStrip` (D86)
where the chips were, *Rotation · 7 days* beside it as §6.51 says how often, the days closed until
tapped (`DisclosureGroup`, the first open as now), *Worth knowing* only when there is something
worth knowing, the cleanup behind Details as now. The button is **Use Push Pull Legs** and it makes
the plan current; **Keep without using** in the ··· saves it without (`makeActive: false`). A
built-in plan's paragraph (`about`, D46) stays above the days.

### D90 — built-in plans as a row of squares

Four tiles under a hairline on the Ask and Paste states: each drawn by its own cycle as a tiny
`CycleStrip`, its name beneath, in D46's order. A tap opens the review with the plan and `about`,
as `BuiltInPlansView` did; the pushed picker goes. The intro's *Choose a plan* button and Today's
empty card (D61) open Add plan on its Ask state, where the row is.

### D91 — day by day, offered on refusal

D52's pipeline (`PlanDrafting`, `PlanDraft`, the outline and day prompts, `DraftModel`) is
untouched; its door moves. **Get it day by day** on a cut-short refusal starts a draft and the
screen's Ask state reads **Send the outline prompt** / *Copy the outline prompt*; the outline's paste
opens the review with every day's square **hollow** (`CycleStrip`'s `hollow` set, a new argument on
the trunk's view — the one exception N1 makes room for: an optional `hollow: Set<Int>` on
`CycleStrip`, added by N1 as a no-op) and each day row hollow with *next* on the first; the button
alternates **Send the prompt for Pull** (with Copy beneath) and **Paste Pull**, always for the first
hollow day, and reads **Use Push Pull Legs** when none is hollow. `Core/DraftTrip.swift` is the
screen: `struct DraftTrip` over a `PlanDraft` with `next: Int?`, `hollow: Set<Int>`, `strip`,
`buttons`, `sent()`, `pasted(index:result:)`. A draft in progress reopens on the review the next
time Add plan opens (as `model.draft` did on the row), and the ··· has *Discard the draft* with its
alert (D56). The *Day by day* screen and the *Build it day by day* row go.

Tests (proposed, `RoundTripImportTests.swift`): **TN7** `ImportTrip`'s transitions on the example:
fresh → ask; sent → paste; a valid paste → review with the plan; the prompt pasted → refused with
`fixAt` 2 and Send the prompt; nothing pasted → the same; a cut-short reply → refused with `fixAt` 1,
*Ask for the whole plan* and `offersDayByDay`; any other error → *Ask for the whole plan* alone;
fix → paste; a built-in → review; **TN8** the strip's marks per stage on Add plan (from
`TripStrip.of`); **TN9** the review's button reads *Use <name>* and the ··· offers *Keep without
using*; Use saves active, Keep saves inactive (extends R0's `makeActive` cases); **TN10** a plan
that named no unit still asks kg / lb on the review and Use writes it (extends D57's case);
**TN11** `DraftTrip` on a three-day outline: hollow {0, 1, 2}, next 0, *Send the prompt for Push*;
Push pasted → hollow {1, 2}, *Send the prompt for Pull*; all pasted → *Use Push Pull Legs* and
`PlanDrafting.assemble` is what Use runs; a day the pipeline refuses leaves its square hollow with
the sentence under the strip; **TN12** Get it day by day starts a draft and the Ask state reads
*Send the outline prompt*; **TN13** (pin) `ImportView` shows no section footer, no *Show text*, no
*Import file* row, no *Build it day by day* row — a grep of the source for those strings is empty;
**TN14** (ui) the built-ins row: four tiles, D46's order, each with its cycle; a tap opens the
review; **TN15** (device) the share sheet: the ChatGPT app and the Claude app open with the prompt in
a new message; Copy is in the sheet; **TN16** (device) after the app switch, the system Paste button
pastes without an alert and the review opens.

---

## N3 — Progression: tiles, the ladders, Start step 1 (D92) — track

Reads: N1, SPEC §6.21, §6.29, §6.65. Owns the files in N1's table. `ProgressionView`'s current
sections (the running progression, *Plan the next one*) are untouched; the planning sections and
`ProgressionReviewSheet` are redrawn.

### D92 — two choices marked, then the same trip

- **The Ask state** is `Core/ProgressionScreen.swift`: `steps` from `Progression.periods`,
  default **6**; `mode`, default **`.performance`** (*When I hit it*), the other *Every week*; the
  two rows as joined tiles (`tiles(steps)`, `tiles(mode)`, each tile a title and `marked`), the
  strip small beneath, and `PromptButtons` with `Prompts.progression(plan:history:weeks:mode:…)`.
  A tap marks; Send confirms (D85's rule). The tiles dim in the Paste state and are not editable
  there; the ··· has *Change the steps*, which returns to Ask. **No history toggle**: the prompt
  carries the last sessions whenever there are any (`ProgressionModel.progressionPrompt(for:weeks:)`,
  N1's signature), and *"The prompt includes your last sessions…"* is not said.
- **The review** is `ProgressionReviewSheet` redrawn: grouped by day with the day's square, one row
  per exercise — the name, a **ladder** of its steps, and the first step's numbers (*82.5 kg · 6–8*,
  or *reps · 8–12* for bodyweight) — from `Core/ProgressionLadder.swift`:
  `ProgressionLadder.of(progression, plan) -> [DayLadders]`, each exercise's bars as heights in 0…1
  normalised within the exercise (by weight; by the reps' lower bound when there is no weight;
  equal when neither changes), `{}` steps repeating the previous, the first bar lit, and `first:
  String` from `TargetText` for step 1. *Worth knowing* stays above the days; the paragraph about
  which mode it is in goes — the mode is the tile the user marked, said once in the header as
  *6 steps · when you hit it*.
- **The button** reads **Start step 1** and does what *Save progression* did
  (`setProgression`); History's row then reads *Step 1 of 6* as Z-series built it.

Tests (proposed, `RoundTripProgressionTests.swift`): **TN17** `ProgressionScreen`'s defaults and
tiles: 4 · 6 · 8 · 12 with 6 marked, *When I hit it* marked; marking 8 and *Every week* changes the
prompt's `{{steps}}` and `{{cadence}}`; the stage machine ask → paste → review → started; **TN18**
the prompt carries MY HISTORY whenever the plan has sessions and no block when it has none, with no
parameter to say otherwise (extends M-section's progression cases); **TN19** `ProgressionLadder` on
the example's 6 steps for Bench (80, 82.5, 85, 82.5, 87.5, 90): heights rise, dip at the easier step,
the first lit, *82.5 kg · 6–8*; a bodyweight exercise ladders by reps; `{}` repeats; **TN20** the
review's button reads *Start step 1* and saving sets the progression at step 1 (extends Z-series);
**TN21** (pin) `ProgressionView`'s planning sections contain no `Picker`, no `Toggle`, no
`TextEditor` and no footer string; **TN22** (device) eighteen ladders read on the phone; the tiles
mark under a thumb.

---

## N4 — Today's exercises, edited in place (D93) — track

Reads: N1, SPEC §6.50, §6.58, §6.66. Owns the files in N1's table. This is the editor §6.58
parked, unparked by the owner (J6): *"swap ⇄, drop −, add +, reorder — under the Today's exercises
card, when the JSON sheet proves too far for the common change."* It proved too far.

### D93 — the day, edited where it stands

- **The card** on the Change *day* picker (D85's *Today's exercises*) opens **`DayEditorView`**
  instead of the pre-filled text sheet: titled **Change Push** after the shown day with its square,
  the line *Wednesday 16 September* beside it, and the day's exercises as Today draws them — the
  name, its sets as blocks (`SetBlocks`), a handle at the right — in one card; a dashed **Add
  exercise** row at the end; **Use for Wednesday** in the bottom slot. It opens on the date's own
  day when there is one (`.own(day)`), else the pattern's day, as the sheet did.
- **A row** opens `ExerciseEditSheet` in its value form (N1) for that exercise — sets, reps, the
  range, kg, rest, in reserve, as steppers — and Save puts the exercise back in the row. **The
  handle** reorders (`.onMove`), a swipe deletes (`.onDelete`), as Plan detail's edit mode does.
- **Add exercise** is a sheet headed by a search field that reads **Find an exercise** (D66's
  words) over `Core/ExerciseNames.swift`: `ExerciseNames.known(plans:history:query:)` — the day's
  plan's names first, then the other plans', then History's, each once, each with its source
  (*Upper Lower*, *History*), filtered by a case-insensitive contains; a tap appends the exercise
  with the plan's default sets (three, the day's most common range, no weight) so the sheet is
  the next tap. A name typed that matches nothing is added as typed.
- **Every change is a `DayEdit`** (`Core/DayEdit.swift`): `enum DayEdit { case move(from:to:),
  remove(Int), add(Exercise), replace(Int, Exercise) }` applied to a `Day` value, and **Use for
  Wednesday** renders the day and reads it back through `ChangeDay.ownDay(_:named:units:settings:)`
  — the same check the sheet's Save ran, in the plan's units, refusing what the importer refuses
  (an empty day, a bad range) with the sentence under the strip. The result is `.own(day)`, named
  as it was, the plan untouched, as §6.58 wrote it; History colours by name.
- **The ···** has **Edit the text** — the D77 sheet pre-filled with the day *as edited so far*,
  whose Save returns to the editor with the text's day (D95) — and **Back to Push as written**,
  which removes the date's own day (the swap's delete path, TQ26).

`DayChoices.Exercises` (`Core/ChangeDay.swift`) gains what the editor draws (the rows as
`HomeStart.rows` draws them; it may call `PreviewRow`); `ChangeDayText` gains the editor's title and
the *Back to Push as written* item. Nothing in `DaySwap` changes.

Tests (proposed, `DayEditTests.swift`): **TN23** `DayEdit` on the example's Push: move 0 → 2,
remove 5, add Cable Fly, replace 0 with Bench at 82.5 kg — the day after each, and the whole
sequence through `ChangeDay.ownDay` round-trips; an empty day is refused with the importer's
sentence; **TN24** `ExerciseNames.known` on Push Pull Legs + Upper Lower + a History with Cable
Fly: order plan, other plans, History; no duplicates; *fly* finds Cable Fly; **TN25** the card
opens the editor on the own day when there is one and the pattern's day otherwise (extends TP38);
**TN26** Use for Wednesday writes `.own(day)` named *Push*, the plan untouched, History's colour by
name (extends TP38, TQ28); **TN27** *Back to Push as written* deletes the own day (extends TQ26);
**TN28** Edit the text opens the D77 sheet pre-filled with the edited day and its Save returns the
text's day to the editor; **TN29** (pin) `ChangeDayView`'s card no longer presents
`JSONFragmentSheet` directly; **TN30** (ui) the rows are name + blocks + handle, the add row is
dashed, the picker's field reads *Find an exercise*; **TN31** (device) reorder by the handle and
delete by a swipe on the phone.

---

## N5 — Say what should change (D94) — track

Reads: N1, SPEC §4.3, §6.19, §6.67, `PROMPT.md` §7. Owns the files in N1's table. This is the
*chatbot prompt per fragment* the v1.9 plan parked, built the other way round: not a prompt per
fragment, but one prompt that carries the whole plan and one sentence, and a review that shows the
difference.

### D94 — one field, the same trip, a review of what changed

- **The ··· on Plan detail** gains **Say what should change**, before *Edit the text*, for the plan
  on the page. It pushes **`ChangePlanView`**: a field that reads *What should change?* and holds the
  request, the strip small beneath, and `PromptButtons` with `Prompts.change(plan:request:settings:)`
  (disabled until something is typed). `Core/ChangeRequest.swift` is the screen: `struct
  ChangeRequest` with `request`, `stage`, `strip`, `buttons`, `diff: PlanDiff?`, `refusal`,
  `sent()`, `pasted(result:)`.
- **The paste** runs the pipeline as any plan (`PlanImport.run`), then **`PlanDiff.between(old:
  new:)`** (`Core/PlanDiff.swift`): days matched by name, then by position for the unmatched;
  within a day, exercises matched by name, then by position; the lines — `.replaced(day, old,
  new)` for a different name at a matched position, `.changed(day, name, from, to)` for the same
  name with different targets (`TargetText.summary` both sides), `.removed(day, name)`,
  `.added(day, exercise)`, `.dayAdded`, `.dayRemoved`, `.dayUnchanged(name)`. `count` is the lines
  that are not `.dayUnchanged`.
- **The review** is titled **2 changes** (*1 change*, *Nothing changed*): grouped by day with the
  day's square, a replaced exercise as the old name struck above the new in ink with the new
  targets, a removed one struck with *removed*, an added one with *added*, a changed one with its
  targets from and to, and an unchanged day as one grey line. *Worth knowing* stays. The button reads
  **Apply 2 changes**; *Nothing changed* has no button and the strip lit at *Chat* with the sentence
  *The reply is the plan as it was. Say it differently, or ask the chatbot again.*
- **Apply** is an edit, not a Replace: `AppModel.applyChange(planId:plan:)` keeps the plan's id, its
  import date, its cycle position and anchor **and its progression**, whose entries match by name as
  every edit's do (§6.21: *"Edits keep it"*; a renamed exercise simply stops matching) — the new text
  becomes the canonical rendering as D43's splice makes it. *(D43's "Replace drops it" stays true of
  Edit JSON's whole-plan replace; Apply is named as the exception in §6.21 and DECISIONS_LOG.)* A
  reply that is not a plan, or is cut short, is Refused with the sentence and *Ask for the whole
  plan* as N2's is; the fix-it prompt is the same `Prompts.render(errors:)`.

Not in this milestone: history in the change prompt (the request is about the plan), a change said
from Today's ··· (Plan detail's is the one door), and a diff of sets within an exercise beyond
`TargetText.summary`'s sentence.

Tests (proposed, `PlanDiffTests.swift`): **TN32** `PlanDiff.between` on the example: Bench →
Dumbbell Bench Press is `.replaced` in Push, Hammer Curl `.removed` in Pull, Legs `.dayUnchanged`,
`count` 2; the same plan twice is all `.dayUnchanged`, count 0; a day renamed is `.dayRemoved` +
`.dayAdded`; an exercise moved within a day is two lines, not none — named as the plan's choice, the
alternative being a `.moved` line; **TN33** `ChangeRequest`'s transitions: typed → ask; sent →
paste; a plan pasted → review with the diff; the same plan → *Nothing changed*, no button, `fixAt`
1; not a plan → refused; **TN34** the review's title and button by count: *1 change* / *Apply 1
change*, *2 changes* / *Apply 2 changes*; **TN35** `applyChange` keeps id, import date, cycle
position, anchor and the progression, with the renamed exercise's entry no longer matching and the
others still matching (extends X-series' edit-keeps-progression case); **TN36** (pin) `PROMPT.md`
§7's marker and its first sentence are what `Prompts.change` renders (extends M-section);
**TN37** (ui) the ··· item is *Say what should change*, the field's placeholder *What should
change?*, the diff rows old struck above new.

---

## N6 — The merge, dead code out, `BUILD_STATUS.md` — trunk

`git merge --no-ff` N2, N3, N4, N5 onto `v1.11-round-trip` in that order, the three routes and a
Release build after each merge, `check_release.py` at the end. Then, on the trunk: `DraftPlanView.swift`
deleted (and removed from the project with `tools/pbxproj_edit.py`); `PromptText.copyStep` and
`.mechanism` removed from `Core/Prompts.swift` if the introduction carries the sentence itself,
else moved there; `ImportView`'s `step(_:_:)` and `ProgressionView`'s twin gone; `Clipboard` kept
(Copy the prompt uses it); the lines the tracks left for the trunk resolved. `BUILD_STATUS.md` once,
for N0–N6. Tests: **TN38** (pin) no source file references `copyStep`, `mechanism`, `DraftPlanView`,
*Show text* or *Edit day as JSON*; the full suite green.

---

## N7 — Docs, checklist, bundle, 1.11

- SPEC: the amendments checked against what shipped, *(v1.10 …)* italics under each changed rule;
  §4.4 read once top to bottom as the screen now is.
- `TEST_CASES.md`: the TN rows renumbered as they landed. `DEVICE_CHECKLIST.md`: a **v1.11 rows**
  section (TN15, TN16, TN22, TN31, and one row for VoiceOver reading the strip's three marks).
- `DECISIONS_LOG.md` (the N7 lines: what N6 removed, the merge order, anything a track left);
  the v1.11 paragraph in `CLAUDE.md` and `AGENTS.md` rewritten for what shipped. `docs/PRIVACY.md`
  gains one sentence: the share sheet hands the prompt to the app you choose and nothing else leaves
  the phone.
- README: `docs/screenshots/add-plan.png` — the Ask state — added to the landing section as the
  screenshot this release changes; `tools/shot.sh` gains the screen.
- Version **1.11** on every target (`MARKETING_VERSION`, six places) and in `docs/APP_STORE.md`;
  the bundle regenerated (`tools/build_bundle.py`); Release build and `check_release.py` green.

---

## What this plan deliberately does not do

- **Read the clipboard on its own.** The stage is the app's, not the clipboard's: the Paste square
  lights because the prompt was sent, not because text arrived. `UIPasteboard.hasStrings` could
  light it without an alert; parked.
- **Talk to a chatbot.** No API, no key, no in-app browser. The share sheet is the whole of D88.
- **Change the pipeline, the format, the fixtures or the disk.** Every paste and edit runs the code
  that ran before; `examples/` and `examples/store/v1/` are untouched.
- **Redraw the D77 sheet.** It moves behind the ··· and changes nothing else; its titles lose the
  word JSON in N1.
- **A diff for Edit JSON's whole-plan replace**, or a change said from Today: named in N5.
- **The Workout screen, the Lock Screen, History, the calendar, the Summary, Settings**: untouched,
  which is what keeps four of the milestones independent.

## Parked

- **The Paste square lit by the clipboard** (`hasStrings`), as the one cue the stage cannot give.
- **A `.moved` diff line**, when two lines for a reorder read wrong on the phone.
- **A change said from Today's ···**, for the plan whose day is showing.
- **The intro page redrawn with the trip strip**, so the first explanation and the first screen are
  the same drawing.
- **Holding Ask until the share sheet completes** (UIKit's `UIActivityViewController` with a
  completion), if presenting-counts-as-sent proves wrong on the phone.
