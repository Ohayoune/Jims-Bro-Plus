import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// X3 (v1.3) — D43, W13–W20: JSON edits at every size. A fragment — one exercise, one day, or
/// a pasted list of either — is spliced into the plan's own JSON tree and re-imported, so the
/// pipeline that validates a paste validates an edit, and its errors name the real place.
final class JSONEditTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let settings = Settings()

    private func imported(_ file: String) throws -> Plan {
        let result = PlanImport.run(try FixtureLoader.text(file), settings: settings, now: now)
        return try XCTUnwrap(result.plan, "\(file): \(result.issues)")
    }

    private func apply(_ operation: PlanEdit.Operation, _ plan: Plan) -> ImportResult {
        PlanEdit.apply(operation, to: plan, settings: settings, now: now)
    }

    private func edited(_ operation: PlanEdit.Operation, _ plan: Plan,
                        file: StaticString = #filePath, line: UInt = #line) throws -> Plan {
        let result = apply(operation, plan)
        return try XCTUnwrap(result.plan, "\(result.issues)", file: file, line: line)
    }

    // W13: a fragment spliced over itself changes nothing, for every day and exercise of every
    // valid fixture — which is what makes "edit the text of this part" safe to offer.
    func testAFragmentSplicedOverItselfChangesNothing() throws {
        var checked = 0
        for fixture in try FixtureLoader.manifest().fixtures where fixture.outcome == .valid {
            let plan = try imported(fixture.file)
            let rendered = PlanJSON.render(plan)
            for (d, day) in plan.days.enumerated() {
                let sameDay = try edited(.replaceDayJSON(day: d, text: PlanJSON.render(day: day)), plan)
                XCTAssertEqual(PlanJSON.render(sameDay), rendered, "\(fixture.file) day \(d)")
                for (e, exercise) in day.exercises.enumerated() {
                    let same = try edited(.replaceExerciseJSON(day: d, exercise: e,
                                                               text: PlanJSON.render(exercise: exercise)), plan)
                    XCTAssertEqual(PlanJSON.render(same), rendered, "\(fixture.file) exercise \(d).\(e)")
                }
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20, "the valid fixtures must actually have been exercised")
    }

    // W14: a compact fragment replaces one exercise; its neighbours and the plan's identity stay.
    func testReplacingAnExerciseFromCompactJSON() throws {
        var plan = try imported("valid/weekly-rotation.json")
        plan.cyclePosition = 1
        plan.cycleAnchor = CoreTestSupport.date(1)
        let text = #"{ "name": "Barbell Bench Press", "sets": 5, "reps": 5, "repRange": "4-6", "weight": 100, "restSeconds": 180, "notes": "Belt on" }"#
        let again = try edited(.replaceExerciseJSON(day: 0, exercise: 0, text: text), plan)

        let bench = again.days[0].exercises[0]
        XCTAssertEqual(bench.sets.count, 5)
        XCTAssertEqual(bench.sets.map(\.weight), Array(repeating: 100, count: 5))
        XCTAssertEqual(bench.sets.first?.work, .reps(.fixed(5)))
        XCTAssertEqual(bench.repRange, RepRange(min: 4, max: 6))
        XCTAssertEqual(bench.sets.first?.restSeconds, 180)
        XCTAssertEqual(bench.notes, "Belt on")
        XCTAssertEqual(again.days[0].exercises.dropFirst().map(\.name),
                       plan.days[0].exercises.dropFirst().map(\.name))
        XCTAssertEqual(again.days.count, plan.days.count)
        XCTAssertEqual(again.id, plan.id)
        XCTAssertEqual(again.importedAt, plan.importedAt)
        XCTAssertEqual(again.cyclePosition, 1)
        XCTAssertEqual(again.cycleAnchor, plan.cycleAnchor)
        XCTAssertEqual(again.sourceText, PlanJSON.render(again), "what the plan keeps is the canonical text")
    }

    // W15: one set unlike the others — what the structured sheet cannot say (SPEC §10, closed).
    func testOneSetCanDifferFromTheOthers() throws {
        let plan = try imported("valid/weekly-rotation.json")
        let text = """
        { "name": "Barbell Bench Press", "repRange": "6-8", "restSeconds": 150,
          "sets": [ { "reps": 8, "weight": 70 }, { "reps": 6, "weight": 80, "restSeconds": 240 }, { "reps": 4, "weight": 90 } ] }
        """
        let again = try edited(.replaceExerciseJSON(day: 0, exercise: 0, text: text), plan)
        let sets = again.days[0].exercises[0].sets
        XCTAssertEqual(sets.map(\.weight), [70, 80, 90])
        XCTAssertEqual(sets.map(\.restSeconds), [150, 240, 150])
        XCTAssertEqual(sets.map(\.work), [.reps(.fixed(8)), .reps(.fixed(6)), .reps(.fixed(4))])
        // And the structured editor's own round trip keeps it.
        let round = PlanImport.run(PlanJSON.render(again), settings: settings, now: now)
        XCTAssertEqual(round.plan?.days[0].exercises[0].sets.map(\.weight), [70, 80, 90])
    }

    // W16: a refused fragment names the real place, and the plan is untouched.
    func testARefusedFragmentNamesTheRealPlace() throws {
        let plan = try imported("valid/weekly-rotation.json")
        let bad = #"{ "name": "Barbell Bench Press", "sets": [ { "reps": "eight", "weight": 80 } ] }"#
        let result = apply(.replaceExerciseJSON(day: 0, exercise: 1, text: bad), plan)
        XCTAssertNil(result.plan)
        let error = try XCTUnwrap(result.errors.first)
        XCTAssertEqual(error.code, "E_REPS_INVALID")
        XCTAssertEqual(error.path, "days[0].exercises[1].sets[0].reps")
        XCTAssertEqual(IssueText.location(error.path), "Day 1, exercise 2, set 1")

        XCTAssertEqual(apply(.replaceExerciseJSON(day: 0, exercise: 1, text: "bench 3x10"), plan).errors.first?.code, "E_NOT_JSON")
        XCTAssertEqual(apply(.replaceExerciseJSON(day: 0, exercise: 1, text: "[1, 2]"), plan).errors.first?.code, "E_NOT_A_PLAN")
        XCTAssertEqual(apply(.replaceExerciseJSON(day: 0, exercise: 1, text: #"[{"name":"A"},{"name":"B"}]"#), plan).errors.first?.code,
                       "E_EDIT_INVALID", "two exercises where one goes")
        XCTAssertEqual(apply(.replaceExerciseJSON(day: 9, exercise: 0, text: "{}"), plan).errors.first?.code, "E_EDIT_INVALID")
        XCTAssertEqual(apply(.replaceDayJSON(day: 0, text: "{ \"name\": \"X\" }"), plan).errors.first?.code, "E_NO_EXERCISES",
                       "a day with nothing in it is a day the importer refuses")
    }

    // W17: adding exercises — at the end, at an index, several at once, out of a day, with
    // prose and a fence around them.
    func testAddingExercises() throws {
        let plan = try imported("valid/weekly-rotation.json")
        let before = plan.days[1].exercises.map(\.name)

        let one = try edited(.insertExercisesJSON(day: 1, at: nil, text: #"{ "name": "Face Pull", "sets": 3, "reps": 15, "weight": 20 }"#), plan)
        XCTAssertEqual(one.days[1].exercises.map(\.name), before + ["Face Pull"])
        XCTAssertEqual(one.days[1].exercises.last?.sets.count, 3)
        XCTAssertEqual(one.days[0].exercises.map(\.name), plan.days[0].exercises.map(\.name), "other days untouched")

        let pasted = "Here you go:\n```json\n[{\"name\":\"Face Pull\",\"sets\":3,\"reps\":15},{\"name\":\"Curl\",\"sets\":3,\"reps\":12}]\n```"
        let atStart = try edited(.insertExercisesJSON(day: 1, at: 0, text: pasted), plan)
        XCTAssertEqual(atStart.days[1].exercises.prefix(2).map(\.name), ["Face Pull", "Curl"])
        XCTAssertEqual(atStart.days[1].exercises.count, before.count + 2)

        let fromDay = try edited(.insertExercisesJSON(day: 1, at: nil, text: #"{ "name": "Extra", "exercises": [ { "name": "Shrug", "sets": 3, "reps": 12 } ] }"#), plan)
        XCTAssertEqual(fromDay.days[1].exercises.last?.name, "Shrug")
        XCTAssertEqual(fromDay.days.count, plan.days.count, "a day pasted as exercises adds no day")

        XCTAssertEqual(apply(.insertExercisesJSON(day: 1, at: nil, text: "[]"), plan).errors.first?.code, "E_NOT_A_PLAN")
        XCTAssertEqual(apply(.insertExercisesJSON(day: 1, at: nil, text: #"{ "name": "" , "sets": 3, "reps": 10 }"#), plan).errors.first?.code,
                       "E_MISSING_NAME", "the template's blank name is refused with a sentence, not saved")
    }

    // W18: adding days — a bare day, a whole plan holding the missing days (the truncated
    // week), and a weekday plan insisting on a weekday. A new day joins the rotation.
    func testAddingDays() throws {
        let plan = try imported("valid/weekly-rotation.json")
        let bare = try edited(.insertDaysJSON(text: #"{ "name": "Arms", "exercises": [ { "name": "Curl", "sets": 3, "reps": 12 } ] }"#), plan)
        XCTAssertEqual(bare.days.map(\.name), plan.days.map(\.name) + ["Arms"])
        XCTAssertEqual(bare.cycle, plan.cycle + [.day(plan.days.count)])
        XCTAssertEqual(bare.cyclePosition, plan.cyclePosition)

        let whole = "```json\n{ \"name\": \"Rest of the week\", \"days\": [ { \"name\": \"Arms\", \"exercises\": [ { \"name\": \"Curl\", \"sets\": 3, \"reps\": 12 } ] }, { \"exercises\": [ { \"name\": \"Plank\", \"sets\": 3, \"durationSeconds\": 45, \"bodyweight\": true } ] } ] }\n```"
        let week = try edited(.insertDaysJSON(text: whole), plan)
        XCTAssertEqual(week.days.map(\.name), plan.days.map(\.name) + ["Arms", "Day \(plan.days.count + 2)"])
        XCTAssertEqual(week.name, plan.name, "the pasted plan's own name is not taken")
        XCTAssertEqual(Array(week.cycle.suffix(2)), [.day(plan.days.count), .day(plan.days.count + 1)])
        XCTAssertFalse(week.warnings.contains { $0.code == "W_CYCLE_MISSING_DAY" })
        XCTAssertFalse(week.warnings.contains { $0.code == "W_DEFAULT_NAME" }, "named here, deliberately")

        let weekday = try imported("valid/weekly-weekday.json")
        let refused = apply(.insertDaysJSON(text: #"{ "name": "Arms", "exercises": [ { "name": "Curl", "sets": 3, "reps": 12 } ] }"#), weekday)
        XCTAssertEqual(refused.errors.first?.code, "E_WEEKDAY_MISSING")
        XCTAssertEqual(refused.errors.first?.path, "days[\(weekday.days.count)].weekday")
        let free = try XCTUnwrap(Weekday.allCases.first { day in !weekday.days.contains { $0.weekday == day } })
        let placed = try edited(.insertDaysJSON(text: "{ \"name\": \"Arms\", \"weekday\": \"\(free.rawValue)\", \"exercises\": [ { \"name\": \"Curl\", \"sets\": 3, \"reps\": 12 } ] }"), weekday)
        XCTAssertEqual(placed.days.last?.weekday, free)
        XCTAssertEqual(placed.cycle[Weekday.allCases.firstIndex(of: free)!], .day(weekday.days.count))
    }

    // W19: a day replaced as text keeps its place in the repeat block, renamed or not.
    func testReplacingADayKeepsItsPlaceInTheRepeatBlock() throws {
        let plan = try imported("valid/weekly-rotation.json")
        let renamed = try edited(.replaceDayJSON(day: 0, text: #"{ "name": "Chest", "exercises": [ { "name": "Bench", "sets": 3, "reps": 8 } ] }"#), plan)
        XCTAssertEqual(renamed.days[0].name, "Chest")
        XCTAssertEqual(renamed.cycle, plan.cycle)
        XCTAssertEqual(renamed.days[0].exercises.map(\.name), ["Bench"])
        XCTAssertEqual(renamed.days.dropFirst().map(\.name), plan.days.dropFirst().map(\.name))

        let unnamed = try edited(.replaceDayJSON(day: 0, text: #"{ "exercises": [ { "name": "Bench", "sets": 3, "reps": 8 } ] }"#), plan)
        XCTAssertEqual(unnamed.days[0].name, plan.days[0].name)
        XCTAssertEqual(unnamed.cycle, plan.cycle)
        XCTAssertFalse(unnamed.warnings.contains { $0.code == "W_DEFAULT_NAME" })
    }

    // W20: the rotation's anchor (D37) survives an edit and a Replace. In v1.2 both dropped it,
    // so the next launch re-anchored the pattern to that day and the calendar moved.
    func testTheAnchorSurvivesEditsAndReplace() throws {
        var plan = try imported("valid/weekly-rotation.json")
        plan.cyclePosition = 1
        plan.cycleAnchor = CoreTestSupport.date(1)
        let edited = try edited(.renameExercise(day: 0, exercise: 0, name: "Bench"), plan)
        XCTAssertEqual(edited.cycleAnchor, plan.cycleAnchor)

        var library = PlanLibrary()
        library.save(plan, makeActive: true)
        library.replace(plan.id, with: try imported("valid/weekly-rotation.json"))
        XCTAssertEqual(library.plans[0].cyclePosition, 1)
        XCTAssertEqual(library.plans[0].cycleAnchor, plan.cycleAnchor)

        // A replacement that cannot carry the position over has nothing to anchor either.
        var unrelated = try imported("valid/minimal.json")
        unrelated.days[0].name = "Something else entirely"
        library.replace(plan.id, with: unrelated)
        XCTAssertNil(library.plans[0].cyclePosition)
        XCTAssertNil(library.plans[0].cycleAnchor)
    }
}
