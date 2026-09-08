import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// V4 (v1.2) — Q34–Q42: the weight rounding of D35 and the per-set suggestions of D36.
///
/// The owner's note was "134 pounds next time doesn't make sense for 135", plus "the steps need
/// a bit of work and suggestions for the sets". Both are about the same thing: a number the app
/// offers has to be one you can act on.
final class SuggestionTests: XCTestCase {
    private let now = CoreTestSupport.now

    // MARK: - D35, rounding

    // Q34: nothing is offered that the equipment cannot make.
    func testSnapRoundsToTheGrid() {
        XCTAssertEqual(WeightRounding.snap(134, increment: 5), 135)
        XCTAssertEqual(WeightRounding.snap(132, increment: 5), 130)
        XCTAssertEqual(WeightRounding.snap(61, increment: 2.5), 60)
        XCTAssertEqual(WeightRounding.snap(62.5, increment: 2.5), 62.5, "already loadable")
        XCTAssertEqual(WeightRounding.snap(1, increment: 5, direction: .up), 5)
        XCTAssertEqual(WeightRounding.snap(9, increment: 5, direction: .down), 5)
        XCTAssertEqual(WeightRounding.snap(-10, increment: 5), 0, "never below zero")
        // "The equipment can make anything" is a legitimate answer.
        XCTAssertEqual(WeightRounding.snap(61.3, increment: 0), 61.3)
        XCTAssertTrue(WeightRounding.isLoadable(135, increment: 5))
        XCTAssertFalse(WeightRounding.isLoadable(134, increment: 5))
    }

    // Q35: "heavier" must actually be heavier, and "lighter" lighter — a suggestion equal to
    // what you just lifted is not advice.
    func testHeavierAndLighterAlwaysMove() {
        // 132 + 2.5 = 134.5, which rounds *down* to 130 on a 5 lb grid. It must go up instead.
        XCTAssertEqual(WeightRounding.heavier(than: 132, target: 134.5, increment: 5), 135)
        XCTAssertEqual(WeightRounding.heavier(than: 60, target: 62.5, increment: 2.5), 62.5)
        XCTAssertEqual(WeightRounding.lighter(than: 132, target: 129.5, increment: 5), 130)
        XCTAssertEqual(WeightRounding.lighter(than: 135, target: 132.5, increment: 5), 130)
        XCTAssertEqual(WeightRounding.lighter(than: 2, target: -3, increment: 5), 0,
                       "and never past zero")
    }

    // Q36: the whole point, end to end. Three sets of 8 at the top of 6–8, on a bar that only
    // makes multiples of 5 lb: the advice is 135, never 134.
    func testProgressionAdviceOnlySuggestsALoadableWeight() throws {
        var exercise = SessionExercise(name: "Bench Press", repRange: RepRange(min: 6, max: 8),
                                       targets: [])
        exercise.targets = Array(repeating: SetTarget(work: .reps(.range(min: 6, max: 8)),
                                                      weight: 132, restSeconds: 90), count: 3)
        let steps = (0..<3).map { index -> SessionStep in
            var step = SessionStep(exerciseIndex: 0, setIndex: index, dropIndex: 0, blockIndex: 0,
                                   isLastInRound: true, isLastInBlock: index == 2)
            step.status = .logged
            step.result = .reps(count: 8, weight: 132)
            return step
        }
        let advice = ProgressionAdvice.evaluate(exercise: exercise, steps: steps,
                                                weightStep: 2.5, increment: 5)
        XCTAssertEqual(advice, .increase(to: 135))

        // And down, on a bar that makes 2.5 kg steps.
        let missed = steps.map { step -> SessionStep in
            var step = step; step.result = .reps(count: 4, weight: 61); return step
        }
        var lighter = exercise
        lighter.targets = exercise.targets.map { var t = $0; t.weight = 61; return t }
        XCTAssertEqual(ProgressionAdvice.evaluate(exercise: lighter, steps: missed,
                                                  weightStep: 2.5, increment: 2.5),
                       .decrease(to: 57.5), "from 61 the next loadable weight down is 57.5")
    }

    // Q37: the steppers land on the grid too. From an off-grid weight the first tap simply
    // brings it onto the grid — 134 lb goes to 135, not to 140.
    func testTheSteppersLandOnALoadableWeight() {
        XCTAssertEqual(InputRules.stepped(weight: 61, by: 2.5, up: true, increment: 2.5), 62.5)
        XCTAssertEqual(InputRules.stepped(weight: 61, by: 2.5, up: false, increment: 2.5), 60)
        XCTAssertEqual(InputRules.stepped(weight: 134, by: 5, up: true, increment: 5), 135)
        XCTAssertEqual(InputRules.stepped(weight: 134, by: 5, up: false, increment: 5), 130)
        // From a loadable weight it moves by a step, rounded onto the grid.
        XCTAssertEqual(InputRules.stepped(weight: 60, by: 2.5, up: true, increment: 2.5), 62.5)
        XCTAssertEqual(InputRules.stepped(weight: 130, by: 2.5, up: true, increment: 5), 135)
        XCTAssertEqual(InputRules.stepped(weight: 0, by: 5, up: false, increment: 5), 0)
        // With no increment given, the old arithmetic is unchanged.
        XCTAssertEqual(InputRules.stepped(weight: 61, by: 2.5, up: true), 63.5)
    }

    // MARK: - D36, per-set suggestions

    private func session(_ plan: Plan, history: [Session]) -> (Session, [Session]) {
        (CoreTestSupport.session(plan, start: now), history)
    }

    // Q38: with no history, the suggestion is the plan's own target — said as a set to aim for.
    func testTheFirstTimeTheSuggestionIsThePlansTarget() {
        let plan = CoreTestSupport.plan(sets: 3, weight: 60)
        let values = Prefill.values(session: CoreTestSupport.session(plan), step: 0, history: [])
        let suggestion = values.suggestion
        XCTAssertEqual(suggestion?.text, "8 × 60 kg")
        XCTAssertEqual(suggestion?.reason, "The plan's target")
        XCTAssertEqual(suggestion?.isProgression, false)
        XCTAssertEqual(StepCard.suggestionChip(values, units: .kg), "Try 8 × 60 kg")
    }

    // Q39: with a last time and no advice, it says what you did, and says so.
    func testWithHistoryItRepeatsLastTimeAndSaysWhy() {
        let plan = CoreTestSupport.plan(sets: 3, weight: 60)
        let last = CoreTestSupport.completed([10, 10, 9], weights: [70, 70, 70], plan: plan)
        let values = Prefill.values(session: CoreTestSupport.session(plan), step: 0,
                                    history: [last])
        XCTAssertEqual(values.suggestion?.weight, 70)
        XCTAssertEqual(values.suggestion?.reason, "Last time 10 × 70 kg")
        XCTAssertEqual(values.suggestion?.isProgression, false)
    }

    // Q40: advice wins over "do that again", and says which rule produced it.
    func testAdviceWinsAndExplainsItself() throws {
        let plan = CoreTestSupport.plan(sets: 3, weight: 60)
        var last = CoreTestSupport.completed([12, 12, 12], weights: [60, 60, 60], plan: plan)
        last.exercises[0].advice = .increase(to: 62.5)
        let values = Prefill.values(session: CoreTestSupport.session(plan), step: 0,
                                    history: [last])
        let suggestion = try XCTUnwrap(values.suggestion)
        XCTAssertEqual(suggestion.weight, 62.5)
        XCTAssertTrue(suggestion.isProgression)
        XCTAssertEqual(suggestion.reason, "You hit the top of 8–12 last time")
        XCTAssertEqual(suggestion.chip, "Try 8 × 62.5 kg")
    }

    // Q41: a suggestion carried over from advice is snapped to the grid on the way out, in case
    // it was stored by a version — or a setting — that used a different one.
    func testAStoredSuggestionIsStillSnappedOnTheWayOut() throws {
        let plan = CoreTestSupport.plan(sets: 3, weight: 60)
        var last = CoreTestSupport.completed([12, 12, 12], weights: [60, 60, 60], plan: plan)
        last.exercises[0].advice = .increase(to: 61)          // not loadable on a 2.5 kg grid
        let values = Prefill.values(session: CoreTestSupport.session(plan), step: 0,
                                    history: [last],
                                    settings: Settings(weightIncrementKg: 2.5))
        XCTAssertEqual(try XCTUnwrap(values.suggestion).weight, 60)
        XCTAssertEqual(values.suggestedWeight, 60)
    }

    // Q42: a timed set is measured in seconds, so it is never offered reps or a weight.
    func testATimedSetIsSuggestedInSeconds() {
        let plan = CoreTestSupport.plan(sets: 2, work: .duration(seconds: 45), weight: nil,
                                        bodyweight: true)
        var last = CoreTestSupport.completed([1, 1], plan: plan)
        for index in last.steps.indices {
            last.steps[index].result = .duration(seconds: 60, weight: nil)
        }
        let values = Prefill.values(session: CoreTestSupport.session(plan), step: 0,
                                    history: [last])
        XCTAssertEqual(values.suggestion?.text, "60 s")
        XCTAssertNil(values.suggestion?.reps)
        XCTAssertNil(values.suggestion?.weight)
        XCTAssertEqual(values.suggestion?.reason, "Last time you held 1:00")
    }
}
