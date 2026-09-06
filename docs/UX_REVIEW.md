# Jimm's Bro+ usability and product review

Reviewed September 5, 2026. These are recommendations, not accepted specification changes.

The next release should concentrate on a stable workout screen, easy corrections, and a clearer path from a plan to a workout. More analytics, modes, and customization would not resolve the main friction.

## Evidence and limits

This review uses the product specification, import format, prompts, test documentation, current SwiftUI views, AppModel, session engine, prefill rules, and saved simulator screenshots in build/. The captures show representative screens; they are earlier captures, not a new walkthrough of the current binary. Some details already differ from the source, such as preview singular/plural wording. Current source takes precedence for behavior.

Two small executable probes were compiled against the current Core sources and run successfully during this review:

- Skip set 0, then send editSet with a valid result: the set remains skipped with no result. This reproduces the mismatch between the edit sheet offered by the UI and the engine's refusal to edit an unlogged set.
- Import explicit weights 50, 60, 70 kg, log the first set at 50 kg, then request the second set's prefill with no history: the prefill is 50 kg despite a 60 kg target.

No app code or authoritative specification was changed. The complete XCTest suite was not rerun for this analysis. This is an expert review with two targeted behavior checks, not a usability study with participants. Priority reflects judgment about frequency, disruption, and implementation scope.

## Why it can feel clunky despite looking sparse

The app's original quiet-UI rules remove labels, hide nearly every secondary action, and make large numbers the main visual feature. This creates a sparse interface, but can remove the context people need to act confidently.

Five patterns recur:

1. **The layout changes while the user's task stays the same.** Logging, resting, and moving to another exercise use substantially different layouts and action positions.
2. **Control disappears at inconvenient times.** The rest screen hides access to the overview and corrections, even though rest is a natural time to check the last entry.
3. **The interface exposes technical structure.** JSON, field paths, rotation, group letters, and flattened step counts are more prominent than their practical meaning.
4. **Automation can conflict with intent.** Carrying forward a weight is useful for straight sets but surprising for explicitly programmed pyramids. Changing weight can also reset an untouched reps field.
5. **Some workflows stop short of completion.** Calendar dates do not navigate to sessions; import does not offer to activate a second plan; skipped-set editing silently does nothing.

Minimalism should remove effort and irrelevant information. Useful labels and visible access to common tasks can make an app feel simpler even when they add a few pixels. Nielsen Norman Group's discussion of minimalist interfaces specifically cautions against hiding content required for primary tasks. Its examples concern websites; applying the principle here is a design judgment, not a measured result for this app. [Source](https://www.nngroup.com/articles/characteristics-minimalism/)

## Priority order

| Order | Change | Expected benefit | Relative scope |
|---|---|---|---|
| 1 | Stable workout layout, inline rest, visible overview and minimize | Less searching and fewer interruptions every session | Medium–large |
| 2 | Immediate undo, reliable skipped-set recovery, explicit save failures | Corrections work and the app feels dependable | Medium |
| 3 | Respect intentionally different set targets; clarify prefill | Less fighting the inputs | Medium |
| 4 | Guided import, meaningful preview, explicit activation | Easier first use and plan replacement | Medium |
| 5 | Clearer Home and complete calendar interactions | Obvious next action, fewer dead ends | Small–medium |
| 6 | Consistent typography, labels, spacing, and accessible controls | More readable, cohesive presentation | Medium |
| 7 | Basic plan editing and “Do later” | Handles ordinary gym changes without another app | Medium–large |
| 8 | Small exercise-progress view and backup restoration | Useful feedback and data portability | Separate, medium features |
| 9 | Lock-screen Live Activity | More convenient rest checks if phone locking is frequent | Separate feature; validate demand |

Scope estimates are comparative, not delivery promises. Items 1–6 should precede a broad feature release. A narrow version of item 7 may be worth moving earlier if modifying plans is your most common frustration.

## 1. Keep the workout in one stable place

Current behavior: WorkoutView replaces the set card with RestOverlay, then uses TransitionView after an exercise block. The Log set button sits inside the card's scroll area, while Skip rest and Continue sit near the bottom. Timed sets put their primary action before the optional weight row.

Recommendation:

- Keep the exercise name, current set, input area, and main action in consistent positions.
- Show the current exercise's short set list: completed, current, and upcoming sets. Do not expand the entire workout onto the main screen.
- Present rest as a compact area attached to the workout. Keep the exercise and inputs visible; changing the next set's draft must not cancel rest.
- Place a clearly labeled Exercises action in the workout header. Use an overview sheet for the full sequence.
- Add a minimize control. Keep the active workout and timer running, with Resume visible in the app.
- During rest, put End rest in the same primary-action location. At expiry, return that location to Log set. Fixed and open work timers should reuse the same area for Start timer, Finish early, or Stop.
- Keep a reachable primary action above the keyboard. Make the supporting content scroll when needed.

This preserves the one-tap normal logging workflow. It does not require adding a Start set tap to every rep-based set.

The current rest screen has no overview or finish toolbar. That is a concrete access problem, not just a preference for a different layout. Workout presentation also lacks an explicit way to minimize back to the tabs while continuing the session.

**Between exercises:** Replace the full-screen completed-exercise duration with a brief completion message and the next exercise ready to view. A small “Moving on” elapsed value can remain for the original timing preference, but it should not require a separate Continue gate for rep-based work. Timed exercises still need an intentional Start timer action.

For a hypothetical workout with six separate exercises and three rep sets each, the existing design adds five Continue taps to eighteen Log set taps. Removing those gates saves five navigation actions; the more important gain is consistent context. This is an illustrative count, not a measured time saving.

Evidence: JimmsBro/Features/Workout/WorkoutView.swift, JimmsBro/Features/Rest/RestOverlay.swift, JimmsBro/Features/Transition/TransitionView.swift, JimmsBro/Features/Workout/TimerBlock.swift, JimmsBro/RootView.swift. Visuals: build/o9-step-card.png, build/o9c-rest.png, build/o32-done.png.

## 2. Make recovery immediate

An accidental log should have a brief “Set logged · Undo” affordance. Undo should restore the previous values, step status, and appropriate timer state. Editing an older result should leave the active rest timer running.

A skipped set should expose either “Do this set” or “Add result,” with the action actually supported by Core. Currently OverviewView opens EditResultSheet for every nonpending step, but SessionEngine.editSet returns immediately unless the set was logged. SessionDetailView similarly offers edits for skipped rows. The sheet dismisses after Save, creating the appearance of success without a change. The targeted probe confirmed this Core behavior.

Deleting a plan through its menu, and deleting from the Plans and History lists, currently have different confirmation behavior from deleting a session in detail. Standardize this: either provide reliable undo for ordinary deletion, or use a concise confirmation where recovery is unavailable. Keep the explicit delete-all confirmation.

Make write failures visible and recoverable. AppModel and SessionRunner suppress multiple write errors with try?. In persistCompletedSessions, a session is inserted into the persisted-ID set even if its save failed, and active-session clearing proceeds. I did not simulate a disk failure, but that control flow deserves correction before cosmetic polishing: only mark a session saved after a successful write, retain recoverable data, and offer Retry on failure.

Success feedback should be quiet. Do not add a confirmation dialog to every set.

Evidence: JimmsBro/Features/Overview/OverviewView.swift, JimmsBro/Features/SessionDetail/SessionDetailView.swift, JimmsBro/Core/SessionEngine.swift, JimmsBro/Features/Plans/PlansView.swift, JimmsBro/Features/History/HistoryView.swift, JimmsBro/Store/AppModel.swift, JimmsBro/Store/SessionRunner.swift.

## 3. Make input assistance predictable

Keep previous-session prefill and the optional progression suggestion. These are valuable shortcuts.

Revise the precedence for explicitly varied sets. A plan that deliberately programs 50 → 60 → 70 kg should not look like a repeated 50 kg workout after the first log. The current prefill deliberately prefers the previous logged weight in the same exercise; the probe confirmed the effect. Distinguish straight-set carry-forward from explicit per-set programming, and decide visibly whether an adjustment applies to “This set” or “Remaining sets.”

Avoid silently rewriting entered reps when weight changes. The current RepsDraft only protects reps once the user has edited them; otherwise it switches between historical reps and the target. A simpler starting point is to initialize the draft once and keep both values stable until the user changes them. If automatic rep adjustment is retained, make the changed value visibly understandable and test it with the owner.

Add the visible labels Reps and Weight or Load. Units explain scale but do not explain every number's purpose. Keep the target and previous result separate from the values about to be logged.

Remove duplicate history text. The current card can show a full “Last time” sequence including weight, plus another “Last 80 kg” line. A short set list with a previous-result column can communicate the relationship once.

Show progress in workout terms: “Exercise 2 of 5 · Set 2 of 3.” Drops should remain explicitly labeled as drops; supersets should show members and round position. The sample Push day contains 16 main sets and six drop steps, while the global header counts 22 “sets.” That internal flattening is useful for execution but can confuse progress at a glance.

Evidence: JimmsBro/Core/Prefill.swift, JimmsBro/Features/Workout/WorkoutView.swift, examples/valid/weekly-rotation.json and its manifest entry.

## 4. Make bringing in a plan feel guided

Keep the local JSON importer and chatbot workflow. They are useful capabilities and do not require a backend. Change the presentation.

The initial screen should explain the next action instead of presenting a large blank monospaced editor. Use “Add plan,” with Paste plan as the main path, plus a clearly named “Create with a chatbot” route and an Import file option.

For the chatbot route, show a short sequence: copy instructions, use them in your chatbot with your workout description, return and paste the reply. Preserve the draft while switching apps. A copied confirmation should briefly appear and then reset; the current button remains “Copied” for the lifetime of the view.

After pasting, show a human-readable preview. Prefer “Review plan” before “Save plan,” so users understand which action validates and which commits. Use one navigation flow rather than stacking a preview sheet over the import sheet.

The preview should allow inspection of exercises and varying set targets. It currently shows day names and counts, which cannot establish whether the chatbot produced the intended exercises, weights, or order.

Present errors at a useful level: “Bench Press, set 2 needs a rep target.” Put JSON paths and diagnostic codes under Details and retain them in the copyable repair prompt. Keep material warnings prominent. Warnings about a mismatched weight unit, removed load, or changed grouping deserve attention; stripping surrounding prose or ignoring an author field should not dominate a successful import.

Offer “Use as current plan” in the preview or save outcome, with the choice and current state clear. When another plan is already active, ImportView saves without makeActive and never asks. The new plan can be saved successfully while Home continues to show the old one.

Make replacement explicit from Plan detail. The specified Replace action is absent from the current menu, so users must discover same-name conflict handling through a fresh import.

Keep the sample plan available, but offer a short practice session before presenting the full advanced sample. The current sample's first day includes supersets, drops, and timed work. That makes it a useful regression fixture and a demanding introduction. Add a separate onboarding sample; do not modify the existing fixtures.

Evidence: JimmsBro/Features/Import/ImportView.swift, JimmsBro/Features/PlanDetail/PlanDetailView.swift, JimmsBro/Store/AppModel.swift, JimmsBro/Core/PlanLibrary.swift, docs/PROMPT.md. Visuals: build/o-import.png, build/o5-preview.png.

## 5. Make Home answer “What am I doing today?”

Lead with the selected plan, workout name, and a brief useful preview such as exercise count. Use “Start Push” or “Resume Push,” and make the workout name or Preview an obvious way to inspect it before starting. Provide a compact way to choose another day.

On a rest day, the primary copy should not pair “Rest day” with a generic Start that begins the next scheduled workout early. Say “Start Pull early” if that is the intended action, and keep the rest-day context clear.

Reduce the month calendar's default prominence. A compact current-week or recent-activity view plus an expandable month is worth testing. This is a proposal, not an assertion that the calendar has no value to you.

Complete the existing interactions before expanding calendar features. Tapping a date currently only toggles a text line; tapping again clears the selection. It cannot open the session detail or start the projected day, despite the documented design. On days with multiple sessions, the selected text chooses only the first. Make completed dates open the session or a short chooser.

Be cautious about projecting an event-driven rotation onto fixed dates. The existing projection makes assumptions about training every calendar day. Separate an actual weekday schedule from a flexible “next workout” sequence so the calendar does not suggest commitments the user never made.

Remove the tap-to-cycle six-metric sparkline from the default Home, or move metric selection into an explicit menu in History. Its interaction is hidden, and workout duration is not self-evidently a measure of progress. “2 workouts this week” is easier to understand without interpreting a line. Use wording that reports activity without implying that more duration is automatically better.

Keep the existing four native tabs for the first refinement. Moving Settings to a gear and using three tabs is optional; it would not fix the workout friction by itself.

Evidence: JimmsBro/Features/Home/HomeView.swift, JimmsBro/Core/HomeCard.swift, JimmsBro/Core/CalendarProjection.swift. Visuals: build/o29-home-seeded.png and build/o30-rest-dots.png.

## 6. Establish a coherent visual hierarchy

The blue accent and native controls are a sound starting point. The main visual work is composition:

- Use one shared spacing scale and consistent horizontal margins.
- Give the active exercise and editable values clear emphasis; use readable secondary text for targets and context.
- Reserve the largest countdown for timed work when watching it matters. A completed exercise's duration should not dominate the next action.
- Make control shapes and positions consistent across reps, timed work, rest, and completion.
- Give tappable names and disclosure rows a clear affordance. Decorative chips should not look like unexplained navigation.
- Use semantic color: accent for actions/current state, subdued neutrals for context, warning treatment for a meaningful issue.
- Use restrained pressed states and feedback. StepButton is an Image with gestures and has no explicit pressed appearance.
- Retain native navigation and familiar icons where they aid recognition. The blanket prohibition on icon-plus-text pairs is unnecessarily strict.

Plan detail should start with compact day rows and expand the selected day, rather than rendering every exercise from every day in a long list. Its exercise summary currently formats every set using only the first target: the sample's 24, 26, 28 kg incline sets are summarized as three sets at 24 kg. Show a per-set variation summary or expand the individual targets.

Accessibility is part of the professional finish. Calendar cells are assigned a 30-point height without a 44-point minimum target. Some small controls also need measurement. Apple's interface guidance recommends at least 44 × 44 points for touch controls. [Source](https://developer.apple.com/design/tips/)

Do not solve larger text by shrinking the most useful numbers: StepperRow currently uses 34-point numbers at accessibility sizes versus 44 normally. Reflow the layout, keep essential controls reachable, and verify the exercise-history action with VoiceOver. A combined accessibility label is not sufficient evidence that the link remains operable. Apple's Dynamic Type guidance emphasizes accommodating the user's text-size choice. [Source](https://developer.apple.com/videos/play/wwdc2024/10074/)

Visuals: build/o9-step-card.png, build/o18-dynamic-type.png, build/o-plandetail.png.

## 7. Make the summary useful in one glance

Show “Workout saved,” the day name, duration, and completed sets. Include one or two meaningful comparisons when the data supports them, then let users open details.

The current summary presents sequences such as “8@80, 8@80 … · last 10@80 …” in small text. Replace that with readable comparisons: “Bench press: 2 more reps at the same weight,” or a compact aligned table when loads vary. Do not invent a positive comparison when the session is not comparable.

Label total volume as Volume. A number followed only by kg can look like a lifted weight rather than reps multiplied by weight. Omit irrelevant zero volume for an entirely bodyweight or timed session.

Automatic rep-set duration includes time between the card appearing and the log tap. It cannot reliably measure actual lifting time. Demote it from the default summary and transition screen; if retained, describe it honestly. Timed exercise results remain directly useful.

Evidence: JimmsBro/Features/Summary/SummaryView.swift, JimmsBro/Core/Stats.swift, JimmsBro/Core/SessionEngine.swift. Visual: build/o13-summary.png.

## Small feature additions worth considering

**Basic plan editing.** Edit exercise names, sets, targets, load, and rest; reorder exercises; duplicate a day. This removes the need to return to a chatbot for a small change. Keep the import format and avoid building a large exercise catalog. Export/copy should represent the current edited plan, not stale sourceText.

**Do later.** When equipment is occupied, move the exercise later in the current workout while preserving it as pending. This is more useful than forcing the user to skip it or navigate individual pending sets. Add substitution only if needed; actual substitute exercises must keep their own history identity.

**A small exercise-progress view.** Make exercise lookup direct in History, then add one meaningful chart with readable units and a short result list. Do not start with a multi-metric dashboard. The Core history query already exists, but presentation and comparability still need design.

**Restore backup.** Export is already present, but there is no in-app restore. Complete that loop with validation, a preview, and a clear merge/replace choice. This can remain in Settings without adding daily interface clutter.

**Live Activity, later.** If checking rest while the phone is locked is frequent, this would be a useful convenience. It should follow the in-app flow fixes and accompany physical-device validation.

Warm-up support, session notes, per-exercise weight increments, and a plate calculator may help particular routines. Add them only when a recurring use case justifies them.

## Features and presentation to remove or postpone

Remove the mandatory full-screen exercise-completion gate, duplicated last-weight text, hidden chart-metric cycling, and prominent low-consequence import diagnostics. Demote automatic rep-set timing and dense summary dumps.

Postpone social feeds, badges, streak pressure, calorie estimates, nutrition, recovery scores, an in-app chatbot, broad exercise video libraries, extensive themes, automatic progression changes, and a large analytics dashboard. These do not solve the friction visible in the current flows.

Preserve local storage, no account requirement, Date-based timers, session snapshots, previous-result prefill, optional progression advice, supersets, drops, timed work, and export. Simplify how these capabilities are presented.

## How to validate the redesign

Before implementing a broad redesign, use the proposed workout direction for a focused owner walkthrough, then test a small SwiftUI slice on the simulator and iPhone.

Suggested acceptance criteria, not results already achieved:

1. From Home, start the intended workout without guessing which plan is active.
2. Log a normal prefilled rep set in one tap.
3. Correct the immediately previous set in at most two deliberate actions, while rest continues.
4. Recover a skipped set and verify the result survives reopening the session.
5. Inspect all exercises with one visible action during work and rest.
6. Minimize and resume with the exact active state preserved.
7. Run a pyramid with explicitly different target weights without fighting prefill.
8. Import a second plan, understand any material warning, and choose whether to activate it.
9. Tap a completed calendar day and reach the correct session, including a day with two workouts.
10. Complete the main tasks at large text sizes, with the keyboard visible, and with VoiceOver.
11. Simulate a persistence failure and verify the app retains recoverable data and offers a truthful retry.
12. Check timers, sound, locking, and one-handed use on the physical phone.

Ask a few people unfamiliar with the app to perform the same tasks without coaching. Record hesitation, wrong turns, and failed recovery as well as taps. Treat a small round as directional feedback, not a statistically representative verdict.

For implementation, revise the conflicting sections of SPEC and TEST_CASES first, then preserve the Core/view separation and finish each scoped milestone with appropriate automated and simulator checks. Existing tests establish conformance to previous rules; they do not establish that those rules produce an intuitive product.
