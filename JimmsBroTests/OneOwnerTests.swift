import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// v1.12 (D96): one owner for each piece of logic. Where two copies disagreed, these pin the side
/// that won, so a copy that grows back and drifts shows up here.
final class OneOwnerTests: XCTestCase {
    private let settings = Settings(warmUpSeconds: 0, transitionRestSeconds: 0)

    private func step(_ fields: String) -> ProgressionImport.Result {
        let reply = #"{ "steps": 1, "exercises": [ { "name": "Bench Press", "steps": [ "# + fields + #" ] } ] }"#
        return ProgressionImport.run(reply, plan: CoreTestSupport.plan(), settings: settings,
                                     now: CoreTestSupport.now, mode: .calendar)
    }

    private func planReps(_ reps: String) -> ImportResult {
        PlanImport.run(CoreTestSupport.planJSON(exercise: #"{ "name": "Bench Press", "sets": 1, "reps": "\#(reps)" }"#),
                       settings: settings, now: CoreTestSupport.now)
    }

    // TL1: reps mean the same in a plan, a progression step and the exercise sheet — 1 to 1000,
    // the same words and separators. A step said "reps": 0 was accepted while a plan refused it.
    func testRepsReadTheSameEverywhere() {
        XCTAssertEqual(planReps("0").errors.map(\.code), ["E_REPS_INVALID"])
        XCTAssertEqual(step(#"{ "reps": 0 }"#).errors.map(\.code), ["E_REPS_INVALID"])
        XCTAssertNil(PlanEdit.parseWork("0"))

        XCTAssertTrue(planReps("1000").errors.isEmpty)
        XCTAssertNotNil(step(#"{ "reps": 1000 }"#).progression)
        XCTAssertEqual(PlanEdit.parseWork("1000"), .reps(.fixed(1000)))

        for text in ["8 to 12", "8/12", "8—12", "8-12 reps"] {
            XCTAssertEqual(planReps(text).plan?.days[0].exercises[0].sets[0].work, .reps(.range(min: 8, max: 12)), text)
            XCTAssertEqual(step(#"{ "reps": ""# + text + #"" }"#).progression?.entries.first?.weeks.first?.work,
                           .reps(.range(min: 8, max: 12)), text)
            XCTAssertEqual(PlanEdit.parseWork(text), .reps(.range(min: 8, max: 12)), text)
        }
    }

    // TL1: a range written high to low is swapped with a warning wherever there is a warning to
    // give, and refused in the sheet, which has none.
    func testABackwardsRangeIsSwappedOrRefused() {
        XCTAssertEqual(planReps("12-8").plan?.warnings.map(\.code), ["W_RANGE_SWAPPED"])
        let swapped = step(#"{ "reps": "12-8" }"#)
        XCTAssertEqual(swapped.issues.map(\.code), ["W_RANGE_SWAPPED"])
        XCTAssertEqual(swapped.progression?.entries.first?.weeks.first?.work, .reps(.range(min: 8, max: 12)))
        XCTAssertNil(PlanEdit.parseWork("12-8"))
        XCTAssertNil(PlanEdit.parseRange("12-8"))
    }

    // TL2: the sheet's range field reads a range as a plan's repRange is read, so a plan whose
    // repRange is 8–8 opens in the sheet and saves untouched.
    func testTheRangeFieldReadsARepRange() throws {
        XCTAssertEqual(PlanEdit.parseRange("8"), RepRange(min: 8, max: 8))
        XCTAssertEqual(PlanEdit.parseRange("8-8"), RepRange(min: 8, max: 8))
        XCTAssertEqual(PlanEdit.parseRange("8 to 12"), RepRange(min: 8, max: 12))
        var plan = CoreTestSupport.plan()
        plan.days[0].exercises[0].repRange = RepRange(min: 8, max: 8)
        let fields = PlanEdit.ExerciseFields(plan.days[0].exercises[0])
        XCTAssertTrue(fields.canSave)
        XCTAssertTrue(fields.changes(from: plan.days[0].exercises[0]).isEmpty)
    }

    // TL3: a progression step's weight reads as a plan's does — a stray unit is named, "+10" is
    // ten — and keeps its own "same", and is snapped rather than rounded to a tenth.
    func testAStepWeightReadsAsAPlanWeight() {
        let pounds = step(#"{ "weight": "60 lb" }"#)
        XCTAssertEqual(pounds.issues.map(\.code), ["W_WEIGHT_UNIT_IGNORED"])
        XCTAssertEqual(pounds.progression?.entries.first?.weeks.first?.weight, 60)
        XCTAssertEqual(step(#"{ "weight": "+10" }"#).progression?.entries.first?.weeks.first?.weight, 10)
        XCTAssertEqual(step(#"{ "weight": "same" }"#).progression?.entries.first?.weeks.first?.weight, nil)
        XCTAssertEqual(step(#"{ "weight": 20000 }"#).errors.map(\.code), ["E_WEIGHT_INVALID"])
        let odd = step(#"{ "weight": 62.55 }"#)
        XCTAssertEqual(odd.issues.map(\.code), ["W_PROGRESSION_ROUNDED"], "snapped once, not rounded first")
    }

    // TL4: every piece of JSON the app writes by hand quotes its text with the one escaper, so
    // a name with a quote in it still parses. `exampleDay` wrote the name in raw.
    func testHandWrittenJSONQuotesItsText() throws {
        let name = #"Push "heavy" \ day"#
        let day = PlanImport.decode(JSONPoint.exampleDay(name: name)).value
        XCTAssertEqual(day?["name"]?.string, name)

        var plan = CoreTestSupport.plan()
        plan.days[0].name = name
        plan.days[0].exercises[0].name = #"Bench "flat""#
        let reply = PlanImport.decode(ProgressionScreen.exampleReply(plan: plan, steps: 2)).value
        XCTAssertEqual(reply?["exercises"]?.array?.first?["day"]?.string, name)
        XCTAssertEqual(reply?["exercises"]?.array?.first?["name"]?.string, #"Bench "flat""#)
    }

    // TL5: E_NOT_JSON's two readings — a plan in words, or a reply cut short — are one
    // predicate each, read by the refusal and by the friendly text alike.
    func testNotJSONHasTwoReadings() throws {
        let words = try XCTUnwrap(PlanImport.run("Monday: bench 3x8, rows 3x10").errors.first)
        let cut = try XCTUnwrap(PlanImport.run(#"{ "name": "Push", "days": ["#).errors.first)
        XCTAssertTrue(words.isPlanInWords); XCTAssertFalse(words.isCutShort)
        XCTAssertTrue(cut.isCutShort); XCTAssertFalse(cut.isPlanInWords)
        XCTAssertEqual(ImportTrip.Refusal.of([words]).sends, .prompt)
        XCTAssertTrue(ImportTrip.Refusal.of([cut]).offersDayByDay)
        XCTAssertTrue(IssueText.friendly(words).contains("plan in words"))
        XCTAssertTrue(IssueText.friendly(cut).contains("cut off"))
    }

    // TL6: the importer and the JSON sheet read JSON with one grammar, so a text the importer
    // refuses has no line to mark and a text it reads has. They were two parsers.
    func testTheImporterAndTheSheetReadOneGrammar() {
        let strict = [#"{ "a": 1 }"#, #"{ "a": [-0.5e+3, true, null, "é\n"] }"#, "{\r\n\t\"a\": {}\r\n}"]
        let loose = [#"{ "a": 1, }"#, #"{ "a": [1, 2,] }"#, #"{ "a": 01 }"#, #"{ "a": .5 }"#, #"{ "a": NaN }"#,
                     #"{ 'a': 1 }"#, #"{ a: 1 }"#, #"{ "a": 1 } // why"#, #"{ "a": "\x" }"#, #"{ "a": "\u12" }"#,
                     "{ \"a\": \"tab\there\" }", #"{ "a": tru }"#]
        for text in strict {
            XCTAssertNotNil(try? JSONGrammar.parse(text), text)
            XCTAssertNotNil(PlanImport.decode(text).value, text)
            XCTAssertNotNil(JSONLocator.line(of: "a", in: text), text)
        }
        for text in loose {
            XCTAssertNil(try? JSONGrammar.parse(text), text)
            XCTAssertEqual(PlanImport.decode(text).issues.map(\.code), ["E_NOT_JSON"], text)
            XCTAssertNil(JSONLocator.line(of: "a", in: text), text)
        }
    }

    // TL7: a refusal says where the grammar broke, and E_NOT_JSON quotes it as it always has —
    // its column counting bytes.
    func testARefusalSaysWhereTheGrammarBroke() {
        let comma = "{\n  \"a\": 1,\n}"
        XCTAssertThrowsError(try JSONGrammar.parse(comma)) { error in
            XCTAssertEqual(error as? JSONGrammar.Failure,
                           JSONGrammar.Failure(message: "Expected a double-quoted string", offset: 12, line: 3, column: 1))
        }
        XCTAssertEqual(PlanImport.decode(comma).issues.first?.message,
                       "This isn't valid JSON: Expected a double-quoted string at line 3, column 1. "
                       + "Ask the chatbot for strict JSON, or use Copy fix-it prompt.")
        XCTAssertThrowsError(try JSONGrammar.parse(#"{"days":["#)) { error in
            XCTAssertEqual((error as? JSONGrammar.Failure)?.localizedDescription, "Unexpected end of file at line 1, column 10.")
        }
        XCTAssertThrowsError(try JSONGrammar.parse(#"{"é": 1,}"#)) { error in
            XCTAssertEqual((error as? JSONGrammar.Failure)?.column, 10, "é is two bytes")
        }
    }

    // TL8: the cut out of a reply reads code points, as the grammar and the oracle do. It read
    // grapheme clusters, so a brace with a combining mark after it was no brace, and the JSON
    // before it ran on to the end of the paste.
    func testTheCutReadsCodePointsAsTheOracleDoes() {
        let cut = PlanImport.extract("Here it is: {\"a\": 1}\u{301} and that's all")
        XCTAssertEqual(cut.value, "{\"a\": 1}")
        XCTAssertEqual(cut.issues.map(\.code), ["W_SURROUNDING_TEXT"])
    }

    // MARK: - L3: plans and the schedule

    private func date(_ day: Int) -> Date { CoreTestSupport.date(day) }

    /// Push · Pull · Push · Legs, on its second Push since the 10th, with a progression attached.
    private func pushTwice() -> Plan {
        let exercises = CoreTestSupport.plan().days[0].exercises
        var plan = Plan(name: "PPL", units: .kg, schedule: .rotation,
                        days: ["Push", "Pull", "Legs"].map { Day(name: $0, exercises: exercises) },
                        importedAt: date(1), sourceText: "", cycle: [.day(0), .day(1), .day(0), .day(2)])
        plan.cyclePosition = 2
        plan.cycleAnchor = CoreTestSupport.utc().startOfDay(for: date(10))
        plan.progression = Progression(startDate: date(10), weeks: 4)
        return plan
    }

    // TL9: a plan hands on its identity one way. A name-conflict Replace kept the place by the
    // day's first occurrence and dropped its anchor, where an edit and Apply kept both; an edit
    // kept the place by index, where Apply followed the day's name.
    func testAReplacementIsCarriedOneWay() throws {
        let plan = pushTwice()
        var library = PlanLibrary()
        library.save(plan, makeActive: true)
        var fresh = plan
        fresh.id = UUID(); fresh.importedAt = date(12); fresh.sourceText = "as pasted"
        fresh.cyclePosition = nil; fresh.cycleAnchor = nil; fresh.progression = nil
        library.save(fresh, conflict: .replace)
        let replaced = library.plans[0]
        XCTAssertEqual(replaced.id, plan.id)
        XCTAssertEqual(replaced.cyclePosition, 2, "the second Push keeps its own place; its first moved the calendar")
        XCTAssertEqual(replaced.cycleAnchor, plan.cycleAnchor, "the anchor goes with its place")
        XCTAssertEqual(replaced.importedAt, date(12), "a new plan has its own import date")
        XCTAssertEqual(replaced.sourceText, "as pasted")
        XCTAssertNil(replaced.progression, "a new plan starts without one (§6.21)")

        // An edit, a JSON edit and Apply keep all of it, and the place follows a renamed day.
        var chest = plan.days[0]
        chest.name = "Chest"
        let edits = [PlanEdit.apply(.renameDay(day: 0, name: "Chest"), to: plan, settings: settings, now: CoreTestSupport.now).plan,
                     PlanEdit.apply(.replaceDayJSON(day: 0, text: PlanJSON.render(day: chest)), to: plan,
                                    settings: settings, now: CoreTestSupport.now).plan,
                     plan.carried(into: fresh, as: .edit)]
        for edited in edits {
            let edited = try XCTUnwrap(edited)
            XCTAssertEqual(edited.id, plan.id)
            XCTAssertEqual(edited.cyclePosition, 2)
            XCTAssertEqual(edited.cycleAnchor, plan.cycleAnchor)
            XCTAssertEqual(edited.importedAt, plan.importedAt)
            XCTAssertEqual(edited.progression, plan.progression)
            XCTAssertEqual(edited.sourceText, PlanJSON.render(edited), "an edit's text is the canonical rendering")
        }
        // Where the day has gone, so has the place, and its anchor with it.
        var noPush = fresh
        noPush.cycle = [.day(1), .day(2)]
        let gone = plan.carried(into: noPush, as: .edit)
        XCTAssertNil(gone.cyclePosition)
        XCTAssertNil(gone.cycleAnchor)
    }

    // TL10: the app speaks English whatever the phone's language. The missed line read the
    // calendar's weekday symbols and the Summary a formatter in the phone's locale, so a German
    // phone said "Pull was due Dienstag" and "Next: Pull, Freitag".
    func testDatesSpeakEnglishWhateverThePhonesLanguage() throws {
        var calendar = CoreTestSupport.utc()
        calendar.locale = Locale(identifier: "de_DE")
        func day(_ name: String) -> Day { Day(name: name, exercises: []) }

        // Anchored to Monday the 7th with Push done; Tuesday's Pull was not.
        var missing = Plan(name: "PPL", units: .kg, schedule: .rotation, days: [day("Push"), day("Pull"), day("Legs")],
                           importedAt: date(1), sourceText: "", cycle: [.day(0), .day(1), .day(2), .rest])
        missing.cyclePosition = 0
        missing.cycleAnchor = calendar.startOfDay(for: date(7))
        var library = PlanLibrary()
        library.calendar = calendar
        library.save(missing, makeActive: true)
        XCTAssertEqual(HomeStart.current(library: library, now: date(9), calendar: calendar).missed?.text,
                       "Pull was due Tuesday")

        // Push done on Wednesday the 9th: Pull on Friday, then Push again on the 17th.
        var summary = PlanLibrary()
        summary.calendar = calendar
        summary.save(Plan(name: "PL", units: .kg, schedule: .rotation, days: [day("Push"), day("Pull")],
                          importedAt: date(1), sourceText: "", cycle: [.day(0), .rest, .day(1), .rest]), makeActive: true)
        PlanSchedule.advance(&summary.plans[0], completedDayName: "Push", on: date(9), calendar: calendar)
        let push = try XCTUnwrap(Session.start(plan: summary.plans[0], dayIndex: 0, now: date(9)))
        XCTAssertEqual(SummaryText.next(after: push, library: summary, now: date(9), calendar: calendar), "Next: Pull, Friday")
        summary.plans[0].cycle = [.day(0)] + Array(repeating: .rest, count: 7)
        summary.plans[0].cyclePosition = 0
        XCTAssertEqual(SummaryText.next(after: push, library: summary, now: date(9), calendar: calendar), "Next: Push, on 17 Sep")

        // The picker's date line, as it always was.
        XCTAssertEqual(summary.dayChoices(for: date(16), now: date(9))?.line,
                       "For Wednesday 16 September only. The plan does not change.")
        XCTAssertEqual(WeekdayText.full(Weekday(date(13), calendar: calendar)), "Sunday")
    }

    // TL11: the swap search's horizon is the calendar's — today and 62 days (§6.12). One search
    // counted 0...62 days from where it started and the other 0..<62, so from tomorrow the card's
    // could look a day past the last one the calendar paints.
    func testTheHorizonIsTheCalendars() {
        let calendar = CoreTestSupport.utc()
        let plan = Plan(name: "A", units: .kg, schedule: .rotation, days: [Day(name: "A", exercises: [])],
                        importedAt: date(1), sourceText: "", cycle: [.day(0)])
        func looked(from start: Date) -> Int {
            var count = 0
            _ = PlanSchedule.firstDay(plan, from: start, swaps: [], today: date(1), calendar: calendar,
                                      where: { _ in count += 1; return false })
            return count
        }
        XCTAssertEqual(looked(from: date(1)), PlanSchedule.horizonDays + 1, "today and 62 days")
        XCTAssertEqual(looked(from: date(2)), PlanSchedule.horizonDays, "from tomorrow, to the same last day")
        XCTAssertEqual(PlanSchedule.firstDay(plan, from: date(2), swaps: [], today: date(1), calendar: calendar)?.date,
                       calendar.startOfDay(for: date(2)), "a day to train, by default")
    }

    // TL12: one exercise search, blind to case, accents and runs of spaces. History's Find an
    // exercise and Change exercise matched "developpe" to nothing; Add exercise matched "bench
    // press" to nothing written "Bench  Press".
    func testOneExerciseSearch() throws {
        var session = CoreTestSupport.session()
        session.endedAt = CoreTestSupport.now
        session.exercises = ["Développé couché", "Bench  Press"].map { SessionExercise(name: $0, targets: []) }
        let plan = CoreTestSupport.plan()
        for plans in [[], [plan]] {
            XCTAssertEqual(ExerciseNames.known(plans: plans, history: [session], query: "developpe").map(\.name),
                           ["Développé couché"])
            XCTAssertEqual(ExerciseNames.known(plans: plans, history: [session], query: " BENCH PRESS ").map(\.name),
                           plans.isEmpty ? ["Bench  Press"] : ["Bench Press"], "a plan's own name is found first")
        }
        XCTAssertEqual(ExerciseNames.known(plans: [], history: [session], query: "").count, 2, "History's alone")

        guard let history = FixtureLoader.doc("JimmsBro/Features/History/HistoryView.swift"),
              let change = FixtureLoader.doc("JimmsBro/Features/Workout/ChangeExerciseSheet.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        for source in [history, change] {
            XCTAssertTrue(source.contains("ExerciseNames.known(plans: [], history: model.sessions"))
        }
    }

    // TL13: a cycle is read one way — as days (`Plan.cycleDays`), in words (`cycleNames`) and as
    // squares (`CycleSquare.of`) — for the plan's JSON, the prompt, the diff, the review's squares,
    // the page's squares and rows, and the symbol. The diff wrote "?" for an entry naming a day the
    // plan no longer has, where everything else draws a rest (§6.12).
    func testACycleIsReadOneWay() {
        let plan = Plan(name: "R", units: .kg, schedule: .rotation,
                        days: [Day(name: "Push", exercises: []), Day(name: "Pull", exercises: [])],
                        importedAt: date(1), sourceText: "", cycle: [.day(0), .rest, .day(1), .day(7)])
        XCTAssertEqual(plan.cycleDays, [0, nil, 1, nil])
        XCTAssertEqual(plan.cycleNames, ["Push", nil, "Pull", nil])
        XCTAssertTrue(PlanJSON.render(plan).contains(#""cycle": ["Push", "rest", "Pull", "rest"]"#))
        XCTAssertTrue(Prompts.outlineListing(plan).contains("Repeat block: Push, rest, Pull, rest"))
        XCTAssertEqual(PlanDiff.scheduleText(plan), "Push · rest · Pull · rest")

        let squares = CycleSquare.of(plan)
        XCTAssertEqual(squares.map(\.name), ["Push", "Rest", "Pull", "Rest"])
        XCTAssertEqual(squares.map(\.dayIndex), plan.cycleDays)
        XCTAssertEqual(squares.map(\.colour), DayColour.cycle(of: plan))
        XCTAssertEqual(ImportTrip.squares(plan).map(\.dayIndex), plan.cycleDays)
        XCTAssertEqual(RepeatBlock.squares(plan, today: date(14), calendar: CoreTestSupport.utc()).map(\.dayIndex), plan.cycleDays)
        XCTAssertEqual(PlanPage.rows(plan).map(\.dayIndex), plan.cycleDays)
    }
}
