import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// v1.12's fix-first milestone (F1–F4): the 2026-09-24 audit read the screens against each other,
/// and where one screen said or did a thing differently from its neighbour in a way that could
/// lose work or mislead, these pin the side that won. TF1–TF5 in `docs/TEST_CASES.md`.
final class ScreenAuditTests: XCTestCase {
    private let now = CoreTestSupport.now

    // TF1 (F1): Edit the text is an edit, as Apply is — the id, the import date and the
    // progression stay and the text's own days land; its sheet names the progression among what
    // stays. A name-conflict Replace on import is a new plan, and starts without one.
    func testEditTheTextKeepsTheProgression() throws {
        var plan = CoreTestSupport.plan()
        plan.progression = Progression(startDate: now, weeks: 2, entries: [
            ProgressionEntry(dayName: "Push", exerciseName: "Bench Press",
                             weeks: [ProgressionWeek(weight: 62.5), ProgressionWeek()]),
        ])
        var library = PlanLibrary()
        library.save(plan, makeActive: true)

        var text = CoreTestSupport.plan(sets: 4)
        text.importedAt = now.addingTimeInterval(86_400)
        XCTAssertEqual(library.replace(plan.id, with: text), plan.id)
        XCTAssertEqual(library.plans[0].progression, plan.progression)
        XCTAssertEqual(library.plans[0].importedAt, plan.importedAt, "an edit keeps the import date, as Apply does")
        XCTAssertEqual(library.plans[0].days[0].exercises[0].sets.count, 4, "the text's own days land")
        XCTAssertEqual(library.activePlanId, plan.id)
        XCTAssertTrue(JSONPoint.replacing("Training", text: "").place.contains("its progression stay"))
        // Plan detail's Edit the text is that edit from text, through the one JSON sheet (L5).
        let edited = PlanEdit.apply(.replacePlanJSON(text: PlanJSON.render(CoreTestSupport.plan(sets: 5))),
                                    to: library.plans[0], settings: Settings(), now: now)
        XCTAssertEqual(edited.plan?.progression, plan.progression)
        XCTAssertEqual(edited.plan?.id, plan.id)
        XCTAssertEqual(edited.plan?.days[0].exercises[0].sets.count, 5)

        library.save(CoreTestSupport.plan(), conflict: .replace)
        XCTAssertNil(library.plans[0].progression, "a name-conflict Replace on import is a new plan")
    }

    // TF2 (F2): the three new confirmations each name what they act on. The day editor's Back,
    // built for a real date, is pinned beside its title in DayEditTests.
    func testTheConfirmationsNameWhatTheyActOn() {
        XCTAssertEqual(WorkoutText.skipExercise("Bench Press"), "Skip the rest of Bench Press?")
        let plan = CoreTestSupport.plan(secondExercise: true)
        XCTAssertEqual(PlanText.deleteExercise(plan, day: 0, exercise: 1), "Delete Row from Push?")
        XCTAssertNil(PlanText.deleteExercise(plan, day: 0, exercise: 2), "an address gone since asks nothing")
        XCTAssertNil(PlanText.deleteExercise(plan, day: 1, exercise: 0))
        XCTAssertEqual(ChangeDayText.discardOwn(weekday: "Wednesday"), "Discard Wednesday's exercises?")
        XCTAssertEqual(ChangeDayText.backResult(weekday: "Wednesday", dayName: "Push"),
                       "Wednesday goes back to Push as written.")
    }

    // TF5 (F4): a set standing alone reads reps first, with its unit — Last time, Best, Heaviest
    // set, Find an exercise's top set and the Summary's record alike. A row in a list of sets
    // leaves the unit to the list; the compact notation names none.
    func testASetReadsRepsFirstEverywhere() {
        let set = SetResult.reps(count: 10, weight: 60)
        XCTAssertEqual(StepCard.setText(set, units: .kg), "10 × 60 kg")
        XCTAssertEqual(StepCard.setText(set, units: .lb), "10 × 60 lb")
        XCTAssertEqual(StepCard.setText(set, units: .kg, wording: .compact), "10 @ 60")
        XCTAssertEqual(StepCard.setText(.reps(count: 10, weight: nil), units: .kg), "10")
        XCTAssertEqual(StepCard.resultText(set), "10 × 60", "a row leaves the unit to its list")

        XCTAssertEqual(ExerciseText.bestSet(set, units: .kg), "10 × 60 kg")
        XCTAssertEqual(ExerciseText.bestSet(.reps(count: 12, weight: nil), units: .kg), "12 reps")
        XCTAssertEqual(ExerciseText.bestSet(.duration(seconds: 45, weight: 20), units: .kg), TargetText.time(45))
    }
}
