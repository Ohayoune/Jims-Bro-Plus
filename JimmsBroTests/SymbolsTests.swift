import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// v1.10 (`docs/ITERATION_11_PLAN.md`) — the Workout screen in symbols. P1: three states, three
/// colours (D79, SPEC §6.52) and the header is the bar (D80, §6.53): TP1–TP6. TP7 is the phone's.
/// P2: the exercise in symbols (D81, §6.54): TP8–TP15. TP16 is the phone's.
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
        XCTAssertEqual(bar.segments.map(\.weight), [4, 3, 3, 3, 3], "widths by set count until P5")
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
        XCTAssertTrue(view.contains("PrimaryButton(title: screen.primary.title, enabled: primaryEnabled, ink: true)"))
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
        XCTAssertTrue(zone.contains("Text(screen.exerciseName)"))
        for gone in ["targetLine", "screen.rows", "SetRowView", "InsetGroup", "Text(\""] {
            XCTAssertFalse(zone.contains(gone), gone)
        }
        for kept in ["SetCardView(card: screen.card.showing(field: InputRules.repsValue(repsText)), day: dayColour)",
                     "NotesButton(notes: notes)", "DotView(dot: dot", "HistoryRoute.exercise(",
                     ".accessibilityLabel(screen.spoken)", "model.apply(.jumpTo(step: dot.step))", "editing = dot.step"] {
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

    /// The text from `start` up to and including the first `end` after it.
    static func block(_ text: String, from start: String, to end: String) -> String? {
        guard let head = text.range(of: start),
              let tail = text.range(of: end, range: head.upperBound..<text.endIndex) else { return nil }
        return String(text[head.lowerBound..<tail.upperBound])
    }
}
