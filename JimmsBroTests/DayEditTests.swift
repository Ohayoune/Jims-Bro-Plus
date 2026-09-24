import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// TN23–TN29 (v1.11, N4, D93, SPEC §6.66): today's exercises edited in place. The card on the
/// Change *day* picker opens the day's editor; every change is a `DayEdit` on a `Day` value; Add
/// exercise searches the names the app knows (`ExerciseNames`); Use for Wednesday reads the day
/// back through the importer and writes it as the date's own day; the ··· goes back to the day as
/// written or opens the text. Wednesday 16 September is Push, as the plan's example has it.
final class DayEditTests: XCTestCase {
    private let calendar = CoreTestSupport.utc()
    private func day(_ n: Int) -> Date { CoreTestSupport.date(n) }

    private static func exercise(_ name: String, _ sets: Int, _ min: Int, _ max: Int, _ kg: Double) -> Exercise {
        Exercise(name: name, sets: Array(repeating: SetTarget(work: .reps(.range(min: min, max: max)), weight: kg,
                                                              restSeconds: 90), count: sets))
    }

    /// The example's Push Pull Legs, anchored so that Wednesday the 16th is Push.
    private func pushPullLegs() -> Plan {
        let push = Day(name: "Push", exercises: [
            Self.exercise("Barbell Bench Press", 4, 6, 8, 80),
            Self.exercise("Overhead Press", 3, 8, 10, 40),
            Self.exercise("Incline Dumbbell Press", 3, 8, 12, 26),
            Self.exercise("Lateral Raise", 3, 12, 15, 10),
            Self.exercise("Tricep Pushdown", 3, 10, 12, 30),
            Self.exercise("Overhead Tricep Extension", 3, 10, 12, 20),
        ])
        let pull = Day(name: "Pull", exercises: [Self.exercise("Barbell Row", 4, 6, 8, 70),
                                                 Self.exercise("Hammer Curl", 3, 10, 12, 14)])
        let legs = Day(name: "Legs", exercises: [Self.exercise("Squat", 4, 5, 8, 100)])
        var plan = Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation, days: [push, pull, legs],
                        importedAt: day(1), sourceText: "",
                        cycle: [.day(0), .day(1), .day(2), .day(0), .day(1), .day(2), .rest])
        plan.cyclePosition = 0
        plan.cycleAnchor = calendar.startOfDay(for: day(16))
        return plan
    }

    private func upperLower() -> Plan {
        Plan(name: "Upper Lower", units: .kg, schedule: .rotation,
             days: [Day(name: "Upper", exercises: [Self.exercise("Pull-up", 3, 6, 10, 0),
                                                   Self.exercise("Overhead Press", 3, 8, 10, 40)]),
                    Day(name: "Lower", exercises: [Self.exercise("Romanian Deadlift", 3, 8, 10, 90)])],
             importedAt: day(1), sourceText: "", cycle: [.day(0), .day(1), .rest])
    }

    private func library() -> PlanLibrary {
        var library = PlanLibrary()
        library.calendar = calendar
        library.save(pushPullLegs(), makeActive: true)
        return library
    }

    private func wednesday(_ library: PlanLibrary) throws -> DayChoices.Exercises {
        try XCTUnwrap(library.dayChoices(for: day(16), now: day(16))?.exercises)
    }

    // TN23: every change is a DayEdit on the day; the whole sequence reads back through the
    // importer as it stands; an empty day is refused in the importer's sentence.
    func testADayEditIsMoveRemoveAddReplace() throws {
        let library = library()
        let push = pushPullLegs().days[0]
        let names = push.exercises.map(\.name)

        let moved = DayEdit.move(from: 0, to: 2).applied(to: push)
        XCTAssertEqual(moved.exercises.map(\.name),
                       [names[1], names[2], names[0], names[3], names[4], names[5]])
        let removed = DayEdit.remove(5).applied(to: moved)
        XCTAssertEqual(removed.exercises.map(\.name), Array(moved.exercises.map(\.name).prefix(5)))

        let fly = DayEdit.exercise(named: " Cable Fly ", in: removed, settings: library.settings)
        XCTAssertEqual(fly.name, "Cable Fly")
        XCTAssertEqual(fly.sets.count, 3, "the plan's default sets")
        XCTAssertEqual(fly.sets.map(\.work), Array(repeating: .reps(.range(min: 8, max: 10)), count: 3),
                       "the day's most common range, the first of a tie")
        XCTAssertEqual(fly.sets.map(\.weight), [nil, nil, nil], "no weight")
        XCTAssertEqual(fly.sets.first?.restSeconds, 90, "the day's rest")
        let added = DayEdit.add(fly).applied(to: removed)
        XCTAssertEqual(added.exercises.last?.name, "Cable Fly")
        XCTAssertEqual(added.exercises.count, 6)

        var bench = push.exercises[0]
        for index in bench.sets.indices { bench.sets[index].weight = 82.5 }
        let replaced = DayEdit.replace(0, bench).applied(to: added)
        XCTAssertEqual(replaced.exercises[0].name, "Barbell Bench Press")
        XCTAssertEqual(replaced.exercises[0].sets.map(\.weight), [82.5, 82.5, 82.5, 82.5])
        XCTAssertEqual(replaced.exercises.map(\.name),
                       ["Barbell Bench Press", "Incline Dumbbell Press", "Barbell Bench Press", "Lateral Raise",
                        "Tricep Pushdown", "Cable Fly"])

        XCTAssertEqual(DayEdit.remove(9).applied(to: push), push, "an index outside the day changes nothing")
        XCTAssertEqual(DayEdit.move(from: 0, to: 6).applied(to: push), push)

        let exercises = try wednesday(library)
        let read = exercises.checked(replaced, settings: library.settings, now: day(16))
        let back = try XCTUnwrap(read.day)
        XCTAssertTrue(read.issues.isEmpty)
        XCTAssertEqual(PlanJSON.render(day: back), PlanJSON.render(day: replaced), "the edited day round-trips")
        XCTAssertEqual(back.name, "Push")

        var empty = push
        for index in push.exercises.indices.reversed() { empty = DayEdit.remove(index).applied(to: empty) }
        XCTAssertTrue(empty.exercises.isEmpty)
        let refused = exercises.checked(empty, settings: library.settings, now: day(16))
        XCTAssertNil(refused.day)
        let importer = PlanImport.run(#"{"name": "P", "days": [{"name": "Push", "exercises": []}]}"#)
            .issues.filter { $0.severity == .error }
        XCTAssertFalse(importer.isEmpty)
        XCTAssertEqual(refused.issues.map(\.code), importer.map(\.code), "the importer's refusal")
        XCTAssertEqual(refused.issues.map(\.message), importer.map(\.message), "in the importer's sentence")
        XCTAssertNil(exercises.used(empty, settings: library.settings, now: day(16)).slot)
    }

    // TN24: the names the app knows — this plan's, the other plans', History's — each once, with
    // where it was found, filtered by a case-insensitive contains; a name typed that matches
    // nothing is added as typed.
    func testExerciseNamesAreThePlansThenHistory() throws {
        var library = library()
        library.save(upperLower(), makeActive: false)
        var session = try XCTUnwrap(Session.start(plan: library.plans[1], dayIndex: 0, now: day(10)))
        session.exercises[0].name = "Cable Fly"
        session.exercises[1].name = "barbell bench press"
        session.endedAt = day(10)
        library.sessions = [session]

        let all = library.exerciseNames(matching: "")
        XCTAssertEqual(all.map(\.name), [
            "Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise", "Tricep Pushdown",
            "Overhead Tricep Extension", "Barbell Row", "Hammer Curl", "Squat",
            "Pull-up", "Romanian Deadlift",
            "Cable Fly",
        ])
        XCTAssertEqual(Set(all.map { normalized($0.name) }).count, all.count, "each once")
        XCTAssertEqual(all.first?.source, "Push Pull Legs")
        XCTAssertEqual(all.first { $0.name == "Pull-up" }?.source, "Upper Lower")
        XCTAssertEqual(all.first { $0.name == "Overhead Press" }?.source, "Push Pull Legs", "kept where first found")
        XCTAssertEqual(all.last, ExerciseNames.Name(name: "Cable Fly", source: "History"))

        XCTAssertEqual(library.exerciseNames(matching: "fly").map(\.name), ["Cable Fly"])
        XCTAssertEqual(library.exerciseNames(matching: " PRESS ").map(\.name),
                       ["Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press"])

        library.activePlanId = library.plans[1].id
        XCTAssertEqual(library.exerciseNames(matching: "").first?.source, "Upper Lower", "the day's plan first")

        XCTAssertNil(ExerciseNames.typed("cable fly", known: library.exerciseNames(matching: "cable fly")))
        XCTAssertNil(ExerciseNames.typed("  ", known: []))
        XCTAssertEqual(ExerciseNames.typed(" Cable Flye ", known: library.exerciseNames(matching: "Cable Flye")),
                       "Cable Flye")
        XCTAssertEqual(ChangeDayText.addTyped("Cable Flye"), "Add “Cable Flye”")
        XCTAssertEqual(ExerciseNames.prompt, "Find an exercise")
    }

    // TN25: the card opens the editor on the date's own day when there is one, and on the day the
    // date is now otherwise (extends TP38).
    func testTheCardOpensTheEditorOnTheDateOwnDayOrItsDay() throws {
        var library = library()
        let plan = try XCTUnwrap(library.activePlan)
        let push = try wednesday(library)
        XCTAssertEqual(push.day, plan.days[0])
        XCTAssertEqual(push.title, "Change Push")
        XCTAssertEqual(push.face, DayChoices.Face(name: "Push", colour: .green, outlined: false))
        XCTAssertEqual(push.date, "Wednesday 16 September")
        XCTAssertEqual(push.use, "Use for Today")
        XCTAssertEqual(push.rows, DayChoices.rows(plan.days[0]))
        XCTAssertEqual(push.rows.first, HomeStart.PreviewRow(name: "Barbell Bench Press", sets: 4))
        XCTAssertNil(push.back, "nothing to go back from")
        XCTAssertEqual(try XCTUnwrap(library.dayChoices(for: day(16), now: day(14))?.exercises).use,
                       "Use for Wednesday")

        library.choose(.day(name: "Pull"), for: day(16), now: day(16))
        XCTAssertEqual(try wednesday(library).day, plan.days[1], "a swapped date opens on the day it is now")

        let own = DayEdit.remove(0).applied(to: plan.days[0])
        library.choose(.own(own), for: day(16), now: day(16))
        let reopened = try wednesday(library)
        XCTAssertEqual(reopened.day, own, "the date's own day")
        XCTAssertEqual(reopened.face, DayChoices.Face(name: "Push", colour: nil, outlined: true))
        XCTAssertFalse(reopened.isEdited(own))

        XCTAssertNil(library.dayChoices(for: day(22), now: day(16))?.exercises, "a rest date has no card")
    }

    // TN26: Use for Wednesday writes `.own(day)` named Push, the plan untouched, and History
    // colours its workout as Push (extends TP38, TQ28).
    func testUseForWednesdayWritesTheDateOwnDay() throws {
        var library = library()
        let plan = try XCTUnwrap(library.activePlan)
        let exercises = try wednesday(library)
        XCTAssertFalse(exercises.isEdited(exercises.day), "Use waits for an edit")

        var edited = DayEdit.remove(5).applied(to: exercises.day)
        edited = DayEdit.add(DayEdit.exercise(named: "Cable Fly", in: edited, settings: library.settings))
            .applied(to: edited)
        XCTAssertTrue(exercises.isEdited(edited))
        let used = exercises.used(edited, settings: library.settings, now: day(16))
        XCTAssertTrue(used.issues.isEmpty)
        let slot = try XCTUnwrap(used.slot)
        guard case let .own(written) = slot else { return XCTFail("an own day, not \(slot)") }
        XCTAssertEqual(written.name, "Push", "named as it was")
        XCTAssertEqual(written.exercises.map(\.name).last, "Cable Fly")

        library.choose(slot, for: day(16), now: day(16))
        let swap = try XCTUnwrap(PlanSchedule.swap(plan, on: day(16), swaps: library.swaps, calendar: calendar))
        XCTAssertEqual(swap.original, .day(name: "Push"))
        XCTAssertEqual(swap.replacement, .own(written))
        XCTAssertEqual(library.activePlan, plan, "the plan does not change")

        var session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: day(16)))
        session.dayName = written.name
        XCTAssertEqual(DayColour.of(session: session, plans: library.plans), .green, "History colours by name")
    }

    // TN27: Back to Push as written removes the date's own day — the pattern's own day chosen,
    // the swap's delete path (extends TQ26).
    func testBackToPushAsWrittenDeletesTheOwnDay() throws {
        var library = library()
        let plan = try XCTUnwrap(library.activePlan)
        let own = DayEdit.remove(0).applied(to: plan.days[0])
        library.choose(.own(own), for: day(16), now: day(16))
        XCTAssertEqual(library.swaps.count, 1)

        let back = try XCTUnwrap(try wednesday(library).back)
        XCTAssertEqual(back.title, "Back to Push as written")
        // TF2 (F2): it asks first, since it discards what was written for the date.
        XCTAssertEqual(back.question, "Discard Wednesday's exercises?")
        XCTAssertEqual(back.message, "Wednesday goes back to Push as written.")
        XCTAssertEqual(back.slot, .day(name: "Push"))
        library.choose(back.slot, for: day(16), now: day(16))
        XCTAssertTrue(library.swaps.isEmpty, "the own day is gone")
        XCTAssertEqual(try wednesday(library).day, plan.days[0])
        XCTAssertNil(try wednesday(library).back)
        XCTAssertEqual(library.activePlan, plan)
    }

    // TN28: Edit the text opens the sheet on the day as edited so far, and its Save puts the
    // text's day back in the editor, writing nothing.
    func testEditTheTextOpensOnTheEditedDayAndReturnsTheTextDay() throws {
        let library = library()
        let exercises = try wednesday(library)
        let edited = DayEdit.move(from: 5, to: 0).applied(to: exercises.day)

        let point = exercises.textPoint(edited)
        XCTAssertEqual(point.kind, .ownDay)
        XCTAssertEqual(point.template, PlanJSON.render(day: edited), "as edited so far")
        XCTAssertEqual(point.title, exercises.point.title, "the sheet as D77 left it")
        XCTAssertEqual(point.place, exercises.point.place)
        XCTAssertEqual(point.saveTitle, "Replace Push", "Save says its effect: the editor's day, not the date")
        XCTAssertEqual(ChangeDayText.editText, "Edit the text")

        let text = point.template.replacingOccurrences(of: "\"Overhead Tricep Extension\"", with: "\"Skull Crusher\"")
        let read = exercises.checked(text, settings: library.settings, now: day(16))
        let textDay = try XCTUnwrap(read.day)
        XCTAssertTrue(read.issues.isEmpty)
        XCTAssertEqual(textDay.exercises.first?.name, "Skull Crusher")
        XCTAssertTrue(exercises.isEdited(textDay))
        XCTAssertTrue(library.swaps.isEmpty, "the text's Save writes nothing")

        let bad = exercises.checked(text.replacingOccurrences(of: "\"Skull Crusher\"", with: "\"\""),
                                    settings: library.settings, now: day(16))
        XCTAssertNil(bad.day)
        XCTAssertFalse(bad.issues.isEmpty, "refused as the sheet refuses")
    }

    // TN29 (pin): the picker's card opens the editor, not the text sheet.
    func testTheCardNoLongerPresentsTheSheetDirectly() throws {
        guard let view = FixtureLoader.doc("JimmsBro/Features/Home/ChangeDayView.swift"),
              let editor = FixtureLoader.doc("JimmsBro/Features/Home/DayEditorView.swift") else {
            throw XCTSkip("the checkout is out of reach on this route")
        }
        XCTAssertFalse(view.contains("writing = exercises.point"), "the card opens the editor")
        XCTAssertTrue(view.contains("DayEditorView("))
        XCTAssertTrue(editor.contains("text = exercises.textPoint(day)") && editor.contains("JSONFragmentSheet(point: text)"),
                      "the text is the editor's ···")
        XCTAssertTrue(editor.contains(".onMove") && editor.contains(".onDelete"))
    }
}
