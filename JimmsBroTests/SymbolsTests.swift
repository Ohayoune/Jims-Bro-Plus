import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// v1.10 (`docs/ITERATION_11_PLAN.md`) — the Workout screen in symbols. P1: three states, three
/// colours (D79, SPEC §6.52) and the header is the bar (D80, §6.53): TP1–TP6. TP7 is the phone's.
/// P2: the exercise in symbols (D81, §6.54): TP8–TP15. TP16 is the phone's.
/// P3: the walk, a count-up and a ring (D82, §6.55): TP17–TP22. TP23 is the phone's.
/// P4: pages (D83, §6.56): TP24–TP28. TP29 is the phone's.
/// P5: a bar that learns your pace (D84, §6.57): TP30–TP34. TP35 is the phone's.
/// P6: Change *day* in squares (D85, §6.58) is TP36–TP39, in `SwapTests` beside Q4's picker;
/// squares that join (D86, §6.59) are TP40–TP41 here. TP42 is the phone's.
final class SymbolsTests: XCTestCase {
    private let now = CoreTestSupport.now

    /// The plan's example: Push Pull Legs, and Push's five exercises.
    private func pushPullLegs() -> Plan {
        func lift(_ name: String, _ sets: Int, _ low: Int, _ high: Int, _ weight: Double) -> Exercise {
            Exercise(name: name, repRange: RepRange(min: low, max: high),
                     sets: Array(repeating: SetTarget(work: .reps(.range(min: low, max: high)),
                                                      weight: weight, restSeconds: 90), count: sets))
        }
        let plank = Exercise(name: "Plank", bodyweight: true,
                             sets: Array(repeating: SetTarget(work: .openDuration(minSeconds: 30),
                                                              restSeconds: 60), count: 3))
        let push = Day(name: "Push", exercises: [
            lift("Barbell Bench Press", 4, 6, 8, 80), lift("Incline Dumbbell Press", 3, 8, 10, 26),
            lift("Lateral Raise", 3, 12, 15, 10), lift("Tricep Pushdown", 3, 10, 12, 30), plank])
        let pull = Day(name: "Pull", exercises: [lift("Barbell Row", 3, 8, 10, 60)])
        let legs = Day(name: "Legs", exercises: [lift("Back Squat", 3, 5, 8, 100)])
        return Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation, days: [push, pull, legs],
                    importedAt: now, sourceText: "", cycle: [.day(0), .day(1), .day(2), .rest])
    }

    /// Bench is done; Incline's first set is logged at 10, and its second is the one on.
    private func example(settings: Settings = CoreTestSupport.classic) throws -> SessionEngine {
        let session = try XCTUnwrap(Session.start(plan: pushPullLegs(), dayIndex: 0, now: now))
        var engine = SessionEngine(session: session, settings: settings, now: now)
        for step in 0..<5 {
            engine.apply(.logSet(step: step, result: .reps(count: step < 4 ? 8 : 10, weight: step < 4 ? 80 : 26)),
                         now: now.addingTimeInterval(Double(step + 1) * 150))
        }
        return engine
    }

    private func screen(_ engine: SessionEngine, at seconds: Double = 800) throws -> WorkoutScreenModel {
        try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                          now: now.addingTimeInterval(seconds)))
    }

    // TP1 (D79): one rule for every step — pending ahead is not yet, the step the workout is on
    // is now, logged is done, skipped is not yet, and a skipped step given a result is done.
    func testTheStateOfEveryStep() throws {
        var engine = try example()
        guard case let .resting(rest) = engine.phase else { return XCTFail("a logged set starts a rest") }
        XCTAssertEqual(rest.nextStep, 5)
        XCTAssertEqual(MarkState.of(step: 0, session: engine.active), .done, "logged")
        XCTAssertEqual(MarkState.of(step: 4, session: engine.active), .done, "logged")
        XCTAssertEqual(MarkState.of(step: 5, session: engine.active), .now, "the step a rest leads to")
        XCTAssertEqual(MarkState.of(step: 6, session: engine.active), .todo, "pending ahead")
        XCTAssertEqual(MarkState.of(step: 15, session: engine.active), .todo, "pending ahead")
        XCTAssertEqual(MarkState.of(step: 99, session: engine.active), .todo, "no such step")

        engine.apply(.skipSet(step: 5), now: now.addingTimeInterval(900))
        XCTAssertEqual(MarkState.of(step: 5, session: engine.active), .todo, "a skip never happened")
        XCTAssertEqual(MarkState.of(step: 6, session: engine.active), .now, "the working step")
        XCTAssertEqual(engine.active.currentStep, 6)

        engine.apply(.editSet(step: 5, result: .reps(count: 9, weight: 26)), now: now.addingTimeInterval(950))
        XCTAssertEqual(MarkState.of(step: 5, session: engine.active), .done, "a skipped step given a result")
        XCTAssertEqual(MarkState.of(step: 6, session: engine.active), .now, "an edit moves nothing")

        // Every step has exactly one state, and exactly one step is now.
        let states = engine.session.steps.indices.map { MarkState.of(step: $0, session: engine.active) }
        XCTAssertEqual(states.filter { $0 == .now }.count, 1)
        XCTAssertEqual(MarkState.allCases.map(\.rawValue), ["done", "now", "todo"])

        // The dots the screen draws take the same rule (D81).
        let dots = try screen(engine, at: 960).dots
        XCTAssertEqual(dots.map(\.state), [.done, .done, .now], "Incline's three dots")
    }

    // TP2 (D79, extends T23): three state colours — done the day's, grey without one; now the
    // accent; not yet the system's fill — none red, amber or yellow; the Lock Screen's bar done
    // in the day's colour, never the accent or a fixed green. Source reads on the host routes.
    func testThreeStateColours() throws {
        guard let square = FixtureLoader.doc("JimmsBro/DaySquare.swift"),
              let activity = FixtureLoader.doc("JimmsBroActivity/WorkoutLiveActivity.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        let mapping = try XCTUnwrap(Self.block(square, from: "extension MarkState {", to: "\n}\n"))
        XCTAssertTrue(mapping.contains("case .done: return day?.color ?? DaySquare.noColour"))
        XCTAssertTrue(mapping.contains("case .now: return .accentColor"))
        XCTAssertTrue(mapping.contains("case .todo: return Color(.secondarySystemFill)"))
        XCTAssertEqual(mapping.components(separatedBy: "case .").count - 1, 3, "three states, three colours")
        for forbidden in [".red", ".yellow", ".orange", "amber", ".green"] {
            XCTAssertFalse(mapping.contains(forbidden), forbidden)
        }
        XCTAssertTrue(square.contains("static let noColour = Color.secondary.opacity(0.4)"),
                      "done with no day colour is the grey History draws")

        let progress = try XCTUnwrap(Self.block(activity, from: "private func progress(", to: "\n    }\n"))
        XCTAssertTrue(progress.contains(".tint(MarkState.done.color(day: state.dayColour))"))
        XCTAssertFalse(progress.contains("accentColor"))
        XCTAssertFalse(progress.contains(".green"))
    }

    // TP3 (D80): the bar on the example — five segments of 4/3/3/3/3 marks weighted by their
    // set counts, Bench's four done, Incline's first done and second now, the other ten not yet,
    // and the caret under Incline.
    func testTheBarOnTheExample() throws {
        let engine = try example()
        let bar = try screen(engine).bar
        XCTAssertEqual(bar, WorkoutBar.of(session: engine.active), "the screen's bar is the Core one")
        XCTAssertEqual(bar.segments.map(\.sets.count), [4, 3, 3, 3, 3])
        XCTAssertEqual(bar.segments.map(\.weight), [4, 3, 3, 3, 3], "widths by set count with no history (D84)")
        XCTAssertEqual(bar.segments.map(\.blockIndex), [0, 1, 2, 3, 4])
        XCTAssertEqual(bar.segments[0].sets, [.done, .done, .done, .done])
        XCTAssertEqual(bar.segments[1].sets, [.done, .now, .todo])
        let all = bar.segments.flatMap(\.sets)
        XCTAssertEqual(all.filter { $0 == .done }.count, 5)
        XCTAssertEqual(all.filter { $0 == .now }.count, 1)
        XCTAssertEqual(all.filter { $0 == .todo }.count, 10)
        XCTAssertEqual(bar.segments.map(\.caret), [false, true, false, false, false])

        // Looking at another block moves the caret and nothing else (P4's pages).
        let looked = WorkoutBar.of(session: engine.active, showing: 3)
        XCTAssertEqual(looked.segments.map(\.caret), [false, false, false, true, false])
        XCTAssertEqual(looked.segments.map(\.sets), bar.segments.map(\.sets))

        // "Do later" moves a block's segment with it, keeping its index.
        var deferred = try example()
        deferred.apply(.deferExercise(exerciseIndex: 2), now: now.addingTimeInterval(820))
        let moved = WorkoutBar.of(session: deferred.active)
        XCTAssertEqual(moved.segments.map(\.blockIndex), [0, 1, 3, 4, 2])
    }

    // TP4 (D80): a skipped set counts for the fill — the day's progress moves past it — but it
    // draws not yet, in place, and the now moves on.
    func testASkippedSetFillsButDrawsNotYet() throws {
        var engine = try example()
        let before = try screen(engine).completion
        engine.apply(.skipSet(step: 5), now: now.addingTimeInterval(900))
        let after = try screen(engine, at: 910)
        XCTAssertEqual(before, 5.0 / 16, accuracy: 1e-9)
        XCTAssertEqual(after.completion, 6.0 / 16, accuracy: 1e-9, "the skip counts for the fill (D34)")
        XCTAssertEqual(after.bar.segments[1].sets, [.done, .todo, .now], "and draws grey, no mark moved")
        XCTAssertEqual(after.bar.segments.flatMap(\.sets).filter { $0 == .done }.count, 5,
                       "the bar never says a skipped set happened")
    }

    // TP5 (D80, extends O50): the same five zones in every state, one caret and one now on the
    // bar, and the header's spoken line is the stage in words, exactly as D34 wrote it.
    func testTheHeaderSpeaksTheStage() throws {
        let warmUp = Settings(warmUpSeconds: 300, transitionRestSeconds: 120)
        let session = try XCTUnwrap(Session.start(plan: pushPullLegs(), dayIndex: 0, now: now))
        var engine = SessionEngine(session: session, settings: warmUp, now: now)
        var screens: [(String, WorkoutScreenModel)] = []
        let warm = try screen(engine, at: 10)
        XCTAssertEqual(warm.spokenHeader, "Warm-up")
        screens.append(("warm-up", warm))

        engine.apply(.skipRest, now: now.addingTimeInterval(20))
        let working = try screen(engine, at: 30)
        XCTAssertEqual(working.spokenHeader, "Exercise 1 of 5 · Set 1 of 4")
        screens.append(("working", working))

        engine.apply(.logSet(step: 0, result: .reps(count: 8, weight: 80)), now: now.addingTimeInterval(60))
        let resting = try screen(engine, at: 70)
        XCTAssertEqual(resting.spokenHeader, "Resting")
        screens.append(("resting", resting))

        for step in 1...3 {
            engine.apply(.logSet(step: step, result: .reps(count: 8, weight: 80)), now: now.addingTimeInterval(Double(60 + step * 100)))
        }
        let walking = try screen(engine, at: 420)
        XCTAssertEqual(walking.spokenHeader, "Between exercises")
        XCTAssertEqual(walking.bar.segments.map(\.caret), [false, true, false, false, false],
                       "the walk's caret is on the exercise it leads to")
        screens.append(("between exercises", walking))

        for step in 4...12 {
            engine.apply(.logSet(step: step, result: .reps(count: 10, weight: 20)), now: now.addingTimeInterval(Double(500 + step * 100)))
        }
        engine.apply(.skipRest, now: now.addingTimeInterval(1800))
        engine.apply(.startTimer(step: 13), now: now.addingTimeInterval(1810))
        let timed = try screen(engine, at: 1840)
        XCTAssertNotNil(timed.timer)
        XCTAssertEqual(timed.bar.segments.map(\.caret), [false, false, false, false, true])
        screens.append(("timed", timed))

        for (name, model) in screens {
            XCTAssertEqual(model.zones, [.header, .exercise, .inputs, .strip, .primary], name)
            XCTAssertEqual(model.spokenHeader, model.stage.title, name)
            XCTAssertEqual(model.bar.segments.filter(\.caret).count, 1, name)
            XCTAssertEqual(model.bar.segments.flatMap(\.sets).filter { $0 == .now }.count, 1, name)
            XCTAssertEqual(model.bar.segments.count, 5, name)
        }
    }

    // TP6 (D80, pin): zone 1 prints no words but the elapsed time — no stage, no percentage, no
    // progress line, no Exercises — draws the bar, speaks the stage, and opens the Overview; the
    // screen's primary button is ink and its controls take ink, not the accent (D79).
    func testZoneOneHasNoWordsButTheElapsedTime() throws {
        guard let view = FixtureLoader.doc("JimmsBro/Features/Workout/WorkoutView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        let zone = try XCTUnwrap(Self.block(view, from: "// MARK: - Zone 1", to: "// MARK: - Zone 2"))
        let code = zone.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertEqual(code.components(separatedBy: "Text(").count - 1, 1, "one Text in zone 1")
        XCTAssertTrue(code.contains("Text(screen.elapsed)"))
        for gone in ["stage.title", "progressLine", "\"Exercises\"", "ProgressView", "percent\")", " Label(\""] {
            XCTAssertFalse(code.contains(gone), gone)
        }
        for kept in ["BarView(bar: screen.bar, day: dayColour)", ".accessibilityLabel(screen.spokenHeader)",
                     "showOverview = true", "DaySquare(colour: dayColour)", "Image(systemName: \"chevron.down\")",
                     "Image(systemName: \"ellipsis\")"] {
            XCTAssertTrue(code.contains(kept), kept)
        }
        XCTAssertTrue(view.contains("PrimaryButton(title: screen.primary.title, systemImage: primaryMark, enabled: primaryEnabled,\n                              ink: true)"))
        XCTAssertTrue(view.contains(".tint(.primary)"))
        XCTAssertTrue(view.contains("Canvas {"), "the bar is one Canvas, not a view per set")
    }

    // MARK: - P2 (D81): the exercise in symbols

    /// Last week's Push: Bench 10, 9, 8, 8 at 80 and Incline 10, 9, 8 at 26 — Incline's second
    /// set reached 9.
    private func lastWeek() throws -> Session {
        let start = now.addingTimeInterval(-7 * 86_400)
        var last = try XCTUnwrap(Session.start(plan: pushPullLegs(), dayIndex: 0, now: start))
        for (i, reps) in [10, 9, 8, 8, 10, 9, 8].enumerated() {
            last.steps[i].status = .logged
            last.steps[i].result = .reps(count: reps, weight: i < 4 ? 80 : 26)
            last.steps[i].loggedAt = start.addingTimeInterval(Double(i + 1) * 150)
        }
        last.endedAt = start.addingTimeInterval(1_200)
        return last
    }

    private func solid(_ cells: [RepCells.Cell]) -> Int { cells.filter { $0.fill == .solid && !$0.over }.count }
    private func faint(_ cells: [RepCells.Cell]) -> Int { cells.filter { $0.fill == .faint && !$0.over }.count }
    private func where_(_ cells: [RepCells.Cell], _ test: (RepCells.Cell) -> Bool) -> [Int] {
        cells.indices.filter { test(cells[$0]) }
    }

    // TP8 (D81): a target's cells — solid to the minimum, faint to the top, the caret under the
    // number in the field, a gap after every fifth, yellow and faint past the top.
    func testTheCellsOfATarget() {
        let range = RepCells.Bounds(minimum: 8, maximum: 10)
        let ten = RepCells.target(range, reps: 10).cells
        XCTAssertEqual(ten.count, 10)
        XCTAssertEqual(solid(ten), 8)
        XCTAssertEqual(faint(ten), 2)
        XCTAssertEqual(where_(ten, \.caret), [9], "the caret under the tenth")
        XCTAssertEqual(ten.map(\.group), [0, 0, 0, 0, 0, 1, 1, 1, 1, 1], "one gap, after the fifth")
        XCTAssertTrue(where_(ten, \.over).isEmpty)
        XCTAssertTrue(where_(ten, \.last).isEmpty, "no last time, no line")

        let twelve = RepCells.target(range, reps: 12).cells
        XCTAssertEqual(twelve.count, 12)
        XCTAssertEqual(where_(twelve, \.over), [10, 11], "two yellow past the top")
        XCTAssertEqual(twelve.filter(\.over).map(\.fill), [.faint, .faint], "translucent: a target")
        XCTAssertEqual(where_(twelve, \.caret), [11])

        let six = RepCells.target(range, reps: 6).cells
        XCTAssertEqual(six.count, 10, "under the minimum the caret moves and the cells stay")
        XCTAssertEqual(where_(six, \.caret), [5])
        XCTAssertTrue(where_(RepCells.target(range, reps: nil).cells, \.caret).isEmpty, "no number, no caret")

        let eight = RepCells.target(RepCells.Bounds(minimum: 8, maximum: 8), reps: 8).cells
        XCTAssertEqual(eight.count, 8)
        XCTAssertEqual(solid(eight), 8, "a range of one: solid, and nothing faint")

        let open = RepCells.Bounds(minimum: 10, maximum: nil)
        XCTAssertEqual(RepCells.target(open, reps: nil).cells.map(\.fill), Array(repeating: .solid, count: 10),
                       "no top: the minimum alone")
        let more = RepCells.target(open, reps: 13).cells
        XCTAssertEqual(faint(more), 3, "past a minimum with no top is faint, never yellow")
        XCTAssertTrue(where_(more, \.over).isEmpty)

        // Last time past everything else still gets its cell.
        let reached = RepCells.target(range, reps: 9, lastTime: 11).cells
        XCTAssertEqual(reached.count, 11)
        XCTAssertEqual(where_(reached, \.last), [10])
        XCTAssertEqual(RepCells.target(range, reps: 999).cells.count, RepCells.maximumCells, "capped")

        // The bounds a target draws, and how the card writes them.
        XCTAssertEqual(RepCells.Bounds.of(.reps(.fixed(10)), range: RepRange(min: 8, max: 12)),
                       RepCells.Bounds(minimum: 8, maximum: 12), "a fixed count in a range draws the range")
        XCTAssertEqual(RepCells.Bounds.of(.reps(.fixed(5)), range: nil), RepCells.Bounds(minimum: 5, maximum: 5))
        XCTAssertEqual(RepCells.Bounds.of(.reps(.amrap(min: nil)), range: nil), RepCells.Bounds(minimum: 0, maximum: nil))
        XCTAssertEqual(RepCells.Bounds.of(.duration(seconds: 45), range: nil), RepCells.Bounds(minimum: 45, maximum: 45))
        XCTAssertEqual(RepCells.Bounds.of(.openDuration(minSeconds: 30), range: nil), RepCells.Bounds(minimum: 30, maximum: nil))
        XCTAssertEqual(SetCard.range(range), "8–10")
        XCTAssertEqual(SetCard.range(RepCells.Bounds(minimum: 8, maximum: 8)), "8")
        XCTAssertEqual(SetCard.range(open), "10+")
        XCTAssertEqual(SetCard.range(RepCells.Bounds(minimum: 0, maximum: nil)), "max")
    }

    // TP9 (D81): a logged set is solid to what was done, and yellow solid past the range.
    func testTheCellsOfALoggedSet() {
        let range = RepCells.Bounds(minimum: 8, maximum: 10)
        let twelve = RepCells.logged(range, result: 12).cells
        XCTAssertEqual(twelve.count, 12)
        XCTAssertEqual(solid(twelve), 10)
        XCTAssertEqual(where_(twelve, \.over), [10, 11])
        XCTAssertEqual(twelve.filter(\.over).map(\.fill), [.solid, .solid], "yellow solid: it happened")
        XCTAssertTrue(where_(twelve, \.caret).isEmpty)

        let six = RepCells.logged(range, result: 6).cells
        XCTAssertEqual(six.count, 10)
        XCTAssertEqual(solid(six), 6)
        XCTAssertEqual(faint(six), 4)
        XCTAssertTrue(where_(six, \.over).isEmpty, "none yellow")
    }

    // TP10 (D81): a timed set draws a cell per five seconds, rounded up.
    func testTheCellsOfATimedSet() {
        XCTAssertEqual(RepCells.secondsPerCell, 5)
        let range = RepCells.Bounds(minimum: 30, maximum: 45)
        let hold = RepCells.timed(range, seconds: nil).cells
        XCTAssertEqual(hold.count, 9)
        XCTAssertEqual(solid(hold), 6)
        XCTAssertEqual(faint(hold), 3)
        XCTAssertTrue(where_(hold, \.caret).isEmpty, "a hold has no field")

        let fifty = RepCells.timed(range, seconds: 50, logged: true).cells
        XCTAssertEqual(fifty.count, 10)
        XCTAssertEqual(fifty.map(\.fill), Array(repeating: .solid, count: 10))
        XCTAssertEqual(where_(fifty, \.over), [9], "the tenth yellow")

        XCTAssertEqual(RepCells.timed(RepCells.Bounds(minimum: 32, maximum: 32), seconds: nil).cells.count, 7,
                       "rounded up")
        XCTAssertEqual(where_(RepCells.timed(range, seconds: nil, lastTime: 41).cells, \.last), [8])
    }

    // TP11 (D81): the card on the example — Incline's 8–10 at 26 kg in blue, its caret under the
    // number in the field, a line over the 9 last time reached; none with no last time.
    func testTheCardCarriesLastTime() throws {
        let engine = try example()
        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [lastWeek()],
                                                       now: now.addingTimeInterval(800)))
        let card = screen.card
        XCTAssertEqual(card.range, "8–10")
        XCTAssertEqual(card.weight, "26 kg")
        XCTAssertNil(card.unit)
        XCTAssertEqual(card.colour, .now)
        XCTAssertEqual(card.lastTime, 9)
        XCTAssertEqual(where_(card.cells.cells, \.last), [8], "the line over the ninth")
        let field = try XCTUnwrap(Int(screen.inputs.reps))
        XCTAssertEqual(where_(card.cells.cells, \.caret), [field - 1], "the number and the cells agree")

        let typed = card.showing(field: 7)
        XCTAssertEqual(where_(typed.cells.cells, \.caret), [6], "the caret follows the field")
        XCTAssertEqual(where_(typed.cells.cells, \.last), [8])
        XCTAssertEqual(typed.cells.cells.count, 10)

        let fresh = try self.screen(engine)
        XCTAssertNil(fresh.card.lastTime)
        XCTAssertTrue(where_(fresh.card.cells.cells, \.last).isEmpty, "no last time, no line")

        // Plank: a hold with a minimum and no top.
        let plank = try XCTUnwrap(SetCard.of(session: engine.session, step: 13, history: [], colour: .now, field: 30))
        XCTAssertEqual(plank.range, "30+")
        XCTAssertEqual(plank.unit, "sec")
        XCTAssertNil(plank.weight, "bodyweight")
        XCTAssertEqual(plank.cells.cells.count, 6)
        XCTAssertTrue(where_(plank.cells.cells, \.caret).isEmpty)
    }

    // TP12 (D81): the dots — a step each, in order, in D79's states, a skip slashed; a drop is a
    // step and so a dot; a superset's rounds in order; the exercise's own dot.
    func testTheDotsOnTheExample() throws {
        var engine = SessionEngine(session: try XCTUnwrap(Session.start(plan: pushPullLegs(), dayIndex: 0, now: now)),
                                   settings: CoreTestSupport.classic, now: now)
        for step in 0..<3 {
            engine.apply(.logSet(step: step, result: .reps(count: 8, weight: 80)), now: now.addingTimeInterval(Double(step + 1) * 150))
        }
        XCTAssertEqual(try screen(engine, at: 500).dots.map(\.state), [.done, .done, .done, .now], "Bench")

        engine = try example()
        let incline = try screen(engine)
        XCTAssertEqual(incline.dots.map(\.step), [4, 5, 6])
        XCTAssertEqual(incline.dots.map(\.state), [.done, .now, .todo], "Incline")
        XCTAssertEqual(incline.dots.map(\.spoken), ["Set 1 of 3, done", "Set 2 of 3, now", "Set 3 of 3, not yet"])
        XCTAssertEqual(incline.exerciseMark, .now)
        XCTAssertEqual(MarkState.of(exercise: 0, session: engine.active), .done, "every Bench set logged")
        XCTAssertEqual(MarkState.of(exercise: 2, session: engine.active), .todo)

        engine.apply(.skipSet(step: 5), now: now.addingTimeInterval(900))
        let skipped = try screen(engine, at: 910)
        XCTAssertEqual(skipped.dots.map(\.state), [.done, .todo, .now])
        XCTAssertEqual(skipped.dots.map(\.skipped), [false, true, false], "slashed")
        XCTAssertEqual(skipped.dots[1].spoken, "Set 2 of 3, skipped")

        engine.apply(.skipExercise(exerciseIndex: 1), now: now.addingTimeInterval(920))
        XCTAssertEqual(MarkState.of(exercise: 1, session: engine.active), .todo, "skipped sets are not done")

        let drops = CoreTestSupport.engine(CoreTestSupport.plan(sets: 2, drops: [DropTarget(work: .reps(.amrap(min: nil)), weight: 40)]))
        let dropDots = try XCTUnwrap(WorkoutScreen.model(active: drops.active, history: [], now: now)).dots
        XCTAssertEqual(dropDots.count, 4, "two sets, each with a lighter set")
        XCTAssertEqual(dropDots.map(\.state), [.now, .todo, .todo, .todo])

        var superset = CoreTestSupport.engine(CoreTestSupport.plan(sets: 2, secondExercise: true, group: "A"))
        superset.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now.addingTimeInterval(60))
        let round = try XCTUnwrap(WorkoutScreen.model(active: superset.active, history: [], now: now.addingTimeInterval(70)))
        XCTAssertEqual(round.dots.map(\.step), [0, 1, 2, 3], "both exercises' rounds, in order")
        XCTAssertEqual(round.dots.map(\.state), [.done, .now, .todo, .todo])
        XCTAssertEqual(round.exerciseName, "Row", "the name follows the round")
    }

    // TP13 (D81): a filled dot changes its set in place — the card shows what was logged, the
    // inputs take it, the primary is Save — and Save's .editSet returns to the set that is on.
    // Undo is the strip's during the rest the set started, and not after.
    func testChangingALoggedSetInPlace() throws {
        var engine = try example()
        let at = now.addingTimeInterval(800)
        let resting = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: at))
        XCTAssertNil(resting.editing)
        XCTAssertEqual(resting.primary.kind, .log)
        XCTAssertEqual(resting.strip.undo, "Set logged · Undo", "the rest the set started")

        let editing = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: at, editing: 4))
        XCTAssertEqual(editing.editing, 4)
        XCTAssertEqual(editing.primary, PrimaryAction(title: "Save", kind: .save))
        XCTAssertEqual(editing.inputs.reps, "10")
        XCTAssertEqual(editing.inputs.weight, "26")
        XCTAssertTrue(editing.inputs.showsWeight)
        XCTAssertFalse(editing.inputs.seconds)
        XCTAssertNil(editing.inputs.suggestion)
        XCTAssertEqual(editing.card.colour, .done)
        XCTAssertEqual(editing.card.cells.cells.map(\.fill), Array(repeating: .solid, count: 10))
        XCTAssertEqual(editing.card.showing(field: 12).cells.cells.filter(\.over).count, 2, "the cells follow the field")
        XCTAssertEqual(editing.step, 5, "the set that is on stays on")
        XCTAssertEqual(editing.dots, resting.dots)
        XCTAssertEqual(editing.zones, WorkoutZone.allCases)

        for ignored in [6, 0, 99] {
            let model = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: at, editing: ignored))
            XCTAssertNil(model.editing, "pending, another block's, or none: \(ignored)")
            XCTAssertEqual(model.primary.kind, .log)
        }

        engine.apply(.editSet(step: 4, result: .reps(count: 9, weight: 26)), now: at)
        XCTAssertEqual(engine.session.steps[4].result, .reps(count: 9, weight: 26))
        let saved = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: at))
        XCTAssertEqual(saved.step, 5)
        XCTAssertEqual(saved.card.colour, .now)
        XCTAssertEqual(saved.primary.kind, .log)
        guard case .resting = engine.phase else { return XCTFail("an edit moves nothing") }

        // After the rest, the dot is the way: the strip says no more.
        engine.apply(.skipRest, now: at.addingTimeInterval(10))
        XCTAssertTrue(engine.active.canUndo)
        XCTAssertNil(try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: at)).strip.undo)

        // A logged hold is changed in seconds, with no timer in the field's place; undoing the set
        // being changed ends the change.
        var hold = CoreTestSupport.engine(CoreTestSupport.plan(sets: 2, work: .openDuration(minSeconds: 30), bodyweight: true))
        hold.apply(.logSet(step: 0, result: .duration(seconds: 40, weight: nil)), now: now.addingTimeInterval(60))
        let changing = try XCTUnwrap(WorkoutScreen.model(active: hold.active, history: [], now: now.addingTimeInterval(70), editing: 0))
        XCTAssertEqual(changing.editing, 0)
        XCTAssertTrue(changing.inputs.seconds)
        XCTAssertEqual(changing.inputs.reps, "40")
        XCTAssertFalse(changing.inputs.showsWeight)
        XCTAssertNil(changing.timer)
        XCTAssertEqual(changing.card.unit, "sec")
        XCTAssertEqual(changing.card.cells.cells.count, 8)
        XCTAssertNotNil(try XCTUnwrap(WorkoutScreen.model(active: hold.active, history: [], now: now.addingTimeInterval(70))).timer)
        hold.apply(.undoLog(step: 0), now: now.addingTimeInterval(80))
        XCTAssertNil(try XCTUnwrap(WorkoutScreen.model(active: hold.active, history: [], now: now.addingTimeInterval(90), editing: 0)).editing)
    }

    // TP14 (D81): the ? only with something behind it, "was …" first.
    func testTheQuestionMarkOnlyWithSomethingBehindIt() throws {
        let engine = try example()
        XCTAssertNil(try screen(engine).notes, "no notes, no change: no ?")

        var exercise = engine.session.exercises[1]
        exercise.notes = "  Bench at 30°.  "
        XCTAssertEqual(WorkoutScreen.notes(exercise), "Bench at 30°.")
        exercise.notes = "   "
        XCTAssertNil(WorkoutScreen.notes(exercise), "whitespace is nothing")
        exercise.substitutedFor = "Barbell Row"
        XCTAssertEqual(WorkoutScreen.notes(exercise), "was Barbell Row")
        exercise.notes = "Elbows in."
        XCTAssertEqual(WorkoutScreen.notes(exercise), "was Barbell Row\nElbows in.")

        var plan = pushPullLegs()
        plan.days[0].exercises[0].notes = "Pause on the chest."
        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now))
        let noted = SessionEngine(session: session, settings: CoreTestSupport.classic, now: now)
        XCTAssertEqual(try screen(noted, at: 5).notes, "Pause on the chest.")
    }

    // MARK: - P3: the walk (D82)

    /// Two exercises of one set each, so logging step 0 ends a block; the plan's walk as given.
    private func twoLifts(walk: Int?) -> Plan {
        var plan = CoreTestSupport.plan(sets: 1, secondExercise: true)
        plan.restBetweenExercises = walk
        return plan
    }

    // TP17 (D82): between blocks the plan's walk comes before the setting's; the setting when
    // the plan has none; zero from either means straight through.
    func testTheWalkIsThePlansThenTheSettings() throws {
        let setting = Settings(warmUpSeconds: 0, transitionRestSeconds: 120)
        func advance(_ walk: Int?, _ settings: Settings) throws -> Advance {
            let session = try XCTUnwrap(Session.start(plan: twoLifts(walk: walk), dayIndex: 0, now: now))
            return RestResolution.after(0, next: 1, steps: session.steps, exercises: session.exercises,
                                        settings: settings, restBetweenExercises: walk)
        }
        XCTAssertEqual(try advance(90, setting), .blockDone(rest: 90), "the plan's, before the setting's")
        XCTAssertEqual(try advance(nil, setting), .blockDone(rest: 120), "the setting's, when the plan has none")
        XCTAssertEqual(try advance(0, setting), .blockDone(rest: 0), "the plan's zero is straight through")
        XCTAssertEqual(try advance(nil, CoreTestSupport.classic), .blockDone(rest: 0), "and so is the setting's")
        // A set's own rest never becomes the walk, and the rest between sets never becomes the plan's.
        let three = try XCTUnwrap(Session.start(plan: CoreTestSupport.plan(sets: 3, rest: 45), dayIndex: 0, now: now))
        XCTAssertEqual(RestResolution.after(0, next: 1, steps: three.steps, exercises: three.exercises,
                                            settings: setting, restBetweenExercises: 90), .rest(45))

        // Through the library, which reads the plan the session belongs to.
        var library = PlanLibrary()
        library.settings = setting
        let id = try XCTUnwrap(library.save(twoLifts(walk: 90), makeActive: true))
        try library.startDay(planId: id, dayIndex: 0, now: now)
        library.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        guard case let .resting(rest)? = library.engine?.phase else { return XCTFail("expected the walk") }
        XCTAssertEqual(rest.kind, .betweenExercises)
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(90))
        XCTAssertEqual(library.engine?.walk.minimum, 90)
        XCTAssertEqual(library.engine?.walk.fromPlan, true)
        // The day's estimate walks the plan's minimum too.
        XCTAssertEqual(BuiltInPlans.estimatedMinutes(twoLifts(walk: 600), dayIndex: 0, settings: setting),
                       BuiltInPlans.estimatedMinutes(twoLifts(walk: nil), dayIndex: 0,
                                                     settings: Settings(warmUpSeconds: 0, transitionRestSeconds: 600)))
    }

    // TP18 (D82): the fixture imports with 90 and "90" alike; -1 is refused at the field. The
    // manifest's `restBetweenExercises` check, which `reference_import.py` also reads, covers
    // the same three files in `ImportTests`.
    func testThePlanFormatReadsTheWalk() throws {
        func run(_ path: String) throws -> ImportResult {
            PlanImport.run(try FixtureLoader.text(path), settings: Settings(units: .kg, defaultRestSeconds: 90), now: now)
        }
        let number = try run("valid/rest-between-exercises.json")
        XCTAssertEqual(number.plan?.restBetweenExercises, 90)
        XCTAssertFalse(number.issues.contains { $0.code == "W_UNKNOWN_FIELD" }, "a known field, not an ignored one")
        XCTAssertEqual(number.plan?.days[0].exercises[0].sets.map(\.restSeconds), [60, 60],
                       "the walk is not a set's rest, and does not resolve into one")
        XCTAssertEqual(try run("valid/rest-between-exercises-string.json").plan?.restBetweenExercises, 90)
        XCTAssertNil(try run("valid/rest-precedence.json").plan?.restBetweenExercises, "absent is nil, not 120")
        let negative = try run("invalid/rest-between-exercises-negative.json")
        XCTAssertNil(negative.plan)
        XCTAssertTrue(negative.issues.contains { $0.code == "E_REST_INVALID" && $0.path == "restBetweenExercises" })
        // The prompts ask for it in the plan and the outline, and never for one day.
        let settings = Settings(units: .kg, defaultRestSeconds: 90)
        XCTAssertTrue(Prompts.render(settings: settings).contains("\"restBetweenExercises\": 120"))
        XCTAssertTrue(Prompts.render(settings: settings).contains("- restBetweenExercises: whole seconds to walk between exercises; if unspecified, 120."))
        XCTAssertTrue(Prompts.outline(settings: settings).contains("- restBetweenExercises:"))
        XCTAssertFalse(Prompts.dayTemplate.contains("restBetweenExercises"), "a day cannot carry a plan's field")
        XCTAssertEqual(Prompts.exampleJSON.contains("restBetweenExercises"), true)
    }

    // TP19 (D82): on disk — the frozen v1 plan decodes with nil, a plan with the field
    // round-trips, and an edit keeps it.
    func testTheWalkOnDisk() throws {
        let frozen = try StoreCoder.decode(PlansPayload.self, from: try FixtureLoader.data("store/v1/plans.json"))
        XCTAssertFalse(frozen.plans.isEmpty)
        XCTAssertTrue(frozen.plans.allSatisfy { $0.restBetweenExercises == nil })

        let plan = twoLifts(walk: 90)
        let decoded = try StoreCoder.decode(PlansPayload.self,
                                            from: try StoreCoder.encode(PlansPayload(activePlanId: plan.id, plans: [plan])))
        XCTAssertEqual(decoded.plans.first?.restBetweenExercises, 90)
        XCTAssertEqual(decoded.plans.first, plan)
        let without = try StoreCoder.decode(PlansPayload.self,
                                            from: try StoreCoder.encode(PlansPayload(activePlanId: nil, plans: [twoLifts(walk: nil)])))
        XCTAssertNil(without.plans.first?.restBetweenExercises)

        XCTAssertTrue(PlanJSON.render(plan).contains("\"restBetweenExercises\": 90"))
        XCTAssertFalse(PlanJSON.render(twoLifts(walk: nil)).contains("restBetweenExercises"))
        let edited = PlanEdit.apply(.renameExercise(day: 0, exercise: 0, name: "Bench"), to: plan,
                                    settings: Settings(), now: now)
        XCTAssertEqual(edited.plan?.restBetweenExercises, 90, "an edit to the plan keeps its walk")
        let spliced = PlanEdit.apply(.replaceDayJSON(day: 0, text: PlanJSON.render(day: plan.days[0])), to: plan,
                                     settings: Settings(), now: now)
        XCTAssertEqual(spliced.plan?.restBetweenExercises, 90, "and so does a day replaced as JSON")
    }

    // TP20 (D82): the strip between exercises counts up beside a ring that fills over the
    // minimum — 0, ½, then 1 with a check at the minimum and after, the count-up going on —
    // with no −30 / +30 / Skip and Log set throughout; Start timer ends it as Log set does.
    func testTheWalkCountsUpBesideARing() throws {
        var library = PlanLibrary()
        library.settings = Settings(warmUpSeconds: 0, transitionRestSeconds: 120)
        let id = try XCTUnwrap(library.save(twoLifts(walk: 90), makeActive: true))
        try library.startDay(planId: id, dayIndex: 0, now: now)
        library.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        let engine = try XCTUnwrap(library.engine)

        func screen(at seconds: Double, _ active: ActiveSession? = nil) throws -> WorkoutScreenModel {
            try XCTUnwrap(WorkoutScreen.model(active: active ?? engine.active, history: [],
                                              now: now.addingTimeInterval(seconds),
                                              settings: library.settings, walk: engine.walk))
        }
        for (seconds, fraction, figure) in [(0.0, 0.0, "0:00"), (45, 0.5, "0:45"), (90, 1, "1:30")] {
            let strip = try screen(at: seconds).strip
            XCTAssertEqual(strip.kind, .blockDone)
            XCTAssertEqual(strip.restKind, .betweenExercises)
            XCTAssertEqual(strip.direction, .up)
            XCTAssertEqual(strip.countdown, figure)
            XCTAssertEqual(try XCTUnwrap(strip.ring).fraction, fraction, accuracy: 0.0001)
            XCTAssertEqual(strip.ring?.full, fraction == 1)
            XCTAssertFalse(strip.showsRestControls, "a count-up has nothing to skip")
            XCTAssertEqual(strip.next, "Row")
            XCTAssertEqual(try screen(at: seconds).primary.kind, .log, "Log set, throughout")
        }
        // The colour runs red, amber, green.
        XCTAssertEqual(try screen(at: 0).strip.ring?.colour, WalkRing.red)
        XCTAssertEqual(try screen(at: 45).strip.ring?.colour, WalkRing.amber)
        XCTAssertEqual(try screen(at: 90).strip.ring?.colour, WalkRing.green)
        XCTAssertEqual(try XCTUnwrap(try screen(at: 45).strip.spoken).hasPrefix("Between exercises, 0:45. at least 1:30. next, Row"), true)

        // The ring fills and the rest ends where it always did; the count-up keeps going.
        var after = engine
        after.apply(.restElapsed, now: now.addingTimeInterval(90))
        XCTAssertEqual(after.phase, .working(step: 1))
        let later = try screen(at: 200, after.active).strip
        XCTAssertEqual(later.countdown, "3:20", "counted from the walk's start, past the minimum")
        XCTAssertEqual(later.ring?.full, true)
        XCTAssertEqual(later.ring?.minimum, 90)
        XCTAssertEqual(later.direction, .up)
        XCTAssertFalse(later.showsRestControls)

        // −30 / +30 / Skip leave this kind of rest; the warm-up keeps them.
        var walking = engine
        XCTAssertEqual(walking.apply(.adjustRest(seconds: 30), now: now.addingTimeInterval(5)), [])
        XCTAssertEqual(walking.apply(.skipRest, now: now.addingTimeInterval(5)), [])
        XCTAssertEqual(walking.active, engine.active)
        var warm = SessionEngine(session: try XCTUnwrap(Session.start(plan: twoLifts(walk: 90), dayIndex: 0, now: now)),
                                 settings: Settings(warmUpSeconds: 300), now: now)
        XCTAssertFalse(warm.apply(.adjustRest(seconds: 30), now: now).isEmpty)
        XCTAssertTrue(try XCTUnwrap(WorkoutScreen.model(active: warm.active, history: [], now: now)).strip.showsRestControls)

        // Log set ends the walk, and so does Start timer.
        var logged = engine
        logged.apply(.logSet(step: 1, result: .reps(count: 10, weight: 60)), now: now.addingTimeInterval(30))
        XCTAssertNil(logged.active.blockDone)
        var timedPlan = CoreTestSupport.plan(sets: 1)
        timedPlan.days[0].exercises.append(Exercise(name: "Plank", bodyweight: true,
            sets: [SetTarget(work: .duration(seconds: 45), restSeconds: 60)]))
        timedPlan.restBetweenExercises = 90
        var timed = SessionEngine(session: try XCTUnwrap(Session.start(plan: timedPlan, dayIndex: 0, now: now)),
                                  settings: CoreTestSupport.classic, now: now)
        timed.restBetweenExercises = 90
        timed.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        XCTAssertNotNil(timed.active.blockDone)
        timed.apply(.startTimer(step: 1), now: now.addingTimeInterval(20))
        XCTAssertTrue(timed.active.timerRunning)
        XCTAssertNil(timed.active.blockDone, "starting the set ends the walk")
        let timedStrip = try XCTUnwrap(WorkoutScreen.model(active: timed.active, history: [],
                                                          now: now.addingTimeInterval(25))).strip
        XCTAssertNil(timedStrip.ring)
        XCTAssertEqual(timedStrip.kind, .timed)

        // A zero minimum is full from the start.
        var straight = SessionEngine(session: try XCTUnwrap(Session.start(plan: twoLifts(walk: 0), dayIndex: 0, now: now)),
                                     settings: Settings(warmUpSeconds: 0, transitionRestSeconds: 120), now: now)
        straight.restBetweenExercises = 0
        straight.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        XCTAssertEqual(straight.phase, .working(step: 1))
        let full = try XCTUnwrap(WorkoutScreen.model(active: straight.active, history: [], now: now,
                                                    walk: straight.walk)).strip
        XCTAssertEqual(full.ring?.full, true)
        XCTAssertEqual(full.countdown, "0:00")

        // The Lock Screen counts the walk up too, before the ring fills and after.
        let island = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now.addingTimeInterval(10)))
        XCTAssertNil(island.endsAt)
        XCTAssertEqual(island.startedAt, now)
        XCTAssertFalse(island.timerCountsDown)
        XCTAssertEqual(island.title, "Between exercises")
        XCTAssertTrue(island.isBreak)
        let islandAfter = try XCTUnwrap(WorkoutActivityState.of(after.active, now: now.addingTimeInterval(200)))
        XCTAssertEqual(islandAfter.startedAt, now)
        XCTAssertFalse(islandAfter.timerCountsDown)
    }

    // TP21 (D82): the alert is scheduled for `endsAt`, as it was — which is now the moment the
    // ring fills.
    func testTheWalksAlertIsAtTheRingsEnd() throws {
        var engine = SessionEngine(session: try XCTUnwrap(Session.start(plan: twoLifts(walk: 90), dayIndex: 0, now: now)),
                                   settings: Settings(warmUpSeconds: 0, transitionRestSeconds: 120), now: now)
        engine.restBetweenExercises = 90
        let effects = engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        XCTAssertTrue(effects.contains { effect in
            if case let .scheduleNotification(id, at, _) = effect { return id == .rest && at == now.addingTimeInterval(90) }
            return false
        })
        let alert = engine.apply(.restElapsed, now: now.addingTimeInterval(90))
        XCTAssertTrue(alert.contains(.playAlert(.end)), "the sound plays when the ring fills")
    }

    // TP22 (D82): the ring's one sentence names the minimum in m:ss, and whose it is.
    func testTheRingExplainsItself() {
        XCTAssertEqual(RestText.ringExplanation(minimum: 120, fromPlan: true),
                       "At least 2:00 between exercises. Your plan's minimum — when the ring is full, you're ready.")
        XCTAssertEqual(RestText.ringExplanation(minimum: 90, fromPlan: false),
                       "At least 1:30 between exercises. Your minimum in Settings — when the ring is full, you're ready.")
        XCTAssertEqual(RestText.ringExplanation(minimum: 0, fromPlan: true),
                       "No minimum between exercises. The ring starts full — go when you're ready.")
        XCTAssertEqual(WalkRing(fraction: 1, minimum: 150, fromPlan: true).explanation,
                       RestText.ringExplanation(minimum: 150, fromPlan: true))
    }

    // TP15 (D81, pin): zone 2 prints no sentence — the name, and the card's range, unit and
    // weight — draws the dots and the card, keeps the ? and the name's history; the edit sheet
    // left this screen for the Overview and Session detail; Undo is the strip's at every size.
    func testZoneTwoHasNoSentence() throws {
        guard let view = FixtureLoader.doc("JimmsBro/Features/Workout/WorkoutView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        func code(_ text: String) -> String {
            text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
        let zone = code(try XCTUnwrap(Self.block(view, from: "// MARK: - Zone 2", to: "// MARK: - Zone 3")))
        XCTAssertEqual(zone.components(separatedBy: "Text(").count - 1, 1, "one Text in zone 2")
        XCTAssertTrue(zone.contains("Text(page.exerciseName)"), "since D83, a page's")
        for gone in ["targetLine", "screen.rows", "SetRowView", "InsetGroup", "Text(\""] {
            XCTAssertFalse(zone.contains(gone), gone)
        }
        for kept in ["SetCardView(card: page.card(field: InputRules.repsValue(repsText)), day: dayColour)",
                     "NotesButton(notes: notes)", "DotView(dot: dot", "HistoryRoute.exercise(",
                     ".accessibilityLabel(page.spoken)", "model.apply(.jumpTo(step: dot.step))", "editing = dot.step"] {
            XCTAssertTrue(zone.contains(kept), kept)
        }
        let card = code(try XCTUnwrap(Self.block(view, from: "private struct SetCardView", to: "\n}\n")))
        XCTAssertEqual(card.components(separatedBy: "Text(").count - 1, 3)
        for text in ["Text(card.range)", "Text(unit)", "Text(weight)"] { XCTAssertTrue(card.contains(text), text) }
        XCTAssertFalse(view.contains("EditResultSheet"), "the sheet stays for the Overview and Session detail")
        XCTAssertTrue(view.contains("await model.apply(.editSet(step: step, result: result))"))
        XCTAssertFalse(view.contains("strip.undo != nil, typeSize.isAccessibilitySize"))
        XCTAssertTrue(view.contains("if strip.undo != nil {"))
    }

    // MARK: - P4: pages (D83)

    private func page(_ engine: SessionEngine, showing: Int?, editing: Int? = nil,
                      at seconds: Double = 800) throws -> WorkoutScreenModel {
        try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now.addingTimeInterval(seconds),
                                          editing: editing, showing: showing))
    }

    // TP24 (D83): a page behind — Bench on the example. The caret under it, every dot done and a
    // check for the ?, the card its fourth set as logged at 70 % and deaf to the field, no inputs,
    // and Back to the exercise that is on; the ··· still acts on it. A dot there changes its set.
    func testAPageBehind() throws {
        let engine = try example()
        let current = try page(engine, showing: nil)
        let bench = try page(engine, showing: 0)
        XCTAssertEqual(bench.bar.segments.map(\.caret), [true, false, false, false, false])
        XCTAssertEqual(bench.showing, 0)
        XCTAssertEqual(bench.currentBlock, 1)
        XCTAssertEqual(bench.page.place, .behind)
        XCTAssertEqual(bench.exerciseName, "Barbell Bench Press")
        XCTAssertEqual(bench.exerciseMark, .done)
        XCTAssertEqual(bench.dots.map(\.state), [.done, .done, .done, .done])
        XCTAssertTrue(bench.page.checked, "a check where the ? was")
        XCTAssertNil(bench.notes)
        XCTAssertEqual(bench.card, SetCard.of(session: engine.session, step: 3, history: [], colour: .done, field: 8),
                       "the fourth set, as logged")
        XCTAssertEqual(bench.card.cells.cells.map(\.fill), Array(repeating: .solid, count: 8))
        XCTAssertEqual(bench.page.cardOpacity, 0.7)
        XCTAssertFalse(bench.page.live)
        XCTAssertEqual(bench.page.card(field: 3), bench.card, "the set that is on's number is not this card's")
        XCTAssertNil(bench.page.firstPending)
        XCTAssertFalse(bench.showsInputs, "zone 3 is empty")
        XCTAssertNil(bench.timer)
        XCTAssertEqual(bench.primary, PrimaryAction(title: "Back to Incline Dumbbell Press", kind: .back))
        XCTAssertEqual(WorkoutText.back(to: "Plank"), "Back to Plank")
        XCTAssertEqual(bench.step, 5, "the ··· acts on the set that is on")
        XCTAssertEqual(bench.exerciseIndex, 1)
        XCTAssertEqual(bench.currentName, "Incline Dumbbell Press")
        XCTAssertEqual(bench.inputs, current.inputs, "what was typed survives a look away")
        XCTAssertEqual(bench.strip, current.strip)
        XCTAssertEqual(bench.zones, WorkoutZone.allCases)

        // The current page, for contrast.
        XCTAssertEqual(current.page.place, .current)
        XCTAssertEqual(current.showing, 1)
        XCTAssertTrue(current.showsInputs)
        XCTAssertTrue(current.page.live)
        XCTAssertEqual(current.page.cardOpacity, 1)
        XCTAssertFalse(current.page.checked)
        XCTAssertEqual(current.primary.kind, .log)
        XCTAssertEqual(current.pages.map(\.place), [.behind, .current, .ahead, .ahead, .ahead])

        // A filled dot behind changes its set there: Save, the inputs, the card opaque and live.
        let changing = try page(engine, showing: 0, editing: 0)
        XCTAssertEqual(changing.editing, 0)
        XCTAssertEqual(changing.primary, PrimaryAction(title: "Save", kind: .save))
        XCTAssertTrue(changing.showsInputs)
        XCTAssertEqual(changing.inputs.reps, "8")
        XCTAssertEqual(changing.inputs.weight, "80")
        XCTAssertTrue(changing.page.live)
        XCTAssertEqual(changing.page.cardOpacity, 1)
        XCTAssertEqual(changing.card.colour, .done)
        XCTAssertEqual(changing.page.card(field: 7).cells.cells.filter { $0.fill == .solid }.count, 7)
        XCTAssertFalse(try XCTUnwrap(changing.pages[safe: 1]).live, "the current page's card waits")
        XCTAssertEqual(changing.exerciseName, "Barbell Bench Press")
        XCTAssertNil(try page(engine, showing: 0, editing: 4).editing, "a set on another page is not changed here")
        XCTAssertNil(try page(engine, showing: 1, editing: 0).editing)

        // A block whose last set was skipped is behind, without a check: the card its last logged set.
        var skipped = SessionEngine(session: try XCTUnwrap(Session.start(plan: pushPullLegs(), dayIndex: 0, now: now)),
                                    settings: CoreTestSupport.classic, now: now)
        for step in 0..<3 {
            skipped.apply(.logSet(step: step, result: .reps(count: 7, weight: 80)), now: now.addingTimeInterval(Double(step + 1) * 150))
        }
        skipped.apply(.skipSet(step: 3), now: now.addingTimeInterval(600))
        let partly = try page(skipped, showing: 0, at: 610)
        XCTAssertEqual(partly.page.place, .behind)
        XCTAssertFalse(partly.page.checked)
        XCTAssertEqual(partly.exerciseMark, .todo)
        XCTAssertEqual(partly.dots.map(\.skipped), [false, false, false, true])
        XCTAssertEqual(partly.card, SetCard.of(session: skipped.session, step: 2, history: [], colour: .done, field: 7))
        XCTAssertEqual(partly.primary.kind, .back)
    }

    // TP25 (D83): a page ahead — Lateral Raise. The caret under it, grey dots and name, a grey
    // card of its first set's target with no caret, no inputs, and Do this now, which jumps to
    // Lateral Raise's first set out of the rest and leaves Incline's two pending to wait its turn.
    func testAPageAheadAndDoThisNow() throws {
        var engine = try example()
        let lateral = try page(engine, showing: 2)
        XCTAssertEqual(lateral.bar.segments.map(\.caret), [false, false, true, false, false])
        XCTAssertEqual(lateral.page.place, .ahead)
        XCTAssertEqual(lateral.exerciseName, "Lateral Raise")
        XCTAssertEqual(lateral.exerciseMark, .todo)
        XCTAssertEqual(lateral.dots.map(\.state), [.todo, .todo, .todo])
        XCTAssertFalse(lateral.page.checked)
        XCTAssertEqual(lateral.card.colour, .todo)
        XCTAssertEqual(lateral.card.range, "12–15")
        XCTAssertEqual(lateral.card.weight, "10 kg")
        XCTAssertEqual(lateral.card.cells.cells.map(\.fill), Array(repeating: .solid, count: 12) + Array(repeating: .faint, count: 3))
        XCTAssertFalse(lateral.card.cells.cells.contains(where: \.caret))
        XCTAssertEqual(lateral.page.card(field: 13), lateral.card)
        XCTAssertEqual(lateral.page.cardOpacity, 1)
        XCTAssertFalse(lateral.showsInputs)
        XCTAssertNil(lateral.timer)
        XCTAssertEqual(lateral.page.firstPending, 7)
        XCTAssertEqual(lateral.primary, PrimaryAction(title: "Do this now", kind: .doNow, step: 7))
        XCTAssertEqual(WorkoutText.doNow, "Do this now")

        // Do this now is `jumpTo`: out of the rest, its notification cancelled.
        let effects = engine.apply(.jumpTo(step: try XCTUnwrap(lateral.primary.step)), now: now.addingTimeInterval(810))
        XCTAssertTrue(effects.contains(.cancelNotification(id: .rest)))
        XCTAssertEqual(engine.phase, .working(step: 7))
        XCTAssertEqual(engine.active.currentStep, 7)
        XCTAssertEqual([5, 6].map { engine.session.steps[$0].status }, [.pending, .pending], "Incline waits")
        let on = try page(engine, showing: nil, at: 820)
        XCTAssertEqual(on.currentBlock, 2)
        XCTAssertEqual(on.showing, 2)
        XCTAssertEqual(on.page.place, .current)
        XCTAssertEqual(on.primary.kind, .log)
        XCTAssertEqual(on.dots.map(\.state), [.now, .todo, .todo])
        XCTAssertEqual(try page(engine, showing: 2, at: 820), on, "the explicit page that is now on is the same screen")

        // Incline, behind the caret with two sets still to do, is a page ahead.
        let incline = try page(engine, showing: 1, at: 820)
        XCTAssertEqual(incline.page.place, .ahead)
        XCTAssertEqual(incline.dots.map(\.state), [.done, .todo, .todo])
        XCTAssertEqual(incline.exerciseMark, .todo)
        XCTAssertEqual(incline.primary, PrimaryAction(title: "Do this now", kind: .doNow, step: 5))
        XCTAssertEqual(incline.card, SetCard.of(session: engine.session, step: 5, history: [], colour: .todo, field: nil))

        // Lateral Raise done, the day goes on to Tricep Pushdown, and Incline still waits.
        for step in 7...9 {
            engine.apply(.logSet(step: step, result: .reps(count: 12, weight: 10)), now: now.addingTimeInterval(Double(step) * 120))
        }
        XCTAssertEqual(engine.active.currentStep, 10)
        let after = try page(engine, showing: 2, at: 1200)
        XCTAssertEqual(after.page.place, .behind)
        XCTAssertTrue(after.page.checked)
        XCTAssertEqual(after.primary, PrimaryAction(title: "Back to Tricep Pushdown", kind: .back))
        XCTAssertEqual(try page(engine, showing: 1, at: 1200).page.place, .ahead)
    }

    // TP26 (D83): the fill is the record — the bar's segments and marks are the same whatever page
    // is looked at; only the caret moves. The pages are the bar's segments, in its order, after
    // Do later too; a block the day does not have is the page that is on.
    func testTheBarsFillDoesNotMoveWithThePage() throws {
        var engine = try example()
        let screens = try [0, nil, 2, 99].map { try page(engine, showing: $0) }
        func fill(_ bar: WorkoutBar) -> [[MarkState]] { bar.segments.map(\.sets) }
        for screen in screens {
            XCTAssertEqual(fill(screen.bar), fill(screens[1].bar))
            XCTAssertEqual(screen.bar.segments.map(\.weight), screens[1].bar.segments.map(\.weight))
            XCTAssertEqual(screen.bar.segments.map(\.blockIndex), screen.pages.map(\.blockIndex))
            XCTAssertEqual(screen.bar.segments.filter(\.caret).map(\.blockIndex), [screen.showing])
            XCTAssertEqual(screen.completion, screens[1].completion)
            XCTAssertEqual(screen.stage, screens[1].stage)
            XCTAssertEqual(screen.pages, screens[1].pages, "every page is the same data wherever you are")
        }
        XCTAssertEqual(screens.map(\.showing), [0, 1, 2, 1], "99 is no block: the page that is on")
        XCTAssertEqual(screens[3], screens[1])
        XCTAssertEqual(screens[0].page(-1), nil)
        XCTAssertEqual(screens[0].page(1), 1)
        XCTAssertEqual(screens[2].page(1), 3)
        XCTAssertEqual(screens[2].page(-1), 1)
        XCTAssertNil(screens[2].page(3))

        engine.apply(.deferExercise(exerciseIndex: 1), now: now.addingTimeInterval(810))
        let deferred = try page(engine, showing: nil, at: 820)
        XCTAssertEqual(deferred.pages.map(\.blockIndex), deferred.bar.segments.map(\.blockIndex))
        XCTAssertEqual(deferred.exerciseName, "Lateral Raise")
        let incline = try XCTUnwrap(deferred.pages.first { $0.blockIndex == 1 })
        XCTAssertEqual(incline.place, .ahead)
        XCTAssertEqual(incline.firstPending.map { engine.session.steps[$0].blockIndex }, 1)
    }

    // TP27 (D83): a superset block is one page — its rounds the dots, its name the current step's
    // as the round alternates; ahead, the name is its first set to do; behind, its last logged.
    func testASupersetIsOnePage() throws {
        var plan = pushPullLegs()
        plan.days[0].exercises[2].group = "A"
        plan.days[0].exercises[3].group = "A"
        var engine = SessionEngine(session: try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now)),
                                   settings: CoreTestSupport.classic, now: now)
        for step in 0..<5 {
            engine.apply(.logSet(step: step, result: .reps(count: 8, weight: 80)), now: now.addingTimeInterval(Double(step + 1) * 150))
        }
        let before = try page(engine, showing: nil)
        XCTAssertEqual(before.pages.count, 4, "Bench, Incline, the superset, Plank")
        XCTAssertEqual(before.bar.segments.count, 4)
        let superset = try page(engine, showing: 2)
        XCTAssertEqual(superset.page.place, .ahead)
        XCTAssertEqual(superset.dots.count, 6, "both exercises' three rounds")
        XCTAssertEqual(superset.exerciseName, "Lateral Raise")
        XCTAssertEqual(superset.primary, PrimaryAction(title: "Do this now", kind: .doNow, step: 7))

        engine.apply(.jumpTo(step: 7), now: now.addingTimeInterval(810))
        XCTAssertEqual(try page(engine, showing: nil, at: 820).exerciseName, "Lateral Raise")
        engine.apply(.logSet(step: 7, result: .reps(count: 12, weight: 10)), now: now.addingTimeInterval(830))
        let partner = try page(engine, showing: nil, at: 840)
        XCTAssertEqual(partner.showing, 2, "one page for the round")
        XCTAssertEqual(partner.exerciseName, "Tricep Pushdown", "the name follows the step that is on")
        XCTAssertEqual(partner.dots.map(\.state), [.done, .now, .todo, .todo, .todo, .todo])

        for step in 8...12 {
            engine.apply(.logSet(step: step, result: .reps(count: 11, weight: 20)), now: now.addingTimeInterval(Double(step) * 100))
        }
        let behind = try page(engine, showing: 2, at: 1300)
        XCTAssertEqual(behind.page.place, .behind)
        XCTAssertTrue(behind.page.checked)
        XCTAssertEqual(behind.exerciseName, "Tricep Pushdown", "its last logged set's")
        XCTAssertEqual(behind.card, SetCard.of(session: engine.session, step: 12, history: [], colour: .done, field: 11))
    }

    // TP28 (D83, pin; proposed as ui): zone 2 is a pager of pages — a horizontal scroll that lands
    // a page per swipe, a 20 pt margin and an 8 pt gap so the next page peeks 12 pt, no page dots
    // or arrows, a page behind at its card's opacity — kept level with the view's `showing`, which
    // the model takes and nothing stores; zone 5's Back and Do this now; zone 3 only with inputs.
    func testZoneTwoIsAPager() throws {
        guard let view = FixtureLoader.doc("JimmsBro/Features/Workout/WorkoutView.swift"),
              let app = FixtureLoader.doc("JimmsBro/Store/AppModel.swift"),
              let activity = FixtureLoader.doc("JimmsBro/Core/WorkoutActivity.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        let zone = try XCTUnwrap(Self.block(view, from: "// MARK: - Zone 2", to: "// MARK: - Zone 3"))
        for kept in ["ScrollView(.horizontal)", ".scrollTargetLayout()", ".modifier(OnePagePerSwipe())",
                     ".containerRelativeFrame(.horizontal)", ".scrollPosition(id: $scrolled)",
                     ".contentMargins(.horizontal, Self.gutter, for: .scrollContent)",
                     "private static let gutter: CGFloat = 20", "private static let pageGap: CGFloat = 8",
                     ".opacity(page.cardOpacity)", "ForEach(screen.pages, id: \\.blockIndex)",
                     "showing = block == screen.currentBlock ? nil : block", "if page.checked {"] {
            XCTAssertTrue(zone.contains(kept), kept)
        }
        for gone in ["TabView", ".tabViewStyle(", "chevron.left", "chevron.right", "PageControl"] {
            XCTAssertFalse(view.contains(gone), gone)
        }
        XCTAssertTrue(view.contains(".viewAligned(limitBehavior: .alwaysByOne)"))
        XCTAssertTrue(view.contains("walk: model.engine?.walk, showing: showing)"))
        XCTAssertTrue(view.contains("@State private var showing: Int?"))
        let primary = try XCTUnwrap(Self.block(view, from: "private func primaryTapped()", to: "\n    }\n"))
        XCTAssertTrue(primary.contains("case .back:"))
        XCTAssertTrue(primary.contains("await model.apply(.jumpTo(step: step))"))
        XCTAssertTrue(view.contains("if !screen.showsInputs {"))
        XCTAssertTrue(view.contains("changeExercise(screen.exerciseIndex, screen.currentName)"))
        XCTAssertFalse(app.contains("showing:"), "nothing the app keeps knows which page is looked at")
        XCTAssertFalse(activity.contains("showing:"), "nor the Lock Screen")
    }

    // MARK: P5 — a bar that learns your pace (D84, SPEC §6.57)

    /// A finished Push `daysAgo` days back. Block b takes `minutes[b]` from its first set to the
    /// next block's first set — its sets in the first three quarters, the walk in the last — and
    /// the last block done ends at its last log. Nil is a block skipped as it came up, in no time.
    private func pastPush(_ minutes: [Double?], daysAgo: Double, renamed: [Int: String] = [:]) throws -> Session {
        var session = try XCTUnwrap(Session.start(plan: pushPullLegs(), dayIndex: 0,
                                                  now: now.addingTimeInterval(-86_400 * daysAgo)))
        for (exercise, name) in renamed { session.exercises[exercise].name = name }
        let lastDone = minutes.lastIndex { $0 != nil }
        var clock = session.startedAt
        for (b, block) in SessionBlocks.indices(session).enumerated() {
            guard let stretch = b < minutes.count ? minutes[b] : nil else {
                session.steps[block[0]].startedAt = clock
                for i in block { session.steps[i].status = .skipped; session.steps[i].loggedAt = clock }
                continue
            }
            let seconds = stretch * 60, sets = b == lastDone ? stretch * 60 : stretch * 45
            for (n, i) in block.enumerated() {
                session.steps[i].startedAt = clock.addingTimeInterval(sets * Double(n) / Double(block.count))
                session.steps[i].loggedAt = clock.addingTimeInterval(sets * Double(n + 1) / Double(block.count))
                session.steps[i].status = .logged
                session.steps[i].result = session.target(at: i)?.work.isTimed == true
                    ? .duration(seconds: 40, weight: nil) : .reps(count: 8, weight: 80)
            }
            clock.addTimeInterval(seconds)
        }
        session.endedAt = clock
        return session
    }

    private func assertMinutes(_ weights: [Double], _ minutes: [Double], _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(weights.count, minutes.count, message, file: file, line: line)
        for (weight, minute) in zip(weights, minutes) {
            XCTAssertEqual(weight, minute * 60, accuracy: 0.001, message, file: file, line: line)
        }
    }

    // TP30 (D84): a day with no history is by set count, as P1 drew it — and so is a history too
    // short to be a pace, and sessions that do not count: unfinished, later, or the day itself.
    func testNoHistoryIsBySetCount() throws {
        let engine = try example()
        let day = engine.active.session
        XCTAssertEqual(Pace.weights(day: day, history: []), [4, 3, 3, 3, 3])
        XCTAssertEqual(try screen(engine).bar.segments.map(\.weight), [4, 3, 3, 3, 3])

        let twice = try [pastPush([14, 10, 8, 8, 4], daysAgo: 2), pastPush([14, 10, 8, 8, 4], daysAgo: 4)]
        XCTAssertEqual(Pace.weights(day: day, history: twice), [4, 3, 3, 3, 3], "two times are not a pace")
        var unfinished = try pastPush([14, 10, 8, 8, 4], daysAgo: 6)
        unfinished.endedAt = nil
        let later = try pastPush([14, 10, 8, 8, 4], daysAgo: -1)
        XCTAssertEqual(Pace.weights(day: day, history: twice + [unfinished, later, day]), [4, 3, 3, 3, 3],
                       "an unfinished session, a later one and the day itself are not times")

        XCTAssertEqual(Pace.weights(sets: [4, 3, 3], medians: [nil, nil, nil]), [4, 3, 3])
        XCTAssertEqual(Pace.median([]), nil)
        XCTAssertEqual(Pace.median([3, 1, 2]), 2)
        XCTAssertEqual(Pace.median([4, 1, 3, 2]), 2.5)
    }

    // TP31 (D84): three past Pushes. Bench took 14, 12 and 15 minutes → 14; Plank 4; each time from
    // a block's first set to the next block's first set, so the walk after it is counted in.
    func testThreeTimesAreAPace() throws {
        let engine = try example()
        let history = try [pastPush([14, 10, 8, 8, 4], daysAgo: 2),
                           pastPush([12, 10, 8, 8, 4], daysAgo: 4),
                           pastPush([15, 10, 8, 8, 4], daysAgo: 6)]
        assertMinutes(Pace.weights(day: engine.active.session, history: history), [14, 10, 8, 8, 4])

        // Bench's sets ended at 10½ minutes; the walk to Incline's first set made it 14.
        let past = history[0]
        let bench = try XCTUnwrap(SessionBlocks.indices(past).first)
        let lastLog = try XCTUnwrap(bench.compactMap { past.steps[$0].loggedAt }.max())
        XCTAssertEqual(lastLog.timeIntervalSince(past.startedAt), 630, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(Pace.time(of: bench, in: past)), 840, accuracy: 0.001)

        // The screen's bar is the pace; its marks and caret are what they were.
        let paced = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: history,
                                                      now: now.addingTimeInterval(800))).bar
        assertMinutes(paced.segments.map(\.weight), [14, 10, 8, 8, 4])
        XCTAssertEqual(paced.segments.map(\.sets), try screen(engine).bar.segments.map(\.sets))
        XCTAssertEqual(paced.segments.map(\.caret), [false, true, false, false, false])
        XCTAssertEqual(WorkoutBar.of(session: engine.active, weights: [1, 2]).segments.map(\.weight),
                       [4, 3, 3, 3, 3], "weights for another day's blocks are not this day's")

        // A session written by v1.2 reads as it is: a circuit from its first set to its last log,
        // and the skips that ended the workout half an hour later are not part of it.
        let frozen = try StoreCoder.decode(Session.self, from: try FixtureLoader.data("store/v1/session.json"))
        let blocks = SessionBlocks.indices(frozen)
        XCTAssertEqual(try XCTUnwrap(Pace.time(of: blocks[0], in: frozen)), 214, accuracy: 0.001)
        XCTAssertNil(Pace.time(of: blocks[1], in: frozen), "a block never logged has no time")
    }

    // TP32 (D84): an exercise done twice takes the day's time per set × its sets — the paced
    // blocks' minutes over their sets.
    func testTwiceUsesTheDaysTimePerSet() throws {
        let engine = try example()
        let history = try [pastPush([14, 10, 8, 8, 5], daysAgo: 2),
                           pastPush([12, 10, nil, 8, 5], daysAgo: 4),
                           pastPush([15, 10, 8, 8, 5], daysAgo: 6)]
        // Lateral Raise was skipped once, so it has two times; Incline's walk then ran to the
        // skip, and Tricep Pushdown's times are its own.
        let perSet = (14.0 + 10 + 8 + 5) / 13
        assertMinutes(Pace.weights(day: engine.active.session, history: history),
                      [14, 10, perSet * 3, 8, 5])
    }

    // TP33 (D84): the clamp. A 40-minute block on a day whose typical stretch is 7 is held at 14,
    // a 1-minute one at 3½ — the median stretch, which the long block does not move.
    func testTheClamp() throws {
        XCTAssertEqual(Pace.weights(sets: [4, 3, 3, 3, 3], medians: [40, 1, 7, 7, 7]), [14, 3.5, 7, 7, 7])
        let engine = try example()
        let history = try [2.0, 4, 6].map { try pastPush([40, 1, 7, 7, 7], daysAgo: $0) }
        assertMinutes(Pace.weights(day: engine.active.session, history: history), [14, 3.5, 7, 7, 7])
        // A block with no pace is clamped too: 13 sets over 55 minutes, three of them 12.7, held at 12.
        XCTAssertEqual(Pace.weights(sets: [4, 3, 3, 3, 3], medians: [40, 3, nil, 6, 6]), [12, 3, 12, 6, 6])
    }

    // TP34 (D84): a changed exercise (D42) is known by the name it now has — substituted after a
    // logged set, or in place before one — and a block never logged goes by its sets.
    func testAChangedExerciseAndASkippedBlock() throws {
        var engine = try example()
        let renamed = [1: "Incline Smith Press", 2: "Cable Lateral Raise"]
        let history = try [2.0, 4, 6].map { try pastPush([14, 10, 8, 8, nil], daysAgo: $0) }
            + [3.0, 5, 7].map { try pastPush([14, 11, 9, 8, nil], daysAgo: $0, renamed: renamed) }
        // Plank was never logged: the day's time per set × 3.
        assertMinutes(Pace.weights(day: engine.active.session, history: history),
                      [14, 10, 8, 8, (14.0 + 10 + 8 + 8) / 13 * 3])

        engine.apply(.substituteExercise(exerciseIndex: 1, name: "Incline Smith Press", weight: nil),
                     now: now.addingTimeInterval(820))
        engine.apply(.substituteExercise(exerciseIndex: 2, name: "Cable Lateral Raise", weight: nil),
                     now: now.addingTimeInterval(830))
        let session = engine.active.session
        XCTAssertEqual(session.exercises.count, 6, "Incline had a logged set, so it was replaced")
        XCTAssertEqual(session.exercises[2].name, "Cable Lateral Raise", "Lateral Raise had none, so renamed")
        XCTAssertEqual(SessionBlocks.indices(session).count, 5)
        assertMinutes(Pace.weights(day: session, history: history),
                      [14, 11, 9, 8, (14.0 + 11 + 9 + 8) / 13 * 3])
    }

    // MARK: P6 — squares that join (D86, SPEC §6.59)

    // TP40: seven to a row — a ten-day cycle is 7 + 3, a week one row, a fortnight two full rows,
    // a weekday plan one row — the symbol's fourteen two rows at most, the corners a row rounds,
    // and today's square on the plan's page.
    func testSquaresWrapAtSeven() throws {
        let calendar = CoreTestSupport.utc()
        func rotation(_ days: Int) -> Plan {
            var plan = pushPullLegs()
            plan.cycle = (0..<days).map { $0 % 4 == 3 ? .rest : .day($0 % 4) }
            return plan
        }
        func rows(_ plan: Plan) -> [Int] {
            CycleGlyph.rows(RepeatBlock.squares(plan, today: now, calendar: calendar)).map(\.count)
        }
        XCTAssertEqual(rows(rotation(10)), [7, 3])
        XCTAssertEqual(rows(rotation(7)), [7])
        XCTAssertEqual(rows(rotation(14)), [7, 7])
        var weekday = pushPullLegs()
        weekday.schedule = .weekday
        weekday.cycle = []
        for (index, day) in [Weekday.monday, .wednesday, .friday].enumerated() { weekday.days[index].weekday = day }
        XCTAssertEqual(rows(weekday), [7], "a weekday plan is one row")
        XCTAssertEqual(CycleGlyph.rows([Int]()), [])
        XCTAssertEqual(CycleGlyph(DayColour.cycle(of: rotation(10))).rows.map(\.count), [7, 3])
        XCTAssertEqual(CycleGlyph(Array(repeating: DayColour?.some(.green), count: 31)).rows.map(\.count), [7, 7],
                       "the symbol cuts at fourteen: two rows, then its trailing mark")

        // The row's two ends are rounded and the inner corners square.
        let ends = (0..<10).map { CycleGlyph.ends($0, count: 10) }
        XCTAssertEqual(ends.map(\.first), [true, false, false, false, false, false, false, true, false, false])
        XCTAssertEqual(ends.map(\.last), [false, false, false, false, false, false, true, false, false, true])
        XCTAssertTrue(CycleGlyph.ends(0, count: 1).first && CycleGlyph.ends(0, count: 1).last)

        // Today's square: a rotation's by its anchor, a weekday plan's by the weekday.
        var anchored = rotation(10)
        anchored.cyclePosition = 4
        anchored.cycleAnchor = calendar.startOfDay(for: now)
        let squares = RepeatBlock.squares(anchored, today: now, calendar: calendar)
        XCTAssertEqual(squares.indices.filter { squares[$0].isToday }, [4])
        let week = RepeatBlock.squares(weekday, today: now, calendar: calendar)
        let todays = Weekday.allCases.firstIndex { $0.calendarValue == calendar.component(.weekday, from: now) }
        XCTAssertEqual(week.indices.filter { week[$0].isToday }, todays.map { [$0] } ?? [])
    }

    // TP41: one joined strip draws a cycle everywhere — the symbol, the plan's page and the
    // picker — and the picker is strips, not a grouped list with section headers.
    func testOneJoinedStripDrawsTheCycleEverywhere() throws {
        guard let square = FixtureLoader.doc("JimmsBro/DaySquare.swift"),
              let picker = FixtureLoader.doc("JimmsBro/Features/Home/ChangeDayView.swift"),
              let page = FixtureLoader.doc("JimmsBro/Features/PlanDetail/PlanDetailView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        XCTAssertFalse(picker.contains("List {"), "the picker is not a grouped list")
        XCTAssertFalse(picker.contains("Section("), "the strips are the sections")
        XCTAssertTrue(picker.contains("CycleStrip(count: strip.tiles.count, side: Self.tile, spacing: 2"),
                      "the picker's strips are the joined drawing at tile size")
        XCTAssertTrue(page.contains("CycleStrip(count: squares.count, side: 40, spacing: 2"),
                      "the plan's page draws the joined strip")
        XCTAssertFalse(page.contains("WrapLayout"), "the page's squares wrap at seven, not at the width")
        XCTAssertTrue(square.contains("CycleStrip(count: glyph.squares.count"), "the symbol is the same drawing")
        XCTAssertTrue(square.contains("CycleGlyph.ends(index, count: count)"), "the corners are Core's")
    }

    /// The text from `start` up to and including the first `end` after it.
    static func block(_ text: String, from start: String, to end: String) -> String? {
        guard let head = text.range(of: start),
              let tail = text.range(of: end, range: head.upperBound..<text.endIndex) else { return nil }
        return String(text[head.lowerBound..<tail.upperBound])
    }
}
