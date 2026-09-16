import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// v1.10 (`docs/ITERATION_11_PLAN.md`) — the Workout screen in symbols. P1: three states, three
/// colours (D79, SPEC §6.52) and the header is the bar (D80, §6.53): TP1–TP6. TP7 is the phone's.
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

        // The rows the screen draws take the same rule.
        let rows = try screen(engine, at: 960).rows
        XCTAssertEqual(rows.map(\.mark), [.done, .done, .now], "Incline's three rows")
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

    /// The text from `start` up to and including the first `end` after it.
    static func block(_ text: String, from start: String, to end: String) -> String? {
        guard let head = text.range(of: start),
              let tail = text.range(of: end, range: head.upperBound..<text.endIndex) else { return nil }
        return String(text[head.lowerBound..<tail.upperBound])
    }
}
