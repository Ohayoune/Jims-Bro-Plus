import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// v1.12 (D96): one owner for each piece of logic. Where two copies disagreed, these pin the side
/// that won, so a copy that grows back and drifts shows up here.
final class OneOwnerTests: XCTestCase {
    private let settings = CoreTestSupport.classic

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
        let reply = PlanImport.decode(JSONPoint.exampleProgression(plan, steps: 2)).value
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
        XCTAssertEqual(TripRefusal.of([words], way: .wholePlanOrDayByDay).sends, .prompt)
        XCTAssertTrue(TripRefusal.of([cut], way: .wholePlanOrDayByDay).offersDayByDay)
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

        let history = try FixtureLoader.requiredDoc("JimmsBro/Features/History/HistoryView.swift")
        let change = try FixtureLoader.requiredDoc("JimmsBro/Features/Workout/ChangeExerciseSheet.swift")
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

    // MARK: - L4: the session and the Workout screen

    private let now = CoreTestSupport.now

    private func engine(_ plan: Plan, walk: Int = 0) -> SessionEngine {
        CoreTestSupport.engine(plan, settings: Settings(warmUpSeconds: 0, transitionRestSeconds: walk))
    }

    // TL14: the rest after a set is the engine's (§6.3). An exercise on its own that still carries a
    // `groupRestSeconds` — left over from a superset it was taken out of — rests its own 1:30, and
    // the idle line said the round's 0:30, a rest the engine never started. In a superset the
    // round's rest is the one all three read, the day's estimate included.
    func testTheRestAfterASetIsTheEngines() throws {
        var alone = CoreTestSupport.plan(sets: 2, rest: 90)
        alone.days[0].exercises[0].sets = alone.days[0].exercises[0].sets.map { var s = $0; s.groupRestSeconds = 30; return s }
        var engine = engine(alone)
        XCTAssertEqual(WorkoutScreen.idleLine(session: engine.session, step: 0), "Rest 1:30 starts when you log",
                       "v1.11: \"Rest 0:30 starts when you log\"")
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        guard case let .resting(rest) = engine.phase else { return XCTFail("expected a rest") }
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(90))

        var superset = CoreTestSupport.plan(sets: 2, secondExercise: true, rest: 90, group: "A")
        for e in superset.days[0].exercises.indices {
            superset.days[0].exercises[e].sets = superset.days[0].exercises[e].sets.map { var s = $0; s.groupRestSeconds = 30; return s }
        }
        let session = CoreTestSupport.session(superset)
        XCTAssertNil(WorkoutScreen.idleLine(session: session, step: 0), "inside a round, no rest")
        XCTAssertEqual(WorkoutScreen.idleLine(session: session, step: 1), "Rest 0:30 starts when you log")
        XCTAssertEqual(RestResolution.after(1, next: 2, steps: session.steps, exercises: session.exercises), .rest(30))
        XCTAssertEqual(RestResolution.betweenSets(after: session.steps[1], exercises: session.exercises), 30)
        XCTAssertEqual(RestResolution.betweenSets(after: CoreTestSupport.session(alone).steps[0],
                                                  exercises: CoreTestSupport.session(alone).exercises), 90,
                       "what the built-ins' estimate counts")
    }

    // TL15: the next step is said one way (§6.4) — "Bench Press · set 2 of 2 · Aim 8–12 reps · 60 kg",
    // led by "Next: " on the strip and in the rest's notification, by "Time!" when a hold ends, and
    // bare on the Lock Screen. The notification said the work alone (v1.11: "… · 10 reps"), and the
    // strip and the Lock Screen gave a drop the set's range.
    func testTheNextStepIsSaidOneWay() throws {
        let plan = CoreTestSupport.plan(sets: 2, work: .reps(.fixed(10)), rest: 90,
                                        drops: [DropTarget(work: .reps(.fixed(10)), weight: 50)])
        var engine = engine(plan)
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        let effects = engine.apply(.logSet(step: 1, result: .reps(count: 10, weight: 50)), now: now)
        let body = effects.compactMap { effect -> String? in
            if case let .scheduleNotification(id, _, body) = effect, id == .rest { return body }
            return nil
        }.first
        let line = "Bench Press · set 2 of 2 · Aim 8–12 reps · 60 kg"
        XCTAssertEqual(StepCard.stepLine(session: engine.session, step: 2), line)
        XCTAssertEqual(body, "Next: " + line)
        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now))
        XCTAssertEqual(screen.strip.next, "Next: " + line)
        XCTAssertEqual(WorkoutActivityState.of(engine.active, now: now)?.detail, line)
        XCTAssertEqual(WorkoutScreen.nextLine(session: engine.session, step: 1),
                       "Next: Bench Press · set 1 of 2 · Aim 10 reps · 50 kg",
                       "a drop's reps are its own; v1.11 said the set's 8–12")

        var hold = self.engine(CoreTestSupport.plan(sets: 1, work: .duration(seconds: 30), weight: nil))
        let timed = hold.apply(.startTimer(step: 0), now: now)
        XCTAssertTrue(timed.contains(.scheduleNotification(id: .setEnd, at: now.addingTimeInterval(30),
                                                           body: "Time! Bench Press · set 1 of 1 · For 30 seconds")))
    }

    // TL16: skipping an exercise starts the walk, as a skipped last set does (§6.3, §6.55): the ring
    // fills over a rest whose end is the alert. v1.11 put Row's card up with the block's line and no
    // rest under the ring, so it filled in silence. A walk of 0 is still straight through.
    func testSkippingAnExerciseStartsTheWalk() throws {
        let plan = CoreTestSupport.plan(sets: 2, secondExercise: true)
        var engine = engine(plan, walk: 120)
        let effects = engine.apply(.skipExercise(exerciseIndex: 0), now: now)
        guard case let .resting(rest) = engine.phase else {
            return XCTFail("v1.11: working on Row, with no rest under the ring")
        }
        XCTAssertEqual(rest, RestState(startedAt: now, endsAt: now.addingTimeInterval(120), nextStep: 2,
                                       kind: .betweenExercises))
        XCTAssertEqual(engine.active.blockDone, BlockDone(finishedBlock: 0, startedAt: now))
        XCTAssertTrue(effects.contains(.scheduleNotification(id: .rest, at: rest.endsAt,
                                                             body: "Next: Row · set 1 of 2 · Aim 8–12 reps · 60 kg")))

        var skipped = self.engine(plan, walk: 120)
        skipped.apply(.skipSet(step: 0), now: now)
        skipped.apply(.skipSet(step: 1), now: now)
        XCTAssertEqual(skipped.phase, engine.phase, "the walk a skipped last set starts")
        XCTAssertEqual(skipped.active.blockDone, engine.active.blockDone)

        var straight = self.engine(plan)
        straight.apply(.skipExercise(exerciseIndex: 0), now: now)
        XCTAssertEqual(straight.phase, .working(step: 2))
        XCTAssertEqual(straight.active.blockDone, BlockDone(finishedBlock: 0, startedAt: now))
    }

    // TL17: the walk is read one way (`ActiveSession.walk`): while its rest runs the minimum, after
    // it, and after `dismissBlockDone` has cleared the line (which leaves the rest running, §6.6),
    // the stage, the strip and the Lock Screen say the same walk from the same start.
    func testTheWalkIsReadOneWay() throws {
        var engine = engine(CoreTestSupport.plan(sets: 1, secondExercise: true), walk: 60)
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        func check(_ label: String, endsAt: Date?, line: Bool, at seconds: Int) throws {
            let time = now.addingTimeInterval(Double(seconds))
            let walk = try XCTUnwrap(engine.active.walk, label)
            XCTAssertEqual(walk.startedAt, now, label)
            XCTAssertEqual(walk.next, 1, label)
            XCTAssertEqual(walk.endsAt, endsAt, label)
            let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: time,
                                                           walk: engine.walk))
            XCTAssertEqual(screen.stage, .betweenExercises, label)
            XCTAssertEqual(screen.strip.kind, .blockDone, label)
            XCTAssertEqual(screen.strip.direction, .up, label)
            XCTAssertEqual(screen.strip.countdown, TargetText.time(seconds), label)
            XCTAssertEqual(screen.strip.ring?.minimum, 60, label)
            XCTAssertEqual(screen.strip.title?.hasPrefix("Bench Press done"), line, label)
            let activity = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: time), label)
            XCTAssertEqual(activity.title, "Between exercises", label)
            XCTAssertNil(activity.endsAt, label)
            XCTAssertEqual(activity.startedAt, now, label)
        }
        var dismissed = engine
        try check("while its rest runs", endsAt: now.addingTimeInterval(60), line: true, at: 20)
        engine.apply(.restElapsed, now: now.addingTimeInterval(60))
        XCTAssertEqual(engine.phase, .working(step: 1))
        try check("after it", endsAt: nil, line: true, at: 75)

        dismissed.apply(.dismissBlockDone, now: now.addingTimeInterval(5))
        engine = dismissed
        try check("its line cleared", endsAt: now.addingTimeInterval(60), line: false, at: 20)

        engine.apply(.logSet(step: 1, result: .reps(count: 10, weight: 60)), now: now.addingTimeInterval(80))
        XCTAssertNil(engine.active.walk, "Log set ends it")
    }

    // TL18: last time is one lookup (§6.5). The result and the weight read the same set of last
    // time, and differ by one argument: the weight's passes over a set logged without one.
    func testLastTimeIsOneLookup() throws {
        let plan = CoreTestSupport.plan(sets: 3, weight: 60)
        let last = CoreTestSupport.completed([10, 8, 6], weights: [70, nil, 72.5], plan: plan)
        let session = CoreTestSupport.session(plan)
        let steps = try XCTUnwrap(Prefill.lastSteps(session: session, step: 1, history: [last])).steps
        XCTAssertEqual(Prefill.lastResult(for: session.steps[1], in: steps), .reps(count: 8, weight: nil))
        XCTAssertEqual(Prefill.lastResult(for: session.steps[1], in: steps, keep: { $0.weight != nil })?.weight, 72.5)
        XCTAssertEqual(Prefill.historicalResult(session: session, step: 1, history: [last]), .reps(count: 8, weight: nil))
        XCTAssertEqual(Prefill.values(session: session, step: 1, history: [last]).lastWeight, 72.5)
        XCTAssertEqual(Prefill.values(session: session, step: 0, history: [last]).lastWeight, 70)
    }

    // TL19: the limits are said once, in `TargetGrammar`: a weight is 0 to 10,000 wherever it comes
    // from, and a name is trimmed and cut to 100 characters wherever it is given.
    func testTheLimitsAreSaidOnce() throws {
        var engine = CoreTestSupport.engine()
        let long = String(repeating: "a", count: 150)
        engine.apply(.renameExercise(exerciseIndex: 0, name: "  \(long)  "), now: now)
        XCTAssertEqual(engine.session.exercises[0].name, String(long.prefix(TargetGrammar.nameLength)))
        XCTAssertEqual(TargetGrammar.cleanName("  \(long)  "), engine.session.exercises[0].name)
        XCTAssertNil(TargetGrammar.cleanName("   "))
        XCTAssertTrue(engine.apply(.renameExercise(exerciseIndex: 0, name: "   "), now: now).isEmpty)

        engine.apply(.setWorkWeight(step: 0, weight: TargetGrammar.maxWeight), now: now)
        XCTAssertEqual(engine.active.workWeight, TargetGrammar.maxWeight)
        engine.apply(.setWorkWeight(step: 0, weight: TargetGrammar.maxWeight + 1), now: now)
        XCTAssertEqual(engine.active.workWeight, TargetGrammar.maxWeight, "refused")
        XCTAssertTrue(engine.apply(.logSet(step: 0, result: .reps(count: 5, weight: .nan)), now: now).isEmpty)
        XCTAssertTrue(engine.apply(.substituteExercise(exerciseIndex: 0, name: "Row", weight: -1), now: now).isEmpty)
        XCTAssertEqual(InputRules.weight("10001", previous: "100"), "100")
        XCTAssertEqual(PlanImport.run(CoreTestSupport.planJSON(exercise: #"{ "name": "Bench Press", "sets": 1, "reps": 5, "weight": 10001 }"#),
                                      settings: settings, now: now).errors.map(\.code), ["E_WEIGHT_INVALID"])
    }

    // TL20: a step is the session's step, and its target a named type. The flattener hands
    // `Session.start` its `SessionStep`s as they are; `target(at:)` is a `StepTarget` — a set's
    // warning and effort target, none for a drop, no weight on a bodyweight exercise; and the
    // active session writes the keys it always has, the synthesized encoder in the hand-written
    // one's place.
    func testAStepIsTheSessionsStep() throws {
        var plan = CoreTestSupport.plan(sets: 1, drops: [DropTarget(work: .reps(.fixed(8)), weight: 40)])
        plan.days[0].exercises[0].sets[0].inReserve = 2
        let session = CoreTestSupport.session(plan)
        XCTAssertEqual(session.steps, flatten(day: plan.days[0]))
        XCTAssertEqual(session.target(at: 0), StepTarget(work: .reps(.range(min: 8, max: 12)), weight: 60, reserve: 2))
        XCTAssertEqual(session.target(at: 1), StepTarget(work: .reps(.fixed(8)), weight: 40))
        XCTAssertNil(CoreTestSupport.session(CoreTestSupport.plan(bodyweight: true)).target(at: 0)?.weight)

        let active = ActiveSession(session: session, phase: .working(step: 0))
        let data = try JSONEncoder().encode(active)
        let keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["session", "phase", "timerRunning", "deliveredBeeps"])
        XCTAssertEqual(try JSONDecoder().decode(ActiveSession.self, from: data), active)
    }

    // TL21: the day's blocks and its counts, once. The stage and the progress line count an
    // exercise's place the same way after Do later; the bar and the Lock Screen count the steps
    // finished the same way; and the Overview and Session detail draw one list of blocks.
    func testCountsAndBlocksAreOnce() throws {
        var engine = engine(CoreTestSupport.plan(sets: 2, secondExercise: true))
        engine.apply(.skipSet(step: 0), now: now)
        engine.apply(.deferExercise(exerciseIndex: 0), now: now)
        let step = try XCTUnwrap(engine.active.currentStep)
        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now))
        XCTAssertEqual(screen.stage.title, StepCard.progress(session: engine.session, step: step))
        XCTAssertEqual(screen.stage.title, "Exercise 1 of 2 · Set 1 of 2", "Row now runs first")
        XCTAssertEqual(WorkoutActivityState.of(engine.active, now: now)?.done, SessionStats.finishedCount(engine.session))
        XCTAssertEqual(WorkoutStage.progress(engine.session), 0.25)

        let overview = try FixtureLoader.requiredDoc("JimmsBro/Features/Overview/OverviewView.swift")
        let detail = try FixtureLoader.requiredDoc("JimmsBro/Features/SessionDetail/SessionDetailView.swift")
        for source in [overview, detail] {
            XCTAssertTrue(source.contains("SessionBlocks.blocks(session)"))
            XCTAssertFalse(source.contains("SessionBlocks.indices"))
        }
    }

    // MARK: - L5: the chatbot screens

    // TL22: one refusal for every trip screen (`TripRefusal`), which differ only in their way back.
    // The prompt pasted, or nothing, is fixed at Paste everywhere by the screen's own prompt; the
    // rest at Chat — asked for whole on Add plan and Say what should change, with day by day
    // beside it on Add plan alone for a reply cut short, and a plan in words sent Add plan's prompt,
    // which it has not met. A refusal that names no error is fixed at Chat, since SPEC §6.60 names
    // Paste only for the prompt or nothing; Add plan had it at Paste, the other screens at Chat.
    func testOneRefusalForEveryTripScreen() throws {
        let ways: [TripRefusal.WayBack] = [.prompt, .wholePlan, .wholePlanOrDayByDay]
        for fixture in ["invalid/prompt-pasted.txt", "invalid/empty.txt"] {
            let issues = try CoreTestSupport.importing(fixture: fixture).issues
            for way in ways {
                let refusal = TripRefusal.of(issues, way: way)
                XCTAssertEqual(refusal.fix, .paste, "\(fixture), \(way)")
                XCTAssertEqual(refusal.sends, .prompt, "\(fixture), \(way)")
                XCTAssertEqual(refusal.buttons(prompt: "the outline prompt"), .ask("the outline prompt"))
            }
        }
        let cut = try CoreTestSupport.importing(fixture: "invalid/truncated.txt").issues
        let words = try CoreTestSupport.importing(fixture: "invalid/not-json-at-all.txt").issues
        XCTAssertEqual(ways.map { TripRefusal.of(cut, way: $0).sends }, [.prompt, .wholePlan, .wholePlan])
        XCTAssertEqual(ways.map { TripRefusal.of(cut, way: $0).offersDayByDay }, [false, false, true])
        XCTAssertEqual(ways.map { TripRefusal.of(words, way: $0).sends }, [.prompt, .wholePlan, .prompt])
        for issues in [cut, words] {
            XCTAssertEqual(ways.map { TripRefusal.of(issues, way: $0).fix }, [.chat, .chat, .chat])
        }
        let whole = TripRefusal.of(cut, way: .wholePlan)
        XCTAssertEqual(whole.buttons(), TripButtons(primary: "Ask for the whole plan", secondary: "Copy the prompt"))
        XCTAssertEqual(whole.prompt(or: "own"), Prompts.render(errors: cut))
        XCTAssertEqual(TripRefusal.of(cut, way: .prompt).prompt(or: "own"), "own")
        XCTAssertEqual(whole.sentence, IssueText.friendly(try XCTUnwrap(cut.first)))

        // The disagreement: nothing names what refused it.
        let unnamed = TripRefusal.of([Issue(severity: .warning, code: "W_UNKNOWN_FIELD", path: "x", message: "Ignored.")],
                                     way: .wholePlanOrDayByDay)
        XCTAssertEqual(unnamed.fix, .chat)
        XCTAssertEqual(unnamed.sends, .prompt, "a fix-it prompt would name nothing")
        XCTAssertEqual(unnamed.errors, [], "a warning is not what refused it")
        XCTAssertNil(unnamed.sentence)

        // Each screen's refusal is that one, with its own way back.
        let truncated = try FixtureLoader.text("invalid/truncated.txt")
        var add = ImportTrip()
        add.pasted(result: PlanImport.run(truncated, settings: settings, now: now))
        XCTAssertEqual(add.refusal, TripRefusal.of(cut, way: .wholePlanOrDayByDay))
        var change = ChangeRequest(plan: CoreTestSupport.plan())
        change.say("Fewer sets")
        change.sent()
        change.pasted(result: PlanImport.run(truncated, settings: settings, now: now))
        XCTAssertEqual(change.refusal, TripRefusal.of(cut, way: .wholePlan))
        let reply = ProgressionImport.run("```json\n[1, 2]\n```", plan: CoreTestSupport.plan(), settings: settings,
                                          now: now, mode: .performance)
        var progression = ProgressionScreen()
        progression.sent()
        progression.read(reply)
        XCTAssertEqual(progression.refusal, TripRefusal.of(reply.issues, way: .prompt))
        let outline = PlanDrafting.outline(truncated, settings: settings, now: now)
        var draft = DraftTrip(draft: nil, settings: settings)
        draft.sent()
        draft.pasted(outline, settings: settings, now: now)
        XCTAssertEqual(draft.refusal, TripRefusal.of(outline.issues, way: .prompt))
        XCTAssertEqual(draft.buttons, .ask("the outline prompt"), "a draft asks with its own prompt, again")
    }

    // TL23: one ··· on every trip screen, drawn by one view from Core's items (§6.68): Send the
    // prompt again once the prompt has gone, Edit the text last wherever it is.
    func testOneMenuForEveryTripScreen() throws {
        var change = ChangeRequest(plan: CoreTestSupport.plan())
        XCTAssertEqual(change.menu, [.editText])
        change.say("Fewer sets")
        change.sent()
        XCTAssertEqual(change.menu, [.sendAgain, .editText])
        var screen = ProgressionScreen()
        XCTAssertEqual(screen.menu(hasProgression: false, planning: false), [.editText])
        screen.sent()
        XCTAssertEqual(screen.menu(hasProgression: false, planning: false), [.sendAgain, .editText])
        XCTAssertEqual(screen.menu(hasProgression: true, planning: true), [.sendAgain, .keepCurrent, .removeProgression, .editText])
        XCTAssertEqual(screen.menu(hasProgression: true, planning: false), [.removeProgression],
                       "the running progression's screen has no text behind it")
        XCTAssertEqual(ImportTrip().menu.last, .editText)
        XCTAssertEqual(DraftTrip(draft: nil, settings: settings).menu.last, .editText)
        XCTAssertEqual(TripMenuItem.sendAgain.title, TripText.sendAgain)
        XCTAssertEqual(TripMenuItem.editText.title, TripText.editText)
        XCTAssertEqual([TripMenuItem.sendAgain, .openFile, .keepWithoutUsing, .discardDraft, .keepCurrent,
                        .removeProgression, .editText].filter(\.isDestructive), [.discardDraft, .removeProgression])

        let add = try FixtureLoader.requiredDoc("JimmsBro/Features/Import/ImportView.swift")
        let changing = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/ChangePlanView.swift")
        let planning = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/ProgressionView.swift")
        for (name, source) in [("ImportView", add), ("ChangePlanView", changing), ("ProgressionView", planning)] {
            XCTAssertTrue(source.contains("TripMenu(items: "), "\(name) builds its own ···")
            XCTAssertFalse(source.contains("Menu {"), "\(name) builds its own ···")
            XCTAssertFalse(source.contains("TripText."), "\(name) writes a menu item's words itself")
            XCTAssertFalse(source.contains("\"Send the prompt again\""), name)
        }
    }

    // TL24: Core chooses the prompt on every screen — the plan prompt or a refusal's fix-it prompt,
    // the outline's or a day's, the progression's with the plan's history — and the subject beside
    // it. The views and the model have no route of their own.
    func testCoreChoosesThePrompt() throws {
        var add = ImportTrip()
        XCTAssertEqual(add.prompt(settings: settings), Prompts.render(settings: settings))
        add.pasted(result: try CoreTestSupport.importing(fixture: "invalid/no-days.json"))
        XCTAssertEqual(add.prompt(settings: settings), Prompts.render(errors: try CoreTestSupport.importing(fixture: "invalid/no-days.json").errors))
        add.pasted(result: try CoreTestSupport.importing(fixture: "invalid/not-json-at-all.txt"))
        XCTAssertEqual(add.prompt(settings: settings), Prompts.render(settings: settings), "a plan in words meets the prompt")

        let plan = CoreTestSupport.plan()
        let session = CoreTestSupport.completed(plan: plan)
        var screen = ProgressionScreen()
        screen.mark(steps: 8)
        XCTAssertEqual(screen.prompt(plan: plan, history: [session], settings: settings, now: now),
                       Prompts.progression(plan: plan, history: [session], weeks: 8, settings: settings, now: now,
                                           mode: ProgressionScreen.defaultMode))
        XCTAssertEqual(ProgressionScreen.subject(plan), "Progression for \(plan.name)")

        let addView = try FixtureLoader.requiredDoc("JimmsBro/Features/Import/ImportView.swift")
        let changing = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/ChangePlanView.swift")
        let planning = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/ProgressionView.swift")
        let drafts = try FixtureLoader.requiredDoc("JimmsBro/Store/DraftModel.swift")
        let progressions = try FixtureLoader.requiredDoc("JimmsBro/Store/ProgressionModel.swift")
        for (name, source) in [("ImportView", addView), ("ChangePlanView", changing), ("ProgressionView", planning)] {
            XCTAssertFalse(source.contains("Prompts."), "\(name) chooses a prompt itself")
            XCTAssertFalse(source.contains("subject: \""), "\(name) writes the share sheet's subject itself")
        }
        XCTAssertFalse(drafts.contains("func outlinePrompt") || drafts.contains("func dayPrompt"), "a second route to a draft's prompts")
        XCTAssertFalse(progressions.contains("func progressionPrompt"), "a second route to the progression prompt")
    }

    // TL25: every text sheet is a `JSONPoint`, built there and nowhere else — and a whole plan's
    // has one sheet: Plan detail's Edit the text is a fragment target whose Save is an edit, which
    // keeps the plan's id, its progression and, when the text names no unit, its unit, as a reply
    // to Say what should change does (one rule, `ImportResult.planKeepingUnits(of:)`).
    func testEveryTextSheetIsAJSONPoint() throws {
        var plan = CoreTestSupport.plan()
        let wholes = [JSONPoint.newPlan(template: "{}"), .replacing(plan.name, text: "{}"), .assembled(plan.name, text: "{}"),
                      .outline, .changing(plan.name, text: "{}")]
        XCTAssertEqual(wholes.map(\.kind), Array(repeating: JSONPoint.Kind.plan, count: 5))
        XCTAssertEqual(Set(wholes.prefix(3).map(\.footer)).count, 1, "one footer for a whole plan")
        XCTAssertEqual(JSONPoint.progression(plan, steps: 2, text: "").kind, .progression)
        XCTAssertEqual(JSONPoint.draftDay(plan, index: 0)?.kind, .day(0))
        XCTAssertNil(JSONPoint.draftDay(plan, index: 9))
        XCTAssertEqual(ImportTrip().textPoint, .newPlan(template: JSONPoint.examplePlan))
        XCTAssertEqual(DraftTrip(draft: nil, settings: settings).textPoint(assembled: nil), .outline)
        XCTAssertEqual(ChangeRequest(plan: plan).textPoint(), .changing(plan.name, text: PlanJSON.render(plan)))

        plan.units = .lb
        plan.progression = Progression(startDate: now, weeks: 1, entries: [
            ProgressionEntry(dayName: plan.days[0].name, exerciseName: plan.days[0].exercises[0].name,
                             weeks: [ProgressionWeek(weight: 62.5)]),
        ])
        var tree = try XCTUnwrap(PlanImport.decode(PlanJSON.render(plan)).value?.object)
        tree["units"] = nil
        tree["name"] = .string("Renamed")
        let silent = RawJSON.object(tree).jsonText
        let point = JSONPoint.replacing(plan.name, text: plan.sourceText)
        XCTAssertEqual(point.operation(silent), .replacePlanJSON(text: silent))
        let saved = try XCTUnwrap(PlanEdit.apply(.replacePlanJSON(text: silent), to: plan, settings: Settings(), now: now).plan)
        XCTAssertEqual(saved.name, "Renamed")
        XCTAssertEqual(saved.units, .lb, "the text named no unit; the setting's kg is not a change anyone asked for")
        XCTAssertEqual(saved.id, plan.id)
        XCTAssertEqual(saved.progression, plan.progression)
        XCTAssertEqual(PlanImport.run(silent, settings: Settings(), now: now).planKeepingUnits(of: plan)?.units, .lb)

        let add = try FixtureLoader.requiredDoc("JimmsBro/Features/Import/ImportView.swift")
        let detail = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/PlanDetailView.swift")
        for file in ["ImportTrip", "DraftTrip", "ChangeRequest", "ProgressionScreen"] {
            let source = try XCTUnwrap(FixtureLoader.doc("JimmsBro/Core/\(file).swift"))
            XCTAssertFalse(source.contains("JSONPoint("), "\(file) builds a sheet itself")
        }
        XCTAssertFalse(add.contains("replacingPlanId"), "Add plan is a second sheet for a whole plan again")
        XCTAssertFalse(add.contains("PlanJSON.render"))
        XCTAssertFalse(detail.contains("ImportView("), "Plan detail opens Add plan to edit its text again")
        XCTAssertTrue(detail.contains("fragment = .plan"))
    }

    // TL26: a draft's day is tried one way (§6.64): the review draws a slot exactly when the day's
    // paste would take it, and the screen reads it when the draft changes, not each time it draws.
    func testADraftsDayIsTriedOnce() throws {
        let text = #"{ "name": "Two", "units": "kg", "days": [ { "name": "A" }, { "name": "B" } ] }"#
        let outline = try XCTUnwrap(PlanDrafting.outline(text, settings: settings, now: now).draft)
        let a = #"{ "name": "A", "exercises": [ { "name": "Squat", "sets": 3, "reps": 5 } ] }"#
        let taken = try XCTUnwrap(PlanDrafting.day(a, into: outline, index: 0, settings: settings, now: now).draft)
        XCTAssertEqual(PlanDrafting.preview(taken, settings: settings, now: now).days.map { $0.exercises.map(\.name) },
                       [["Squat"], []])
        let refused = #"{ "name": "B", "exercises": [ { "name": "Row", "sets": 3, "reps": "lots" } ] }"#
        XCTAssertNil(PlanDrafting.day(refused, into: taken, index: 1, settings: settings, now: now).draft)
        var forced = taken
        forced.dayTexts[1] = refused
        XCTAssertEqual(PlanDrafting.preview(forced, settings: settings, now: now).days[1].exercises.count, 0,
                       "a text the day's check refuses is not drawn either")

        var trip = DraftTrip(draft: outline, settings: settings, now: now)
        XCTAssertEqual(trip.preview?.days.map(\.exercises.count), [0, 0])
        trip.pasted((taken, []), settings: settings, now: now)
        XCTAssertEqual(trip.preview?.days.map { $0.exercises.map(\.name) }, [["Squat"], []])

        let add = try FixtureLoader.requiredDoc("JimmsBro/Features/Import/ImportView.swift")
        XCTAssertFalse(add.contains("preview(settings"), "Add plan reads the draft again each time it draws")
    }

    // TL27: the chatbot screens' shared parts are drawn once, in Features/Shared — the refusal and
    // its Details, Worth knowing, the tidying, the Paste button.
    func testTheChatbotScreensShareTheirParts() throws {
        let parts = try FixtureLoader.requiredDoc("JimmsBro/Features/Shared/TripParts.swift")
        let add = try FixtureLoader.requiredDoc("JimmsBro/Features/Import/ImportView.swift")
        let changing = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/ChangePlanView.swift")
        let planning = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/ProgressionView.swift")
        let sheet = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/JSONFragmentSheet.swift")
        for literal in ["issue.code) · ", "Section(\"Worth knowing\")", "DisclosureGroup(\"Details", "PasteButton(payloadType"] {
            XCTAssertTrue(parts.contains(literal), "the shared parts lost \(literal)")
        }
        let screens = [("ImportView", add), ("ChangePlanView", changing), ("ProgressionView", planning)]
        for (name, source) in screens + [("JSONFragmentSheet", sheet)] {
            XCTAssertFalse(source.contains("issue.code) · "), "\(name) writes Details itself")
            XCTAssertFalse(source.contains("Section(\"Worth knowing\")"), "\(name) writes Worth knowing itself")
            XCTAssertFalse(source.contains("DisclosureGroup(\"Details"), "\(name) writes the tidying itself")
        }
        for (name, source) in screens {
            XCTAssertFalse(source.contains("PasteButton(payloadType"), "\(name) styles Paste itself")
            XCTAssertTrue(source.contains("RefusalDetails(refusal: "), "\(name) draws a refusal itself")
        }
    }

    // TL28: the Summary's lines are Core's (`SummaryText`), worked out once per screen — the
    // records read once, not once per exercise, and the comparison never against itself.
    func testTheSummarysLinesAreCores() throws {
        let plan = CoreTestSupport.plan(sets: 2, secondExercise: true)
        let now = CoreTestSupport.now
        let before = CoreTestSupport.completed([10], weights: [60, 60, 60, 60], plan: plan,
                                               start: now.addingTimeInterval(-7 * 86400))
        var today = CoreTestSupport.completed([10], weights: [60, 62.5, 60, 60], plan: plan, start: now)
        today.exercises[1].substitutedFor = "Cable Row"

        XCTAssertEqual(SummaryText.headline(today), "Push · 3 min · 4 of 4 sets · Volume 2,425 kg")

        let lines = SummaryText.exercises(today, history: [before, today])
        XCTAssertEqual(lines.map(\.name), ["Bench Press", "Row"])
        XCTAssertEqual(lines.map(\.record), ["PR 10 × 62.5 kg", nil])
        XCTAssertEqual(lines.map(\.insteadOf), [nil, "Instead of Cable Row"])
        XCTAssertEqual(lines.map(\.took), ["Took 1:34 · 0:34 a set", "Took 2:00 · 0:34 a set"])
        XCTAssertEqual(lines[0].comparison,
                       SessionStats.comparison(for: "Bench Press", session: today, history: [before]),
                       "the session is compared with the ones before it, never itself")
        XCTAssertEqual(lines, SummaryText.exercises(today, history: [before]),
                       "the session itself in the history changes nothing")

        let summary = try FixtureLoader.requiredDoc("JimmsBro/Features/Summary/SummaryView.swift")
        let detail = try FixtureLoader.requiredDoc("JimmsBro/Features/SessionDetail/SessionDetailView.swift")
        for owner in ["SummaryText.headline(", "SummaryText.exercises("] {
            XCTAssertTrue(summary.contains(owner), "the Summary no longer draws \(owner)")
        }
        for gone in ["personalRecords", "ProgressionAdvice", "mean(", "\"Took ", "Volume \\(", "SessionStats.comparison"] {
            XCTAssertFalse(summary.contains(gone), "the Summary works out \(gone) itself again")
        }
        XCTAssertEqual(detail.components(separatedBy: "personalRecords(").count - 1, 1,
                       "Session detail reads the records once")
        XCTAssertFalse(detail.contains("private var records"), "Session detail reads the records per row again")
    }

    // TL29: Progression's lines are Core's — the second line, the step it is on, the ladder or
    // the weeks, the rows of a day, and one test of an entry done (`ProgressionEntry.isDone`).
    func testProgressionsLinesAreCores() throws {
        let calendar = CoreTestSupport.utc()
        let start = calendar.startOfDay(for: CoreTestSupport.date(10))
        let bench = ProgressionEntry(dayName: "Push", exerciseName: "Bench Press",
                                     weeks: [ProgressionWeek(weight: 80), ProgressionWeek(weight: 82.5)], step: 1)
        let row = ProgressionEntry(dayName: "Push", exerciseName: "Row",
                                   weeks: [ProgressionWeek(weight: 50), ProgressionWeek(weight: 52.5)], step: 2)
        XCTAssertEqual([bench.isDone, row.isDone], [false, true])

        var earned = Progression(startDate: start, weeks: 2, entries: [row, bench], mode: .performance)
        let date = CoreTestSupport.date(11)
        let startedText = "Started \(start.formatted(date: .abbreviated, time: .omitted))"
        XCTAssertEqual(ProgressionText.started(earned, calendar: calendar), "\(startedText) · 1 of 2 exercises done")
        XCTAssertEqual(ProgressionText.now(bench, in: earned, units: .kg, bodyweight: false, on: date, calendar: calendar),
                       "This step: 82.5 kg")
        XCTAssertNil(ProgressionText.now(row, in: earned, units: .kg, bodyweight: false, on: date, calendar: calendar),
                     "an entry past its last step is on none")
        XCTAssertEqual(ProgressionText.steps(bench, in: earned, units: .kg, bodyweight: false, on: date, calendar: calendar),
                       "1) 80 kg · ▸ 2) 82.5 kg")
        XCTAssertFalse(earned.isFinished(on: date, calendar: calendar))
        earned.entries = [row]
        XCTAssertEqual(ProgressionText.started(earned, calendar: calendar), "\(startedText) · 1 of 1 exercise done")
        XCTAssertTrue(earned.isFinished(on: date, calendar: calendar))

        let weekly = Progression(startDate: start, weeks: 2, entries: [row, bench], mode: .calendar)
        let ends = weekly.endDate(calendar: calendar).formatted(date: .abbreviated, time: .omitted)
        XCTAssertEqual(ProgressionText.started(weekly, calendar: calendar), "\(startedText) · ends \(ends)")
        XCTAssertEqual(ProgressionText.now(bench, in: weekly, units: .kg, bodyweight: false, on: date, calendar: calendar),
                       "This week: 80 kg")
        XCTAssertEqual(ProgressionText.steps(bench, in: weekly, units: .kg, bodyweight: false, on: date, calendar: calendar),
                       ProgressionText.weeksLine(bench, units: .kg, bodyweight: false))

        let day = CoreTestSupport.plan(secondExercise: true).days[0]
        XCTAssertEqual(weekly.entries(on: day).map(\.exercise.name), ["Bench Press", "Row"], "in the day's order")

        let view = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/ProgressionView.swift")
        for gone in ["exercises done", "\"This step: \"", "\"This week: \"", "compactMap { exercise ->", "weeks.count"] {
            XCTAssertFalse(view.contains(gone), "ProgressionView works out \(gone) itself again")
        }
        for owner in ["ProgressionText.started(", "ProgressionText.now(", "ProgressionText.steps(", ".entries(on: "] {
            XCTAssertTrue(view.contains(owner), "ProgressionView no longer draws \(owner)")
        }
    }

    // TL30: one plural (`TargetText.counted`), one duration setting (`TargetText.setting`) and the
    // restore's sentences in `RestoreText`, where Settings wrote them.
    func testOnePluralAndSettingsSentences() throws {
        XCTAssertEqual(TargetText.counted(1, "plan"), "1 plan")
        XCTAssertEqual(TargetText.counted(0, "workout"), "0 workouts")
        XCTAssertEqual(TargetText.counted(3, "set"), "3 sets")
        XCTAssertEqual([0, 45, 60, 90, 300].map(TargetText.setting), ["Off", "45 s", "1 min", "1 min 30 s", "5 min"])

        let one = BackupSummary(exportedAt: CoreTestSupport.now, appVersion: "1.12", plans: 1, sessions: 2,
                                newPlans: 1, newSessions: 0)
        XCTAssertEqual(RestoreText.detail(one), "It holds 1 plan and 2 workouts. Merge adds 1 plan and 0 workouts, "
                       + "and changes nothing you already have. Replace all deletes everything here first.")
        var nothing = one
        nothing.newPlans = 0
        XCTAssertEqual(RestoreText.detail(nothing), "It holds 1 plan and 2 workouts. Merge would add nothing — "
                       + "you already have all of it. Replace all deletes everything here first.")
        XCTAssertEqual(RestoreText.title(nil), "Restore this backup?")
        XCTAssertTrue(RestoreText.title(one).hasPrefix("Backup from "))

        let sources = try FixtureLoader.swiftSources()
        let plurals = sources.filter { $0.text.contains("== 1 ? \"\" : \"s\"") }.map(\.path)
        XCTAssertEqual(plurals, ["JimmsBro/Core/Stats.swift"], "a plural spelled out again")
        let settings = try XCTUnwrap(sources.first { $0.path.hasSuffix("Settings/SettingsView.swift") }).text
        for gone in ["func duration", "restoreDetail", "restorePrompt", "It holds"] {
            XCTAssertFalse(settings.contains(gone), "Settings writes \(gone) again")
        }
    }

    // TL31: one question when a start meets an open workout (D17) — the words Core's, the alert
    // and the refusal's catch drawn once, for Today and Plan detail alike.
    func testOneSwitchWorkoutAlert() throws {
        var open = CoreTestSupport.session(CoreTestSupport.plan(sets: 3))
        open.steps[0].status = .logged
        XCTAssertEqual(SessionSwitch.prompt(open),
                       "You're in the middle of Push (1 of 3 sets). Switching workouts mid-session isn't recommended.")
        XCTAssertEqual(SessionSwitch.prompt(nil), "Switch workout?")

        let sources = try FixtureLoader.swiftSources()
        let asking = sources.filter { $0.text.contains("\"Discard and start\"") }.map(\.path)
        XCTAssertEqual(asking, ["JimmsBro/Features/Shared/Presenting.swift"], "the switch alert is drawn twice again")
        let catching = sources.filter { $0.text.contains("LibraryError.sessionInProgress")
                                        && $0.path.hasPrefix("JimmsBro/Features/") }.map(\.path)
        XCTAssertEqual(catching, ["JimmsBro/Features/Shared/Presenting.swift"])
        for name in ["Home/HomeView.swift", "PlanDetail/PlanDetailView.swift"] {
            let view = try XCTUnwrap(sources.first { $0.path.hasSuffix(name) }).text
            XCTAssertTrue(view.contains(".switchWorkoutAlert("), "\(name) asks its own way")
            XCTAssertTrue(view.contains("beginWorkout("), "\(name) catches the refusal itself")
            XCTAssertFalse(view.contains("switchPrompt"), "\(name) words the question itself")
            XCTAssertFalse(view.contains("try? await model.start"), "\(name) swallows a start's error")
        }
    }

    // TL32: the views' small repeats, once — an optional as a presentation's flag, the alert that
    // only says why, and one share sheet for the prompt, the backup and the CSV.
    func testTheViewsSmallRepeatsAreOnce() throws {
        let sources = try FixtureLoader.swiftSources()
        let shared = "JimmsBro/Features/Shared/Presenting.swift"
        let flags = sources.filter { $0.text.contains("!= nil }, set: { if !$0") }.map(\.path)
        XCTAssertEqual(flags, [], "an optional bound to a flag by hand again")
        let oks = sources.filter { $0.text.contains("Button(\"OK\", role: .cancel)") }.map(\.path)
        XCTAssertEqual(oks, [shared], "an OK-only alert written out again")
        let sheets = sources.filter { $0.text.contains("UIActivityViewController(") }.map(\.path)
        XCTAssertEqual(sheets, [shared], "a second share sheet")
        let settings = try XCTUnwrap(sources.first { $0.path.hasSuffix("Settings/SettingsView.swift") }).text
        XCTAssertTrue(settings.contains(".shareSheet("))
        XCTAssertFalse(settings.contains("ShareSheet("))
    }

    // TL33: the exercise sheet saves once — every changed field one `editExercise`, one pipeline
    // run, all of them or none — and makes what the fields made one at a time.
    func testTheExerciseSheetSavesOnce() throws {
        let plan = CoreTestSupport.plan(secondExercise: true, group: "A")
        let changes: [PlanEdit.ExerciseChange] = [.name("Incline Press"), .setCount(4), .rest(120)]
        let once = PlanEdit.apply(.editExercise(day: 0, exercise: 0, changes: changes), to: plan,
                                  settings: settings, now: CoreTestSupport.now)
        let edited = try XCTUnwrap(once.plan, "\(once.errors)")
        var stepwise = plan
        for change in changes {
            stepwise = try XCTUnwrap(PlanEdit.apply(change.operation(day: 0, exercise: 0), to: stepwise,
                                                    settings: settings, now: CoreTestSupport.now).plan)
        }
        XCTAssertEqual(PlanJSON.render(edited), PlanJSON.render(stepwise), "one edit makes what the fields made one by one")
        XCTAssertEqual(edited.days[0].exercises[0].name, "Incline Press")
        XCTAssertEqual(edited.days[0].exercises[0].sets.count, 4)
        XCTAssertEqual(edited.days[0].exercises[1].sets.map(\.groupRestSeconds), [120, 120, 120],
                       "a superset's rest still reaches the round")

        let refused = PlanEdit.apply(.editExercise(day: 0, exercise: 0, changes: [.name("Incline Press"), .rest(5000)]),
                                     to: plan, settings: settings, now: CoreTestSupport.now)
        XCTAssertNil(refused.plan, "a refusal part-way saves none of it")
        XCTAssertEqual(refused.errors.map(\.code), ["E_EDIT_INVALID"])

        let sheet = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/ExerciseEditSheet.swift")
        let detail = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/PlanDetailView.swift")
        XCTAssertFalse(sheet.contains("for change in changes"), "the sheet commits a field at a time again")
        XCTAssertTrue(detail.contains(".editExercise("))
    }
}
