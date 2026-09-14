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
                       "E_MISSING_NAME", "a blank name is refused with a sentence, not saved")
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

    // MARK: - Q5 (v1.9): the JSON sheet, redone (D77)

    /// The example v1.9's plan speaks in: Push Pull Legs, Bench Press the third of Push's five.
    private func pushPullLegs() throws -> Plan {
        let text = """
        { "schemaVersion": 1, "name": "Push Pull Legs", "units": "kg", "schedule": "rotation",
          "cycle": ["Push", "Pull", "Legs", "rest", "Push", "Pull", "Legs"],
          "days": [
            { "name": "Push", "exercises": [
              { "name": "Overhead Press", "sets": 3, "reps": 8, "weight": 40 },
              { "name": "Incline Press", "sets": 3, "reps": 11, "weight": 50 },
              { "name": "Bench Press", "sets": 3, "reps": "6-8", "weight": 80 },
              { "name": "Dip", "sets": 3, "reps": 10 },
              { "name": "Lateral Raise", "sets": 3, "reps": 15, "weight": 8 } ] },
            { "name": "Pull", "exercises": [ { "name": "Row", "sets": 3, "reps": 8, "weight": 60 } ] },
            { "name": "Legs", "exercises": [ { "name": "Squat", "sets": 3, "reps": 5, "weight": 100 } ] }
          ] }
        """
        let result = PlanImport.run(text, settings: settings, now: now)
        return try XCTUnwrap(result.plan, "\(result.issues)")
    }

    private func wednesday(_ plan: Plan, own: Day? = nil) -> JSONPoint {
        JSONPoint.ownDay(when: "Wednesday", date: "Wednesday 16 September", name: "Wednesday's own day",
                         plan: plan, own: own)
    }

    // TQ30: every point opens on text the pipeline takes as its own kind — an edit on the part
    // itself, which saved changes nothing; an addition on an example that saves as it stands, on
    // a rotation and on a weekday plan; and a day just for a date, named by the date.
    func testEveryPointOpensOnTextItCanSave() throws {
        for plan in [try pushPullLegs(), try imported("valid/weekly-weekday.json")] {
            let rendered = PlanJSON.render(plan)
            let exercise = try XCTUnwrap(JSONPoint.exercise(plan, day: 0, exercise: 0))
            XCTAssertEqual(PlanJSON.render(try edited(XCTUnwrap(exercise.operation(exercise.template)), plan)), rendered)
            let day = try XCTUnwrap(JSONPoint.day(plan, day: 0))
            XCTAssertEqual(PlanJSON.render(try edited(XCTUnwrap(day.operation(day.template)), plan)), rendered)

            let exercises = try XCTUnwrap(JSONPoint.addExercises(plan, day: 0))
            let added = try edited(XCTUnwrap(exercises.operation(exercises.template)), plan)
            XCTAssertEqual(added.days[0].exercises.map(\.name), plan.days[0].exercises.map(\.name) + ["Push-up"])
            XCTAssertEqual(added.days[0].exercises.last?.sets.map(\.work), Array(repeating: .reps(.range(min: 8, max: 12)), count: 3))

            let days = JSONPoint.addDays(plan)
            let more = try edited(XCTUnwrap(days.operation(days.template)), plan)
            XCTAssertEqual(more.days.map(\.name), plan.days.map(\.name) + ["Day \(plan.days.count + 1)"])
            XCTAssertEqual(more.days.last?.exercises.map(\.name), ["Push-up"])
            if plan.schedule == .weekday {
                XCTAssertNotNil(more.days.last?.weekday, "a weekday plan's example takes a free weekday")
            }
        }

        let plan = try pushPullLegs()
        let own = wednesday(plan)
        XCTAssertNil(own.operation(own.template), "a day just for a date is not the plan's")
        let read = PlanLibrary.ownDay(own.template, named: "Wednesday's own day", units: plan.units,
                                      settings: settings, now: now)
        XCTAssertEqual(read.day?.name, "Wednesday's own day")
        XCTAssertEqual(read.day?.exercises.map(\.name), ["Push-up"])
        XCTAssertTrue(read.issues.isEmpty, "\(read.issues)")
        let legs = plan.days[2]
        XCTAssertEqual(wednesday(plan, own: legs).template, PlanJSON.render(day: legs), "the date's own day opens on itself")
    }

    // TQ31: the five points on the example plan — what the JSON is, where it lands and for how
    // long, and a Save that says its effect.
    func testEachPointSaysWhatItIsWhereItLandsAndWhatSaveDoes() throws {
        let plan = try pushPullLegs()
        let bench = try XCTUnwrap(JSONPoint.exercise(plan, day: 0, exercise: 2))
        XCTAssertEqual([bench.title, bench.place, bench.saveTitle],
                       ["One exercise", "Bench Press, exercise 3 of 5 in Push", "Replace Bench Press"])
        let push = try XCTUnwrap(JSONPoint.day(plan, day: 0))
        XCTAssertEqual([push.title, push.place, push.saveTitle],
                       ["One day", "Push, day 1 of 3 in Push Pull Legs", "Replace Push"])
        let toPush = try XCTUnwrap(JSONPoint.addExercises(plan, day: 0))
        XCTAssertEqual([toPush.title, toPush.place, toPush.saveTitle],
                       ["Exercises to add", "Added at the end of Push", "Add to Push"])
        let toPlan = JSONPoint.addDays(plan)
        XCTAssertEqual([toPlan.title, toPlan.place, toPlan.saveTitle],
                       ["A day to add", "Added at the end of Push Pull Legs", "Add to Push Pull Legs"])
        let own = wednesday(plan)
        XCTAssertEqual([own.title, own.place, own.saveTitle],
                       ["A day just for Wednesday", "For Wednesday 16 September. Not saved to Push Pull Legs.", "Use for Wednesday"])

        // Pre-filled: an edit on the part's own text, an addition on the example.
        XCTAssertEqual(bench.template, PlanJSON.render(exercise: plan.days[0].exercises[2]))
        XCTAssertEqual(push.template, PlanJSON.render(day: plan.days[0]))
        XCTAssertEqual(toPush.template, JSONPoint.exampleExercise)
        XCTAssertTrue(toPlan.template.contains("\"name\": \"Day 4\""))
        XCTAssertFalse(toPlan.template.contains("weekday"), "a rotation's new day has no weekday")
        XCTAssertTrue(own.template.contains("\"name\": \"\""), "left nameless, it takes the date's name")

        // Save is the operation D43 built, on the right part.
        XCTAssertEqual(bench.operation("x"), .replaceExerciseJSON(day: 0, exercise: 2, text: "x"))
        XCTAssertEqual(push.operation("x"), .replaceDayJSON(day: 0, text: "x"))
        XCTAssertEqual(toPush.operation("x"), .insertExercisesJSON(day: 0, at: nil, text: "x"))
        XCTAssertEqual(toPlan.operation("x"), .insertDaysJSON(text: "x"))
        XCTAssertNil(JSONPoint.exercise(plan, day: 0, exercise: 5))
        XCTAssertNil(JSONPoint.day(plan, day: 3))
        XCTAssertNil(JSONPoint.addExercises(plan, day: 3))
    }

    // TQ32: the error at its line — the line its path names, or nothing, never the wrong one.
    func testTheErrorIsMarkedAtItsLineOrNowhere() throws {
        let plan = try pushPullLegs()

        // A rendered plan: the pipeline's own path finds the second exercise's first reps.
        let whole = PlanJSON.render(plan)
        let lines = whole.components(separatedBy: "\n")
        let reps = try XCTUnwrap(JSONLocator.line(of: "days[0].exercises[1].sets[0].reps", in: whole))
        XCTAssertEqual(lines[reps - 1].trimmed, "\"reps\": 11,")

        let written = """
        {
          "name": "Bench Press",
          "sets": [
            { "reps": 8, "weight": 80 },
            {
              "reps":
                "eight"
            }
          ]
        }
        """
        XCTAssertEqual(JSONLocator.line(of: "name", in: written), 2)
        XCTAssertEqual(JSONLocator.line(of: "sets[0].weight", in: written), 4)
        XCTAssertEqual(JSONLocator.line(of: "sets[1]", in: written), 5, "an element's first line")
        XCTAssertEqual(JSONLocator.line(of: "sets[1].reps", in: written), 6, "a member's key, not its value")
        XCTAssertEqual(JSONLocator.line(of: "name", in: "{\r\n  \"name\": \"A\"\r\n}"), 2)
        XCTAssertEqual(JSONLocator.range(ofLine: 2, in: "a\nbc\nd").map { String("a\nbc\nd"[$0]) }, "bc")

        // Nothing rather than the wrong line.
        XCTAssertNil(JSONLocator.line(of: "", in: written), "the whole text is no one line")
        XCTAssertNil(JSONLocator.line(of: "sets[0].restSeconds", in: written), "a path into a missing key")
        XCTAssertNil(JSONLocator.line(of: "sets[2]", in: written))
        XCTAssertNil(JSONLocator.line(of: "name.first", in: written))
        XCTAssertNil(JSONLocator.line(of: "sets[0", in: written))
        XCTAssertNil(JSONLocator.line(of: "name", in: "Here it is:\n```json\n" + written + "\n```\nEnjoy."),
                     "a fenced fragment with prose around it")
        XCTAssertNil(JSONLocator.line(of: "name", in: "{\n  \"name\": \"A\",\n}"), "a trailing comma")
        XCTAssertNil(JSONLocator.line(of: "name", in: "{\n  \u{201C}name\u{201D}: \"A\"\n}"), "curly quotes")
        XCTAssertNil(JSONLocator.line(of: "name", in: "{\n  \"name\": \"A\",\n  \"name\": \"B\"\n}"), "a key written twice")

        // Through a point: the pipeline's path is the plan's, the line is the text's, and the
        // sentence beneath the line leaves out the place, because the line is the place.
        let pull = try XCTUnwrap(JSONPoint.day(plan, day: 1))
        let badDay = """
        {
          "name": "Pull",
          "exercises": [
            { "name": "Row", "sets": 3, "reps": 8 },
            { "name": "Curl", "sets": [ { "reps": "lots" } ] }
          ]
        }
        """
        let refused = apply(try XCTUnwrap(pull.operation(badDay)), plan).errors
        XCTAssertEqual(refused.first?.path, "days[1].exercises[1].sets[0].reps")
        let found = pull.marks(for: refused, in: badDay)
        XCTAssertEqual(found.marked.map(\.line), [5])
        XCTAssertEqual(found.marked.first?.sentences.first, "The reps need to be a number, a range like 8-12, or AMRAP.")
        XCTAssertEqual(found.unmarked, [])

        let bench = try XCTUnwrap(JSONPoint.exercise(plan, day: 0, exercise: 2))
        let badBench = "{\n  \"name\": \"Bench Press\",\n  \"sets\": 3,\n  \"reps\": \"6-8\",\n  \"weight\": \"heavy\"\n}"
        let weightErrors = apply(try XCTUnwrap(bench.operation(badBench)), plan).errors
        XCTAssertEqual(weightErrors.first?.path, "days[0].exercises[2].weight")
        XCTAssertEqual(bench.marks(for: weightErrors, in: badBench).marked.map(\.line), [5])

        let toPull = try XCTUnwrap(JSONPoint.addExercises(plan, day: 1))
        let two = "[\n  { \"name\": \"Curl\", \"sets\": 3, \"reps\": 12 },\n  { \"name\": \"Shrug\", \"sets\": 3, \"reps\": \"x\" }\n]"
        let addErrors = apply(try XCTUnwrap(toPull.operation(two)), plan).errors
        XCTAssertEqual(addErrors.first?.path, "days[1].exercises[2].reps")
        XCTAssertEqual(toPull.marks(for: addErrors, in: two).marked.map(\.line), [3],
                       "the second of two, found by its place in the text")

        let wrapped = "{ \"name\": \"Anything\", \"days\": [\n  { \"name\": \"Pull\", \"exercises\": [\n    { \"name\": \"Row\", \"sets\": 3, \"reps\": \"x\" } ] } ] }"
        let wrappedErrors = apply(try XCTUnwrap(pull.operation(wrapped)), plan).errors
        XCTAssertEqual(pull.marks(for: wrappedErrors, in: wrapped).marked.map(\.line), [3],
                       "a day pasted inside a plan is found where it was pasted")

        let own = wednesday(plan)
        let ownText = "{\n  \"exercises\": [\n    { \"name\": \"Row\", \"sets\": 3, \"reps\": \"x\" }\n  ]\n}"
        let ownErrors = PlanLibrary.ownDay(ownText, named: "Wednesday's own day", units: .kg,
                                           settings: settings, now: now).issues
        XCTAssertEqual(ownErrors.first?.path, "exercises[0].reps")
        XCTAssertEqual(own.marks(for: ownErrors, in: ownText).marked.map(\.line), [3])

        // Under the box, with the place: prose around the text, an error about the paste as a
        // whole, a day gathered here from loose exercises, and another part of the plan.
        let prose = pull.marks(for: apply(try XCTUnwrap(pull.operation("Here is the day:\n" + badDay)), plan).errors,
                               in: "Here is the day:\n" + badDay)
        XCTAssertEqual(prose.marked, [])
        XCTAssertEqual(prose.unmarked.first, "Day 2, exercise 2, set 1: the reps need to be a number, a range like 8-12, or AMRAP.")
        let twoForOne = "[\n  { \"name\": \"A\", \"sets\": 3, \"reps\": 5 },\n  { \"name\": \"B\", \"sets\": 3, \"reps\": 5 }\n]"
        let editErrors = apply(try XCTUnwrap(bench.operation(twoForOne)), plan).errors
        XCTAssertEqual(editErrors.first?.code, "E_EDIT_INVALID")
        XCTAssertEqual(bench.marks(for: editErrors, in: twoForOne).marked, [], "two exercises where one goes")
        let addDay = JSONPoint.addDays(plan)
        let loose = "[\n  { \"name\": \"Curl\", \"sets\": 3, \"reps\": \"x\" }\n]"
        let looseErrors = apply(try XCTUnwrap(addDay.operation(loose)), plan).errors
        XCTAssertFalse(looseErrors.isEmpty)
        XCTAssertEqual(addDay.marks(for: looseErrors, in: loose).marked, [], "a day made here is no line of the text")
        let elsewhere = Issue(severity: .error, code: "E_CYCLE_UNKNOWN_DAY", path: "cycle[2]", message: "Unknown day.")
        XCTAssertEqual(addDay.marks(for: [elsewhere], in: loose).marked, [])
        XCTAssertEqual(addDay.marks(for: [elsewhere], in: loose).unmarked.count, 1)
    }
}
