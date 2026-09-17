import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// TN17–TN21 (v1.11, N3) — D92: Progression's planning screen as two rows of pre-marked tiles and
/// the trip (§6.60), no history switch, the reply reviewed as ladders, and **Start step 1**.
final class RoundTripProgressionTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let settings = CoreTestSupport.classic

    /// The plan's example, cut to what the ladders need: Push — Barbell Bench Press 4 × 6–8 at
    /// 80 kg, Overhead Press 3 × 8–10 at 40 kg, Lateral Raise 3 × 12–15 at 10 kg; Pull — Pull-up,
    /// bodyweight, 3 × 8–12; Legs — Squat 3 × 5 at 100 kg, which the reply leaves alone.
    private func plan() -> Plan {
        func lift(_ name: String, _ sets: Int, _ min: Int, _ max: Int, _ weight: Double?, bodyweight: Bool = false) -> Exercise {
            Exercise(name: name, repRange: RepRange(min: min, max: max), bodyweight: bodyweight,
                     sets: Array(repeating: SetTarget(work: .reps(.range(min: min, max: max)), weight: weight, restSeconds: 90),
                                 count: sets))
        }
        let squat = Exercise(name: "Squat", sets: Array(repeating: SetTarget(work: .reps(.fixed(5)), weight: 100, restSeconds: 180), count: 3))
        return Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation,
                    days: [Day(name: "Push", exercises: [lift("Barbell Bench Press", 4, 6, 8, 80),
                                                         lift("Overhead Press", 3, 8, 10, 40),
                                                         lift("Lateral Raise", 3, 12, 15, 10)]),
                           Day(name: "Pull", exercises: [lift("Pull-up", 3, 8, 12, nil, bodyweight: true)]),
                           Day(name: "Legs", exercises: [squat])],
                    importedAt: now, sourceText: "", cycle: [.day(0), .day(1), .day(2)])
    }

    /// Six steps: Bench climbs by weight and dips at the easier fourth step; Lateral Raise holds;
    /// Pull-up climbs by reps with a `{}` third step. Overhead Press is left out.
    private let reply = """
    Here is your progression:
    ```json
    {
      "steps": 6,
      "exercises": [
        { "day": "Push", "name": "Barbell Bench Press", "steps": [ { "weight": 82.5, "reps": "6-8" }, { "weight": 85 }, { "weight": 87.5 }, { "weight": 85, "reps": "8-10" }, { "weight": 90 }, { "weight": 92.5 } ] },
        { "day": "Push", "name": "Lateral Raise", "steps": [ {}, {}, {}, {}, {}, {} ] },
        { "day": "Pull", "name": "Pull-up", "steps": [ { "reps": "8-12" }, { "reps": "9-12" }, {}, { "reps": "10-12" }, { "reps": "11-13" }, { "reps": "12-15" } ] }
      ]
    }
    ```
    """

    private func read(_ text: String, mode: ProgressionMode) -> ProgressionImport.Result {
        ProgressionImport.run(text, plan: plan(), settings: settings, now: now, mode: mode)
    }

    // TN17: the tiles' defaults, marking them, and the stage machine ask → paste → review → started.
    func testTheTilesAndTheStages() throws {
        typealias Tile = ProgressionScreen.Tile
        var screen = ProgressionScreen()
        XCTAssertEqual(screen.stepTiles, [Tile(title: "4", marked: false), Tile(title: "6", marked: true),
                                          Tile(title: "8", marked: false), Tile(title: "12", marked: false)])
        XCTAssertEqual(screen.modeTiles, [Tile(title: "When I hit it", marked: true), Tile(title: "Every week", marked: false)])
        XCTAssertEqual(screen.stage, .ask)
        XCTAssertTrue(screen.editable)
        XCTAssertEqual(screen.strip, TripStrip.of(.ask))
        XCTAssertEqual(screen.buttons, TripButtons.ask())
        let six = screen.prompt(plan: plan(), history: [], settings: settings, now: now)
        XCTAssertTrue(six.contains("as 6 steps"))
        XCTAssertTrue(six.contains(Prompts.cadence(.performance)))

        // A tap marks, and the prompt says what is marked.
        screen.mark(steps: 8)
        screen.mark(mode: .calendar)
        screen.mark(steps: 5)
        XCTAssertEqual(screen.stepTiles.filter(\.marked).map(\.title), ["8"], "5 is not a tile")
        XCTAssertEqual(screen.modeTiles.filter(\.marked).map(\.title), ["Every week"])
        let eight = screen.prompt(plan: plan(), history: [], settings: settings, now: now)
        XCTAssertTrue(eight.contains("as 8 steps"))
        XCTAssertTrue(eight.contains("\"steps\": 8"))
        XCTAssertTrue(eight.contains(Prompts.cadence(.calendar)))
        XCTAssertFalse(eight.contains("as 6 steps"))
        XCTAssertFalse(eight.contains(Prompts.cadence(.performance)))

        // Send: Paste, the tiles dim and hold; Send the prompt again returns to Ask.
        screen.sent()
        XCTAssertEqual(screen.stage, .paste)
        XCTAssertFalse(screen.editable)
        XCTAssertEqual(screen.strip, TripStrip.of(.paste))
        XCTAssertEqual(screen.buttons, TripButtons.paste)
        screen.mark(steps: 4)
        screen.mark(mode: .performance)
        XCTAssertEqual(screen.steps, 8, "the tiles hold on Paste")
        XCTAssertEqual(screen.mode, .calendar)
        screen.restart()
        XCTAssertEqual(screen.stage, .ask)
        screen.mark(steps: 6)
        screen.mark(mode: .performance)
        XCTAssertEqual(ProgressionScreen().stepTiles, screen.stepTiles)
        screen.sent()

        // Refused: the prompt pasted back lights Paste; a reply that isn't one lights Chat.
        let prompt = screen.prompt(plan: plan(), history: [], settings: settings, now: now)
        screen.read(read(prompt, mode: screen.mode))
        XCTAssertEqual(screen.stage, .refused)
        XCTAssertEqual(screen.fixAt, 2)
        XCTAssertEqual(screen.strip.marks, [.done, .done, .now])
        XCTAssertNotNil(screen.refusal)
        XCTAssertEqual(screen.buttons, TripButtons.ask(), "the trouble goes back as the prompt")
        screen.read(read("   ", mode: screen.mode))
        XCTAssertEqual(screen.fixAt, 2, "nothing was pasted")
        screen.read(read("```json\n[1, 2]\n```", mode: screen.mode))
        XCTAssertEqual(screen.stage, .refused)
        XCTAssertEqual(screen.fixAt, 1)
        XCTAssertEqual(screen.strip.marks, [.done, .now, .todo])
        XCTAssertFalse(screen.editable, "a refusal does not reopen the tiles")
        screen.sent()
        XCTAssertEqual(screen.stage, .paste)
        XCTAssertNil(screen.refusal)

        // Review: the ladders' button, Cancel back to Paste, and Start once.
        screen.read(read(reply, mode: screen.mode))
        XCTAssertEqual(screen.stage, .review)
        XCTAssertEqual(screen.strip, TripStrip.of(.review))
        XCTAssertEqual(screen.buttons, TripButtons.effect("Start step 1"))
        XCTAssertTrue(screen.issues.allSatisfy { $0.severity == .warning })
        screen.cancelReview()
        XCTAssertEqual(screen.stage, .paste)
        XCTAssertNil(screen.progression)
        screen.read(read(reply, mode: screen.mode))
        let started = try XCTUnwrap(screen.start())
        XCTAssertTrue(screen.started)
        XCTAssertEqual(started.mode, .performance)
        XCTAssertEqual(started.weeks, 6)
        XCTAssertNil(screen.start(), "Start runs once")
        screen.read(read("   ", mode: .performance))
        XCTAssertEqual(screen.stage, .review, "nothing moves a started screen")
        screen.sent()
        screen.restart()
        XCTAssertEqual(screen.stage, .review)

        // The header says the mode once; the button says the mode's word.
        XCTAssertEqual(ProgressionScreen.header(started), "6 steps · when you hit it")
        var weekly = started
        weekly.mode = .calendar
        weekly.weeks = 1
        XCTAssertEqual(ProgressionScreen.header(weekly), "1 step · every week")
        XCTAssertEqual(ProgressionScreen.startTitle(.performance), "Start step 1")
        XCTAssertEqual(ProgressionScreen.startTitle(.calendar), "Start week 1")
    }

    // TN17 (the ···, D95): Edit the text opens on a reply that reads as it stands — or on the
    // last text read — named without "JSON", and a refusal in it marks its line.
    func testTheTextBehindTheMore() throws {
        let plan = plan()
        let point = ProgressionScreen.textPoint(plan: plan, steps: 6, text: " ")
        XCTAssertEqual(point.title, "The progression")
        XCTAssertEqual(point.saveTitle, "Review the steps")
        XCTAssertFalse((point.title + point.place + point.footer).contains("JSON"))
        let example = read(point.template, mode: .performance)
        XCTAssertEqual(example.errors, [])
        XCTAssertEqual(example.progression?.weeks, 6)
        XCTAssertEqual(example.progression?.entries.count, 5, "every exercise of the plan")
        XCTAssertEqual(ProgressionScreen.textPoint(plan: plan, steps: 6, text: reply).template, reply)

        let broken = point.template.replacingOccurrences(of: "\"Barbell Bench Press\", \"steps\": [{}, {}, {}, {}, {}, {}]",
                                                         with: "\"Barbell Bench Press\", \"steps\": \"lots\"")
        XCTAssertNotEqual(broken, point.template)
        let refused = read(broken, mode: .performance)
        XCTAssertFalse(refused.errors.isEmpty)
        let found = point.marks(for: refused.errors, in: broken)
        XCTAssertEqual(found.marked.map(\.line), [4], "the Bench line, counted from 1")
        XCTAssertEqual(found.unmarked, [])
    }

    // TN18: the prompt carries MY HISTORY whenever the plan has sessions, no block when it has
    // none, and nothing can say otherwise.
    @MainActor func testThePromptCarriesTheHistoryWheneverThereIsAny() async throws {
        let plan = CoreTestSupport.plan()
        let session = CoreTestSupport.completed(plan: plan)
        XCTAssertFalse(Prompts.progression(plan: plan, history: [], weeks: 6, settings: settings, now: now, mode: .performance)
            .contains("MY HISTORY"))
        let carried = Prompts.progression(plan: plan, history: [session], weeks: 6, settings: settings, now: now, mode: .performance)
        XCTAssertTrue(carried.contains("MY HISTORY"))
        XCTAssertTrue(carried.contains("Bench Press"))
        XCTAssertEqual(ProgressionScreen().prompt(plan: plan, history: [session], settings: settings, now: now), carried)

        // The app's prompt: none on a fresh store, the block once a workout is on disk.
        let root = CoreTestSupport.makeRoot("ProgressionHistory")
        defer { CoreTestSupport.discard(root) }
        let empty = AppModel(store: Store(root: root))
        await empty.load()
        _ = await empty.save(plan, makeActive: true)
        let id = try XCTUnwrap(empty.plans.first?.id)
        XCTAssertFalse(try XCTUnwrap(empty.progressionPrompt(for: id, weeks: 6, now: now)).contains("MY HISTORY"))

        try await Store(root: root).save(session: session)
        let model = AppModel(store: Store(root: root))
        await model.load()
        XCTAssertTrue(try XCTUnwrap(model.progressionPrompt(for: id, weeks: 6, now: now)).contains("MY HISTORY"))
        XCTAssertNil(model.progressionPrompt(for: UUID(), weeks: 6, now: now))

        guard let prompts = FixtureLoader.doc("JimmsBro/Core/Prompts.swift"),
              let app = FixtureLoader.doc("JimmsBro/Store/ProgressionModel.swift"),
              let view = FixtureLoader.doc("JimmsBro/Features/PlanDetail/ProgressionView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        for (name, source) in [("Prompts", prompts), ("ProgressionModel", app), ("ProgressionView", view)] {
            XCTAssertFalse(source.contains("includeHistory"), "\(name) has a history switch again")
        }
        XCTAssertFalse(view.contains("The prompt includes your last sessions"))
    }

    // TN19: the review's ladders — by weight, by reps, level — grouped by day with the day's colour.
    func testTheLadders() throws {
        let plan = plan()
        let progression = try XCTUnwrap(read(reply, mode: .performance).progression)
        let days = ProgressionLadder.of(progression, plan)
        XCTAssertEqual(days.map(\.dayName), ["Push", "Pull"], "Legs has nothing in the reply")
        XCTAssertEqual(days.map(\.colour), [DayColour.of(dayIndex: 0), DayColour.of(dayIndex: 1)])
        XCTAssertEqual(days[0].exercises.map(\.exerciseName), ["Barbell Bench Press", "Lateral Raise"])

        // Bench: 82.5, 85, 87.5, 85, 90, 92.5 — rises, dips at the easier step, the first lit.
        let bench = days[0].exercises[0]
        XCTAssertEqual(bench.measure, .weight)
        XCTAssertEqual(bench.bars.count, 6)
        XCTAssertEqual(bench.lit, 0)
        XCTAssertEqual(bench.first, "82.5 kg · 6–8")
        XCTAssertEqual(bench.bars[0], ProgressionLadder.floor, accuracy: 0.0001)
        XCTAssertLessThan(bench.bars[0], bench.bars[1])
        XCTAssertLessThan(bench.bars[1], bench.bars[2])
        XCTAssertLessThan(bench.bars[3], bench.bars[2], "the easier step dips")
        XCTAssertEqual(bench.bars[3], bench.bars[1], accuracy: 0.0001)
        XCTAssertLessThan(bench.bars[4], bench.bars[5])
        XCTAssertEqual(bench.bars[5], 1, accuracy: 0.0001)
        XCTAssertTrue(bench.bars.allSatisfy { (0...1).contains($0) })

        // Lateral Raise: nothing moves, so every bar is the same; step 1 is the plan's own.
        let raise = days[0].exercises[1]
        XCTAssertEqual(raise.measure, .level)
        XCTAssertEqual(raise.bars, Array(repeating: ProgressionLadder.level, count: 6))
        XCTAssertEqual(raise.first, "10 kg · 12–15")

        // Pull-up: bodyweight, so by the reps' lower bound; the {} step repeats the one before.
        let pullUp = days[1].exercises[0]
        XCTAssertEqual(pullUp.measure, .reps)
        XCTAssertEqual(pullUp.first, "reps · 8–12")
        XCTAssertEqual(pullUp.bars[2], pullUp.bars[1], accuracy: 0.0001, "{} repeats")
        XCTAssertEqual(pullUp.bars.first ?? -1, ProgressionLadder.floor, accuracy: 0.0001)
        XCTAssertEqual(pullUp.bars.last ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(pullUp.bars, pullUp.bars.sorted(), "never down")

        // A weight that holds while the reps climb climbs by reps; a hold climbs by its seconds.
        let row = Exercise(name: "Row", repRange: RepRange(min: 8, max: 10),
                           sets: Array(repeating: SetTarget(work: .reps(.range(min: 8, max: 10)), weight: 50, restSeconds: 90), count: 3))
        let rows = ProgressionLadder.of(ProgressionEntry(dayName: "Pull", exerciseName: "Row", weeks: [
            ProgressionWeek(), ProgressionWeek(work: .reps(.range(min: 10, max: 12)))]), exercise: row, units: .kg)
        XCTAssertEqual(rows.measure, .reps)
        XCTAssertEqual(rows.bars, [ProgressionLadder.floor, 1])
        XCTAssertEqual(rows.first, "50 kg · 8–10")
        let plank = Exercise(name: "Plank", bodyweight: true,
                             sets: Array(repeating: SetTarget(work: .duration(seconds: 45), weight: nil, restSeconds: 45), count: 3))
        let planks = ProgressionLadder.of(ProgressionEntry(dayName: "Core", exerciseName: "Plank", weeks: [
            ProgressionWeek(work: .duration(seconds: 50)), ProgressionWeek(work: .duration(seconds: 60))]),
                                          exercise: plank, units: .kg)
        XCTAssertEqual(planks.measure, .reps)
        XCTAssertEqual(planks.first, "50 s")
        XCTAssertEqual(ProgressionLadder.heights([]), [])
    }

    // TN20: the review's button reads Start step 1, and starting sets the progression at step 1.
    @MainActor func testStartStepOne() async throws {
        let root = CoreTestSupport.makeRoot("StartStepOne")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root))
        await model.load()
        _ = await model.save(plan(), makeActive: true)
        let id = try XCTUnwrap(model.plans.first?.id)

        var screen = ProgressionScreen()
        screen.sent()
        screen.read(model.runProgressionImport(reply, planId: id, now: now, mode: screen.mode))
        XCTAssertEqual(screen.buttons.primary, "Start step 1")
        let progression = try XCTUnwrap(screen.start())
        await model.setProgression(progression, for: id)

        let saved = try XCTUnwrap(model.plans.first?.progression)
        XCTAssertEqual(saved.mode, .performance)
        XCTAssertTrue(saved.entries.allSatisfy { $0.step == 0 && $0.tries == 0 })
        XCTAssertEqual(ProgressionText.status(saved, on: now), "Step 1 of 6")

        let reopened = AppModel(store: Store(root: root))
        await reopened.load()
        XCTAssertEqual(reopened.plans.first?.progression, saved, "on disk as it was started")
    }

    // TN21 (pin): the planning screen has no picker, no switch, no editor and no footer, and the
    // v1.10 words are gone from it.
    func testThePlanningScreenIsTilesAndTheTrip() throws {
        guard let view = FixtureLoader.doc("JimmsBro/Features/PlanDetail/ProgressionView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        for gone in ["Picker(", "Toggle(", "TextEditor(", "footer:", "PromptText.", "Copy prompt", "Copied",
                     "Paste progression", "Show text", "Use my history", "Save progression"] {
            XCTAssertFalse(view.contains(gone), "ProgressionView has \(gone) again")
        }
        for kept in ["ProgressionScreen", "TripStripView", "PromptButtons", "PasteButton", "RefusedBand",
                     "ProgressionLadder.of", "TripText.sendAgain", "TripText.editText", "Plan the next one"] {
            XCTAssertTrue(view.contains(kept), "ProgressionView lost \(kept)")
        }
    }
}
