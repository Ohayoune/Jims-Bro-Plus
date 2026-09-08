import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Z1 (v1.5) — D50: clearer, not louder. The sentences that explain the chatbot round-trip,
/// the rule for Home's quiet link, and the views pinned to both.
final class ClarityTests: XCTestCase {
    private let now = CoreTestSupport.now

    // Z1: the four sentences say what they must.
    func testTheSentences() {
        for text in [PromptText.copyStep, PromptText.mechanism, PromptText.progressionRow, PromptText.planProgression] {
            XCTAssertFalse(text.trimmed.isEmpty)
        }
        XCTAssertTrue(PromptText.copyStep.hasPrefix("Copy the prompt."))
        XCTAssertTrue(PromptText.copyStep.contains("format") && PromptText.copyStep.contains("reply"))
        XCTAssertTrue(PromptText.mechanism.contains("never talks to the chatbot"))
        XCTAssertTrue(PromptText.progressionRow.contains("chatbot") && PromptText.progressionRow.contains("lifted"))
        XCTAssertEqual(PromptText.planProgression, "Plan a progression")
    }

    // Z2: the link appears only with history for every exercise on the day, and no progression.
    func testWhenHomeOffersAProgression() throws {
        var library = PlanLibrary()
        XCTAssertFalse(HomeStart.current(library: library, now: now).offersProgression, "no plan")

        // A two-exercise day, nothing logged yet.
        let plan = CoreTestSupport.plan(secondExercise: true)
        library.save(plan, makeActive: true)
        XCTAssertFalse(HomeStart.current(library: library, now: now).offersProgression, "nothing logged")

        // One exercise logged is not enough: the prompt would have nothing for the other.
        var partial = CoreTestSupport.session(plan, start: now.addingTimeInterval(-86400))
        for index in partial.steps.indices where partial.steps[index].exerciseIndex == 0 {
            partial.steps[index].status = .logged
            partial.steps[index].result = .reps(count: 10, weight: 60)
            partial.steps[index].loggedAt = partial.startedAt.addingTimeInterval(Double(index) * 60)
        }
        partial.endedAt = partial.startedAt.addingTimeInterval(1800)
        library.sessions = [partial]
        XCTAssertFalse(HomeStart.current(library: library, now: now).offersProgression, "one exercise never logged")

        // Both logged: the link is there.
        let full = CoreTestSupport.completed([10, 10, 8], plan: plan, start: now.addingTimeInterval(-86400))
        library.sessions = [full]
        let card = HomeStart.current(library: library, now: now)
        XCTAssertTrue(card.offersProgression)
        XCTAssertNotNil(card.planId)

        // A running workout does not offer it; the card is the workout's.
        var running = library
        _ = try running.startDay(planId: plan.id, dayIndex: 0, now: now)
        XCTAssertFalse(HomeStart.current(library: running, now: now).offersProgression, "in progress")

        // A progression attached takes it away.
        var progressed = library
        progressed.plans[0].progression = Progression(startDate: now, weeks: 4, entries: [])
        XCTAssertFalse(HomeStart.current(library: progressed, now: now).offersProgression, "already planned")

        // History of another day's exercises does not count for this day.
        var other = CoreTestSupport.plan()
        other.days[0].name = "Pull"
        other.days[0].exercises[0].name = "Deadlift"
        var twoDays = plan
        twoDays.days.append(other.days[0])
        twoDays.cycle = [.day(0), .day(1)]
        var again = PlanLibrary()
        again.save(twoDays, makeActive: true)
        again.sessions = [full]
        // Today is Push (day 0), whose two exercises are both in `full`.
        XCTAssertTrue(HomeStart.current(library: again, now: now).offersProgression)
    }

    // Z3: the views show the Core sentences, not copies of them.
    func testTheViewsShowTheCoreSentences() throws {
        let pins: [(file: String, literal: String)] = [
            ("JimmsBro/Features/Import/ImportView.swift", "PromptText.copyStep"),
            ("JimmsBro/Features/Import/ImportView.swift", "PromptText.mechanism"),
            ("JimmsBro/Features/PlanDetail/ProgressionView.swift", "PromptText.copyStep"),
            ("JimmsBro/Features/PlanDetail/ProgressionView.swift", "PromptText.mechanism"),
            ("JimmsBro/Features/PlanDetail/PlanDetailView.swift", "PromptText.progressionRow"),
            ("JimmsBro/Features/Home/HomeView.swift", "PromptText.planProgression"),
            ("JimmsBro/Features/Home/HomeView.swift", "card.offersProgression"),
        ]
        for pin in pins {
            guard let source = FixtureLoader.doc(pin.file) else {
                throw XCTSkip("\(pin.file) is outside the simulator's sandbox; this pin runs on the host routes")
            }
            XCTAssertTrue(source.contains(pin.literal), "\(pin.file) no longer shows \(pin.literal)")
        }
        // And the old bare sentences are gone from the views.
        if let source = FixtureLoader.doc("JimmsBro/Features/Import/ImportView.swift") {
            XCTAssertFalse(source.contains("step(1, \"Copy the prompt.\")"))
        }
    }
}
