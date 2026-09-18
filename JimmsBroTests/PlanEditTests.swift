import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// R5.2 (v1.1) — editing a plan in the app (D29): L39–L44 and the C-section round trip.
/// Every edit is rendered back to JSON and re-imported, so the pipeline that validates an
/// import is the one that validates an edit.
final class PlanEditTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let settings = Settings()

    private func imported(_ file: String) throws -> Plan {
        let result = PlanImport.run(try FixtureLoader.text(file), settings: settings, now: now)
        return try XCTUnwrap(result.plan, "\(file): \(result.issues)")
    }

    // C-section: rendering a plan and importing it again is a fixpoint, for every valid fixture.
    // This is what lets an edit go out through the real pipeline instead of around it.
    func testRenderReimportsIdenticallyForEveryValidFixture() throws {
        var checked = 0
        for fixture in try FixtureLoader.manifest().fixtures where fixture.outcome == .valid {
            let original = try imported(fixture.file)
            let rendered = PlanJSON.render(original)
            let round = PlanImport.run(rendered, settings: settings, now: now)
            let again = try XCTUnwrap(round.plan, "\(fixture.file) failed to re-import: \(round.issues)")
            XCTAssertTrue(round.issues.filter { $0.severity == .error }.isEmpty,
                          "\(fixture.file): \(round.issues)")
            // `render` ignores ids, dates and warnings, so equal output means an equal plan.
            XCTAssertEqual(PlanJSON.render(again), rendered, "\(fixture.file) did not round-trip")
            // And the shape itself survives, not just the text.
            XCTAssertEqual(again.days.count, original.days.count, fixture.file)
            XCTAssertEqual(again.days.map { $0.exercises.count },
                           original.days.map { $0.exercises.count }, fixture.file)
            XCTAssertEqual(again.days.flatMap { $0.exercises.map { $0.sets.count } },
                           original.days.flatMap { $0.exercises.map { $0.sets.count } }, fixture.file)
            XCTAssertEqual(again.cycle, original.cycle, fixture.file)
            XCTAssertEqual(again.schedule, original.schedule, fixture.file)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20, "the valid fixtures must actually have been exercised")
    }

    // L39: the everyday edits, each validated by the import pipeline on the way through.
    func testExerciseEdits() throws {
        let plan = try imported("valid/weekly-rotation.json")
        func edit(_ op: PlanEdit.Operation, _ plan: Plan) throws -> Plan {
            let result = PlanEdit.apply(op, to: plan, settings: settings, now: now)
            return try XCTUnwrap(result.plan, "\(result.issues)")
        }

        let renamed = try edit(.renameExercise(day: 0, exercise: 0, name: "  Flat Bench  "), plan)
        XCTAssertEqual(renamed.days[0].exercises[0].name, "Flat Bench", "trimmed like an import")
        XCTAssertEqual(renamed.id, plan.id, "the same plan, changed")
        XCTAssertEqual(renamed.importedAt, plan.importedAt)
        XCTAssertEqual(renamed.sourceText, PlanJSON.render(renamed),
                       "Copy JSON and the export file reflect the edit")

        let fewer = try edit(.setSetCount(day: 0, exercise: 0, count: 2), plan)
        XCTAssertEqual(fewer.days[0].exercises[0].sets.count, 2)
        let more = try edit(.setSetCount(day: 0, exercise: 0, count: 6), plan)
        XCTAssertEqual(more.days[0].exercises[0].sets.count, 6)
        XCTAssertEqual(more.days[0].exercises[0].sets[5], more.days[0].exercises[0].sets[3],
                       "a new set repeats the last one")

        let heavier = try edit(.setWeight(day: 0, exercise: 0, weight: 82.5), plan)
        XCTAssertEqual(heavier.days[0].exercises[0].sets.map(\.weight), Array(repeating: 82.5, count: 4))
        let unloaded = try edit(.setWeight(day: 0, exercise: 0, weight: nil), plan)
        XCTAssertTrue(unloaded.days[0].exercises[0].sets.allSatisfy { $0.weight == nil })

        let ranged = try edit(.setReps(day: 0, exercise: 0, text: "5-8"), plan)
        XCTAssertEqual(ranged.days[0].exercises[0].sets[0].work, .reps(.range(min: 5, max: 8)))
        let amrap = try edit(.setReps(day: 0, exercise: 0, text: "AMRAP"), plan)
        XCTAssertEqual(amrap.days[0].exercises[0].sets[0].work, .reps(.amrap(min: nil)))
        let timed = try edit(.setReps(day: 0, exercise: 0, text: "45s"), plan)
        XCTAssertEqual(timed.days[0].exercises[0].sets[0].work, .duration(seconds: 45))

        let rested = try edit(.setRest(day: 0, exercise: 0, seconds: 210), plan)
        XCTAssertTrue(rested.days[0].exercises[0].sets.allSatisfy { $0.restSeconds == 210 })

        let noRange = try edit(.setRepRange(day: 0, exercise: 0, text: nil), plan)
        XCTAssertNil(noRange.days[0].exercises[0].repRange)
        let newRange = try edit(.setRepRange(day: 0, exercise: 0, text: "4–6"), plan)
        XCTAssertEqual(newRange.days[0].exercises[0].repRange, RepRange(min: 4, max: 6),
                       "an en dash is accepted, as it is on import")
    }

    // L40: reordering and deleting.
    func testReorderAndDelete() throws {
        let plan = try imported("valid/weekly-rotation.json")
        let names = plan.days[0].exercises.map(\.name)
        XCTAssertGreaterThan(names.count, 2)

        let moved = try XCTUnwrap(PlanEdit.apply(.moveExercise(day: 0, from: 0, to: 2),
                                                 to: plan, settings: settings, now: now).plan)
        var expected = names
        expected.insert(expected.remove(at: 0), at: 2)
        XCTAssertEqual(moved.days[0].exercises.map(\.name), expected)

        let deleted = try XCTUnwrap(PlanEdit.apply(.deleteExercise(day: 0, exercise: 1),
                                                   to: plan, settings: settings, now: now).plan)
        XCTAssertEqual(deleted.days[0].exercises.count, names.count - 1)
        XCTAssertFalse(deleted.days[0].exercises.map(\.name).contains(names[1]))
    }

    // L41: duplicating a day, and what it deliberately does not touch.
    func testDuplicateDay() throws {
        let plan = try imported("valid/weekly-rotation.json")
        let result = PlanEdit.apply(.duplicateDay(day: 0), to: plan, settings: settings, now: now)
        let copied = try XCTUnwrap(result.plan, "\(result.issues)")
        XCTAssertEqual(copied.days.count, plan.days.count + 1)
        XCTAssertEqual(copied.days[1].name, "\(plan.days[0].name) copy")
        XCTAssertEqual(copied.days[1].exercises.map(\.name), plan.days[0].exercises.map(\.name))
        XCTAssertNotEqual(copied.days[1].id, copied.days[0].id, "a copy is its own day")
        // The cycle is untouched: duplicating a day is not a request to train more often.
        XCTAssertEqual(copied.cycle.count, plan.cycle.count)
    }

    // L42: an edit that would break the plan is refused, and the plan is left alone.
    func testInvalidEditsAreRefused() throws {
        let plan = try imported("valid/weekly-rotation.json")
        func refused(_ op: PlanEdit.Operation) {
            let result = PlanEdit.apply(op, to: plan, settings: settings, now: now)
            XCTAssertNil(result.plan, "\(op) should have been refused")
            XCTAssertFalse(result.issues.filter { $0.severity == .error }.isEmpty)
        }
        refused(.renameExercise(day: 0, exercise: 0, name: "   "))
        refused(.renameExercise(day: 9, exercise: 0, name: "Bench"))
        refused(.setSetCount(day: 0, exercise: 0, count: 0))
        refused(.setSetCount(day: 0, exercise: 0, count: 51))
        refused(.setReps(day: 0, exercise: 0, text: "banana"))
        refused(.setRest(day: 0, exercise: 0, seconds: -1))
        refused(.setRest(day: 0, exercise: 0, seconds: 3_601))
        refused(.setWeight(day: 0, exercise: 0, weight: 20_000))
        refused(.setRepRange(day: 0, exercise: 0, text: "12-8"))
        refused(.moveExercise(day: 0, from: 0, to: 99))
        refused(.duplicateDay(day: 42))

        // Deleting the last exercise would leave a day with none, which the importer rejects.
        var single = plan
        single.days[0].exercises = [plan.days[0].exercises[0]]
        let result = PlanEdit.apply(.deleteExercise(day: 0, exercise: 0), to: single,
                                    settings: settings, now: now)
        XCTAssertNil(result.plan)
    }

    // L43: the plan-format vocabulary the reps field accepts is the chatbot's vocabulary.
    func testRepsVocabulary() throws {
        XCTAssertEqual(PlanEdit.parseWork("10"), .reps(.fixed(10)))
        XCTAssertEqual(PlanEdit.parseWork(" 8-12 "), .reps(.range(min: 8, max: 12)))
        XCTAssertEqual(PlanEdit.parseWork("8–12"), .reps(.range(min: 8, max: 12)))
        XCTAssertEqual(PlanEdit.parseWork("amrap"), .reps(.amrap(min: nil)))
        XCTAssertEqual(PlanEdit.parseWork("MAX"), .reps(.amrap(min: nil)))
        XCTAssertEqual(PlanEdit.parseWork("5+"), .reps(.amrap(min: 5)))
        XCTAssertEqual(PlanEdit.parseWork("45s"), .duration(seconds: 45))
        XCTAssertNil(PlanEdit.parseWork(""))
        XCTAssertNil(PlanEdit.parseWork("soon"))
        XCTAssertNil(PlanEdit.parseWork("-3"))
        XCTAssertNil(PlanEdit.parseWork("0s"))
        XCTAssertEqual(PlanEdit.parseRange("8-12"), RepRange(min: 8, max: 12))
        XCTAssertNil(PlanEdit.parseRange("12-8"), "a backwards range is not a range")
        // TL2 (D96): the field reads a range as a plan's repRange is read — one number is 8–8.
        XCTAssertEqual(PlanEdit.parseRange("8"), RepRange(min: 8, max: 8))
    }

    // L45: `text(for:)` and `parseWork` are inverses. Without this, opening the edit sheet on a
    // timed set and pressing Save would silently turn it into a rep set, because "30+" reads as
    // an AMRAP rep target while `.openDuration(30)` is a hold.
    func testWorkTextRoundTripsThroughTheParser() throws {
        let every: [WorkTarget] = [
            .reps(.fixed(1)), .reps(.fixed(12)), .reps(.fixed(1000)),
            .reps(.range(min: 8, max: 12)), .reps(.range(min: 1, max: 1000)),
            .reps(.amrap(min: nil)), .reps(.amrap(min: 5)),
            .duration(seconds: 1), .duration(seconds: 45), .duration(seconds: 86_400),
            .openDuration(minSeconds: nil), .openDuration(minSeconds: 30),
        ]
        for work in every {
            let text = PlanEdit.text(for: work)
            XCTAssertEqual(PlanEdit.parseWork(text), work,
                           "\(work) printed as \"\(text)\" and came back different")
        }
        // The four shapes stay apart, which is the whole point of the "s" suffix.
        XCTAssertEqual(PlanEdit.parseWork("30+"), .reps(.amrap(min: 30)))
        XCTAssertEqual(PlanEdit.parseWork("30s+"), .openDuration(minSeconds: 30))
        XCTAssertEqual(PlanEdit.parseWork("30s"), .duration(seconds: 30))
        XCTAssertEqual(PlanEdit.parseWork("30"), .reps(.fixed(30)))
        XCTAssertEqual(PlanEdit.parseWork("open"), .openDuration(minSeconds: nil))
        XCTAssertEqual(PlanEdit.parseWork("max"), .reps(.amrap(min: nil)),
                       "in a field you type reps into, \"max\" means reps")
    }

    // L44: an edited plan still runs — the sets it produces are the sets you asked for.
    func testEditedPlanStillFlattensAndRuns() throws {
        let plan = try imported("valid/weekly-rotation.json")
        let edited = try XCTUnwrap(PlanEdit.apply(.setSetCount(day: 0, exercise: 0, count: 2),
                                                  to: plan, settings: settings, now: now).plan)
        let before = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now))
        let after = try XCTUnwrap(Session.start(plan: edited, dayIndex: 0, now: now))
        XCTAssertEqual(after.steps.count, before.steps.count - 2, "two sets fewer, two steps fewer")

        var engine = SessionEngine(session: after, settings: CoreTestSupport.classic, now: now)
        engine.apply(.logSet(step: 0, result: .reps(count: 8, weight: 80)), now: now)
        XCTAssertEqual(engine.session.steps[0].status, .logged)
    }
}
