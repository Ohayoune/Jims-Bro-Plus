import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// X2 (v1.3) — D42, W4–W11: changing an exercise mid-workout. The machine is taken and you
/// want to do *something* now; the exercise's remaining sets become sets of another exercise,
/// which keeps its own history identity.
final class ChangeExerciseTests: XCTestCase {
    private let now = CoreTestSupport.now

    // W4: nothing logged yet — the exercise is renamed in place, its sets keep their place.
    func testChangingBeforeAnySetIsARenameInPlace() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        let effects = engine.apply(.substituteExercise(exerciseIndex: 0, name: " Dumbbell Press ", weight: 22.5), now: now)

        XCTAssertEqual(engine.session.exercises.count, 3, "no second exercise: nothing was done under the old name")
        XCTAssertEqual(CoreTestSupport.stepNames(engine), ["Dumbbell Press", "Dumbbell Press", "Row", "Row", "Squat", "Squat"])
        XCTAssertEqual(engine.session.exercises[0].substitutedFor, "Bench Press")
        XCTAssertNil(engine.session.exercises[0].replaces)
        XCTAssertNil(engine.session.exercises[0].advice)
        XCTAssertEqual(engine.session.exercises[0].targets.map(\.weight), [22.5, 22.5], "the given weight replaces every target")
        XCTAssertEqual(engine.session.steps.map(\.blockIndex), [0, 0, 1, 1, 2, 2])
        XCTAssertEqual(engine.phase, .working(step: 0))
        XCTAssertEqual(engine.active.workWeight, 22.5, "the card re-reads its prefill")
        XCTAssertTrue(effects.contains(.persist))
    }

    // W5: one set already logged — the exercise splits, and the logged set keeps its name.
    func testChangingAfterASetSplitsTheExercise() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 50)), now: now)
        guard case let .resting(before) = engine.phase else { return XCTFail("should be resting") }

        engine.apply(.substituteExercise(exerciseIndex: 0, name: "Dumbbell Press", weight: nil), now: now)

        XCTAssertEqual(engine.session.exercises.count, 4)
        let substitute = engine.session.exercises[3]
        XCTAssertEqual(substitute.name, "Dumbbell Press")
        XCTAssertEqual(substitute.replaces, 0)
        XCTAssertEqual(substitute.substitutedFor, "Bench Press")
        XCTAssertEqual(substitute.targets.map(\.weight), [50, 50], "no weight given: the plan's stays")
        XCTAssertEqual(engine.session.exercises[0].name, "Bench Press")
        XCTAssertEqual(engine.session.steps[0].exerciseIndex, 0)
        XCTAssertEqual(engine.session.steps[0].status, .logged)
        XCTAssertEqual(engine.session.steps[1].exerciseIndex, 3)
        XCTAssertEqual(engine.session.steps[1].status, .pending)
        XCTAssertEqual(engine.session.steps.map(\.blockIndex), [0, 0, 1, 1, 2, 2], "order and blocks are untouched")

        // The rest that was running is still running, into the same step.
        guard case let .resting(after) = engine.phase else { return XCTFail("the rest was interrupted") }
        XCTAssertEqual(after, before)

        // The rows still show the logged set under its own name next to the pending one.
        let rows = StepCard.setRows(session: engine.session, step: 1, history: [])
        XCTAssertEqual(rows.map(\.label), ["Bench Press · Set 1 of 2", "Dumbbell Press · Set 2 of 2"])
        XCTAssertEqual(rows.map(\.status), [.logged, .pending])
    }

    // W6: the substitute reads its own history — its last time, its own prefill (D8).
    func testTheSubstituteKeepsItsOwnHistory() throws {
        var earlier = CoreTestSupport.plan(sets: 2, weight: 24)
        earlier.days[0].exercises[0].name = "Dumbbell Press"
        let history = CoreTestSupport.completed([12, 12], weights: [24, 24], plan: earlier)

        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises(), history: [history])
        engine.apply(.substituteExercise(exerciseIndex: 0, name: "dumbbell press", weight: nil), now: now)

        let values = Prefill.values(session: engine.session, step: 0, history: [history])
        XCTAssertEqual(values.weight, 24)
        XCTAssertEqual(values.reps, 12)
        XCTAssertEqual(engine.active.workWeight, 24)
        XCTAssertEqual(engine.session.exercises[0].targets.first?.weight, 50, "the plan's target is not history")
        XCTAssertEqual(Prefill.lastTime(session: engine.session, step: 0, history: [history])?.text, "12, 12 @ 24 kg")
        // D55 (v1.6): the fields already say 12 × 24, so there is no chip to draw.
        XCTAssertNil(values.suggestion)
    }

    // W7: the header keeps the exercise's number and says what it stood in for.
    func testTheStageKeepsTheExercisesNumber() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 50)), now: now)
        engine.apply(.substituteExercise(exerciseIndex: 0, name: "Dumbbell Press", weight: nil), now: now)
        engine.apply(.skipRest, now: now)

        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now,
                                                       settings: CoreTestSupport.classic))
        XCTAssertEqual(screen.stage, .working(exercise: 1, exercises: 3, set: 2, sets: 2))
        XCTAssertEqual(screen.progress, "Exercise 1 of 3 · Set 2 of 2")
        XCTAssertEqual(screen.exerciseName, "Dumbbell Press")
        // D81 (v1.10): said once, first behind the ?, and on the Overview's line — never on a dot.
        XCTAssertEqual(screen.notes?.components(separatedBy: "\n").first, "was Bench Press")
        XCTAssertTrue(StepCard.targetLine(session: engine.session, step: screen.step).hasSuffix("· was Bench Press"))
    }

    // W8: advice goes to the substitute; the original earns none for a job it did not finish.
    func testAdviceGoesToTheSubstituteNotTheOriginal() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3))
        engine.apply(.logSet(step: 0, result: .reps(count: 12, weight: 60)), now: now)
        engine.apply(.substituteExercise(exerciseIndex: 0, name: "Dumbbell Press", weight: nil), now: now)
        engine.apply(.skipRest, now: now)
        engine.apply(.logSet(step: 1, result: .reps(count: 12, weight: 60)), now: now)
        engine.apply(.skipRest, now: now)
        engine.apply(.logSet(step: 2, result: .reps(count: 12, weight: 60)), now: now)

        XCTAssertEqual(engine.phase, .completed)
        XCTAssertNil(engine.session.exercises[0].advice, "one set of Bench Press is not a finished exercise")
        XCTAssertEqual(engine.session.exercises[1].advice, .increase(to: 62.5))
        let line = StepCard.blockDoneLine(session: engine.session,
                                          blockDone: BlockDone(finishedBlock: 0, startedAt: now))
        XCTAssertTrue(line?.hasPrefix("Dumbbell Press done") == true, line ?? "nil")
    }

    // W9: a superset member is substituted alone; the round stays a round.
    func testASupersetMemberIsSubstitutedAlone() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises(group: "A"))
        engine.apply(.substituteExercise(exerciseIndex: 1, name: "Cable Row", weight: nil), now: now)

        XCTAssertEqual(engine.session.exercises.count, 3)
        XCTAssertEqual(engine.session.exercises.map(\.group), ["A", "A", "A"])
        XCTAssertEqual(CoreTestSupport.stepNames(engine), ["Bench Press", "Cable Row", "Squat", "Bench Press", "Cable Row", "Squat"])
        XCTAssertEqual(Set(engine.session.steps.map(\.blockIndex)), [0])
        let rows = StepCard.setRows(session: engine.session, step: 0, history: [])
        XCTAssertEqual(rows.map(\.label), ["Bench Press · Set 1 of 2", "Cable Row · Set 1 of 2", "Squat · Set 1 of 2"])
    }

    // W10: what is refused, and the one thing the same name is good for.
    func testWhatIsRefused() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        XCTAssertEqual(engine.apply(.substituteExercise(exerciseIndex: 0, name: "  ", weight: nil), now: now), [])
        XCTAssertEqual(engine.apply(.substituteExercise(exerciseIndex: 9, name: "X", weight: nil), now: now), [])
        XCTAssertEqual(engine.apply(.substituteExercise(exerciseIndex: 0, name: "X", weight: -1), now: now), [])
        XCTAssertEqual(engine.apply(.substituteExercise(exerciseIndex: 0, name: "bench press", weight: nil), now: now), [],
                       "the same name with no weight changes nothing")

        // The same name with a weight is a weight change for the remaining sets.
        engine.apply(.substituteExercise(exerciseIndex: 0, name: "Bench Press", weight: 55), now: now)
        XCTAssertEqual(engine.session.exercises[0].targets.map(\.weight), [55, 55])
        XCTAssertNil(engine.session.exercises[0].substitutedFor)
        XCTAssertEqual(engine.session.exercises.count, 3)

        // Nothing left to do under that name: nothing to change.
        engine.apply(.skipExercise(exerciseIndex: 0), now: now)
        XCTAssertEqual(engine.apply(.substituteExercise(exerciseIndex: 0, name: "Dumbbell Press", weight: nil), now: now), [])

        engine.apply(.finish, now: now)
        XCTAssertEqual(engine.apply(.substituteExercise(exerciseIndex: 1, name: "Cable Row", weight: nil), now: now), [])
    }

    // W11: the two new fields survive the disk, and a file written before them still decodes.
    func testTheNewFieldsSurviveTheDiskAndOldFilesStillDecode() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 50)), now: now)
        engine.apply(.substituteExercise(exerciseIndex: 0, name: "Dumbbell Press", weight: nil), now: now)
        let data = try StoreCoder.encode(engine.active)
        let back = try StoreCoder.decode(ActiveSession.self, from: data)
        XCTAssertEqual(back, engine.active)
        XCTAssertEqual(back.session.exercises[3].replaces, 0)

        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Bench Press","bodyweight":false,"targets":[]}"#
        let exercise = try JSONDecoder().decode(SessionExercise.self, from: Data(old.utf8))
        XCTAssertNil(exercise.substitutedFor)
        XCTAssertNil(exercise.replaces)
    }
}
