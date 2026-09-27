import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// R5.1 (v1.1) — "Do later" (D28): G61–G64. The machine is taken, so move the exercise to the
/// end of the day rather than skipping it.
final class DeferExerciseTests: XCTestCase {
    private let now = CoreTestSupport.now

    // G61: the block's pending steps move after the last pending step of the day.
    func testDeferMovesTheBlockToTheEnd() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        XCTAssertEqual(CoreTestSupport.stepNames(engine), ["Bench Press", "Bench Press", "Row", "Row", "Squat", "Squat"])

        engine.apply(.deferExercise(exerciseIndex: 0), now: now)
        XCTAssertEqual(CoreTestSupport.stepNames(engine), ["Row", "Row", "Squat", "Squat", "Bench Press", "Bench Press"])
        XCTAssertEqual(engine.phase, .working(step: 0), "the next exercise is already on screen")
        XCTAssertEqual(engine.session.exercises[engine.session.steps[0].exerciseIndex].name, "Row")
        // `blockIndex` still identifies the block; only the order changed.
        XCTAssertEqual(Set(engine.session.steps.map(\.blockIndex)), [0, 1, 2])
        XCTAssertEqual(engine.session.steps.suffix(2).map(\.blockIndex), [0, 0])
    }

    // G62: a partly-done exercise takes only what is left with it, and keeps what was logged.
    func testDeferKeepsLoggedSetsInPlace() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 50)), now: now)
        engine.apply(.skipRest, now: now.addingTimeInterval(10))
        XCTAssertEqual(engine.phase, .working(step: 1))

        engine.apply(.deferExercise(exerciseIndex: 0), now: now.addingTimeInterval(20))
        // The whole block moves, logged set included, so the exercise stays one thing.
        XCTAssertEqual(CoreTestSupport.stepNames(engine), ["Row", "Row", "Squat", "Squat", "Bench Press", "Bench Press"])
        XCTAssertEqual(engine.session.steps[4].status, .logged)
        XCTAssertEqual(engine.session.steps[4].result, .reps(count: 10, weight: 50))
        XCTAssertEqual(engine.session.steps[5].status, .pending)
        XCTAssertEqual(engine.phase, .working(step: 0))
        // The undo target followed its step through the move rather than pointing at a stranger.
        XCTAssertEqual(engine.active.lastCompletedStep, 4)
        XCTAssertTrue(engine.canUndo)
    }

    // G63: deferring out of a rest cancels it; deferring clears a block-done strip.
    func testDeferCancelsRestAndClearsTheStrip() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 50)), now: now)
        guard case .resting = engine.phase else { return XCTFail("expected a rest") }

        let effects = engine.apply(.deferExercise(exerciseIndex: 0), now: now.addingTimeInterval(5))
        XCTAssertTrue(effects.contains(.cancelNotification(id: AlertIdentifier.rest)),
                      "the rest it interrupted must not fire later")
        XCTAssertTrue(effects.contains(.persist))
        guard case .working = engine.phase else { return XCTFail("deferring resumes work") }

        // And a block-done strip does not survive the reorder it no longer describes.
        var second = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        second.apply(.logSet(step: 0, result: .reps(count: 10, weight: 50)), now: now)
        second.apply(.skipRest, now: now)
        second.apply(.logSet(step: 1, result: .reps(count: 10, weight: 50)), now: now)
        XCTAssertNotNil(second.active.blockDone, "finishing Bench Press leaves a strip")
        second.apply(.deferExercise(exerciseIndex: 1), now: now)
        XCTAssertNil(second.active.blockDone)
    }

    // G64: the cases where there is nothing to do, and the superset that moves as one.
    func testDeferIsANoOpWhenItWouldChangeNothing() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())

        // Nothing pending outside this block: deferring the last exercise moves it nowhere.
        for step in 0..<4 {
            engine.apply(.skipSet(step: step), now: now)
        }
        let before = engine.session.steps
        XCTAssertTrue(engine.apply(.deferExercise(exerciseIndex: 2), now: now).isEmpty)
        XCTAssertEqual(engine.session.steps, before)

        // An exercise with nothing left pending has nothing to defer either.
        var done = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        done.apply(.skipSet(step: 0), now: now)
        done.apply(.skipSet(step: 1), now: now)
        XCTAssertTrue(done.apply(.deferExercise(exerciseIndex: 0), now: now).isEmpty)
        XCTAssertTrue(done.apply(.deferExercise(exerciseIndex: 99), now: now).isEmpty)

        // A superset moves as one block: its members are one station.
        var superset = CoreTestSupport.engine(CoreTestSupport.threeExercises(group: "A"))
        let blocks = Set(superset.session.steps.map(\.blockIndex))
        XCTAssertEqual(blocks.count, 1, "one group means one block, so there is nowhere to move")
        XCTAssertTrue(superset.apply(.deferExercise(exerciseIndex: 0), now: now).isEmpty)

        // And a completed session refuses it outright.
        var finished = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        finished.apply(.finish, now: now)
        XCTAssertTrue(finished.apply(.deferExercise(exerciseIndex: 0), now: now).isEmpty)
    }

    // G61: the overview's block order follows the steps, not `blockIndex`.
    func testOverviewOrderFollowsTheDeferredSteps() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.threeExercises())
        engine.apply(.deferExercise(exerciseIndex: 0), now: now)
        let session = engine.session
        let ordered = Dictionary(grouping: session.steps.indices, by: { session.steps[$0].blockIndex })
            .map { $0.value.sorted() }
            .sorted { ($0.first ?? 0) < ($1.first ?? 0) }
        XCTAssertEqual(ordered.map { session.exercises[session.steps[$0[0]].exerciseIndex].name },
                       ["Row", "Squat", "Bench Press"])
        XCTAssertNotEqual(ordered.map { session.steps[$0[0]].blockIndex }, [0, 1, 2],
                          "sorting by blockIndex would still show the old order")
    }
}
