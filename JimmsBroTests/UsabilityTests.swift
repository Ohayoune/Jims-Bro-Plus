import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// U1 (v1.6) — D55: nothing untrue. The 2026-09-09 audit found five places where the app
/// volunteered a sentence the person knew to be false; each was a Core rule, and each is a test.
final class UsabilityTests: XCTestCase {
    private let calendar = CoreTestSupport.utc()
    private func day(_ number: Int) -> Date { CoreTestSupport.date(number) }

    /// Push / Pull / Legs / rest, imported on the 1st.
    private func rotation(anchor: Int?, position: Int? = nil, imported: Int = 1) -> Plan {
        var plan = Plan(name: "PPL", units: .kg, schedule: .rotation,
                        days: [Day(name: "Push", exercises: []),
                               Day(name: "Pull", exercises: []),
                               Day(name: "Legs", exercises: [])],
                        importedAt: day(imported), sourceText: "",
                        cycle: [.day(0), .day(1), .day(2), .rest])
        plan.cyclePosition = position
        plan.cycleAnchor = anchor.map { calendar.startOfDay(for: day($0)) }
        return plan
    }

    private func missed(_ plan: Plan, today: Int, sessions: [Session] = []) -> Int? {
        PlanSchedule.missed(plan, sessions: sessions, swaps: [], today: day(today), calendar: calendar)?.dayIndex
    }

    // U1: a missed workout is one the plan actually expected.
    func testAMissedDayIsAfterTheImportAndAfterTheAnchor() {
        // A fresh plan: nothing completed, no anchor. Three minutes old, it has missed nothing —
        // v1.5 projected the pattern backwards over the week before it existed.
        XCTAssertNil(missed(rotation(anchor: nil, imported: 9), today: 9))
        XCTAssertNil(missed(rotation(anchor: nil, imported: 9), today: 10))
        // Imported ten days ago and never started: still nothing missed. You never began.
        XCTAssertNil(missed(rotation(anchor: nil, imported: 1), today: 11))

        // Push done on the 7th (the anchor), today the 9th: Pull on the 8th was missed.
        XCTAssertEqual(missed(rotation(anchor: 7, position: 0), today: 9), 1)
        // The anchor day itself is never "missed" — it is the day that was done.
        XCTAssertNil(missed(rotation(anchor: 7, position: 0), today: 8))

        // A day run out of order re-anchors the pattern: Legs done on the 9th puts Pull on the
        // 8th in the projection, but the 8th was lived through before the anchor moved.
        XCTAssertNil(missed(rotation(anchor: 9, position: 2), today: 10))
        // And the import day is a floor of its own: a plan imported on the 8th and anchored the
        // same day cannot have missed the 7th.
        XCTAssertNil(missed(rotation(anchor: 8, position: 1, imported: 8), today: 9))

        // The v1.2 rule still holds within those bounds: having trained on the 8th, nothing.
        var trained = CoreTestSupport.session(CoreTestSupport.plan(), start: day(8))
        trained.endedAt = day(8)
        XCTAssertNil(missed(rotation(anchor: 7, position: 0), today: 9, sessions: [trained]))
        // And it still looks no further back than a week: anchored on the 1st and away until
        // the 20th, only the most recent projected day is reported, not the 2nd.
        XCTAssertNotEqual(PlanSchedule.missed(rotation(anchor: 1, position: 0), sessions: [], swaps: [], today: day(20),
                                              calendar: calendar)?.date, calendar.startOfDay(for: day(2)))

        // Home says the same thing the schedule does.
        var library = PlanLibrary()
        library.save(rotation(anchor: nil, imported: 9), makeActive: true)
        XCTAssertNil(HomeStart.current(library: library, now: day(9), calendar: calendar).missed)
    }

    // U2: "Nothing logged" outranks "First time".
    func testNothingLoggedOutranksFirstTime() {
        let plan = CoreTestSupport.plan()
        let untouched = CoreTestSupport.session(plan)       // every step pending
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: untouched, history: []).headline,
                       "Nothing logged", "no history and nothing logged is not a first time")
        let before = CoreTestSupport.completed([10, 10, 8], plan: plan)
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: untouched, history: [before]).headline,
                       "Nothing logged")
        // A first time that happened is still a first time.
        let first = CoreTestSupport.completed([10, 10, 8], plan: plan, start: CoreTestSupport.now)
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: first, history: []).headline,
                       "First time")
    }

    // U3: a calendar cell tells the plan's days apart.
    func testCalendarLabelsAreUniqueWithinThePlan() {
        func labels(_ names: [String]) -> [String] { names.map { CalendarText.short($0, among: names) } }
        XCTAssertEqual(labels(["Push", "Pull", "Legs"]), ["Push", "Pull", "Legs"])
        XCTAssertEqual(labels(["Upper Body", "Lower Body"]), ["Upper", "Lower"])
        // The audit's case: both days read "Full…".
        XCTAssertEqual(labels(["Full Body A", "Full Body B"]), ["FBA", "FBB"])
        XCTAssertEqual(labels(["Upper A", "Lower A", "Upper B", "Lower B"]), ["UA", "LA", "UB", "LB"])
        XCTAssertEqual(labels(["Day 1", "Day 2", "Day 3"]), ["D1", "D2", "D3"])
        XCTAssertEqual(labels(["Push A", "Push B"]), ["PA", "PB"])
        // Names whose initials also collide fall back to their number in the plan.
        XCTAssertEqual(labels(["Push A", "Push Alpha"]), ["1", "2"])
        // Mixed: only the colliding names change.
        XCTAssertEqual(labels(["Push", "Full Body A", "Full Body B"]), ["Push", "FBA", "FBB"])
        // A name the plan does not hold keeps the plain rule, as does a one-day plan.
        XCTAssertEqual(CalendarText.short("Shoulders and Arms", among: ["Push", "Pull"]), "Shou…")
        XCTAssertEqual(CalendarText.short("Full Body A", among: ["Full Body A"]), "Full")

        // Through the cell itself: a projected day and a completed session of the same plan.
        var plan = CoreTestSupport.plan()
        plan.days[0].name = "Full Body A"
        var b = plan.days[0]; b.id = UUID(); b.name = "Full Body B"
        plan.days.append(b)
        XCTAssertEqual(CalendarText.label(.projected(planId: plan.id, dayIndex: 1), plans: [plan]), "FBB")
        var session = CoreTestSupport.session(plan)
        session.endedAt = session.startedAt.addingTimeInterval(1800)
        XCTAssertEqual(CalendarText.label(.completed([session]), plans: [plan]), "FBA")
        // The spoken cell still says the whole name.
        XCTAssertTrue(CalendarText.spoken(CalendarDay(date: day(9), entry: .completed([session])),
                                          plans: [plan], calendar: calendar).hasSuffix("Done: Full Body A"))
    }

    // U4: the suggestion chip never contradicts the fields.
    func testTheChipNeverContradictsTheFields() throws {
        // A fixed target of 5 in a 4–6 range, last time 10 at the same weight.
        var plan = CoreTestSupport.plan(sets: 4, work: .reps(.fixed(5)), weight: 100)
        plan.days[0].exercises[0].repRange = RepRange(min: 4, max: 6)
        let last = CoreTestSupport.completed([10, 10, 10, 10], weights: [100, 100, 100, 100], plan: plan)
        let session = CoreTestSupport.session(plan)
        let target = try XCTUnwrap(session.target(at: 0))

        // "Do that again" is what was done — never the plan's 5 at last time's 100.
        let again = Prefill.setSuggestion(session: session, step: 0, exercise: session.exercises[0],
                                          target: target, last: .reps(count: 10, weight: 100),
                                          lastWeight: 100, advice: nil, adviceReason: nil, units: .kg)
        XCTAssertEqual(again?.text, "10 × 100 kg")
        XCTAssertEqual(again?.reason, "Last time 10 × 100 kg")

        // And since the fields are prefilled with exactly that, the card shows no chip at all.
        let values = Prefill.values(session: session, step: 0, history: [last])
        XCTAssertEqual(values.reps, 10); XCTAssertEqual(values.weight, 100)
        XCTAssertNil(values.suggestion)
        XCTAssertNil(StepCard.suggestionChip(values, units: .kg))

        // Advice differs from the fields, so it is shown, with its reason.
        var advised = last
        advised.exercises[0].advice = .increase(to: 102.5)
        let withAdvice = Prefill.values(session: session, step: 0, history: [advised])
        XCTAssertEqual(withAdvice.suggestion?.weight, 102.5)
        XCTAssertEqual(withAdvice.suggestion?.reason, "You hit the top of 4–6 last time")
        XCTAssertEqual(StepCard.suggestionChip(withAdvice, units: .kg), "Try 5 × 102.5 kg")

        // The first set of a plan with no weights: the fields already show the target's reps.
        let first = Prefill.values(session: CoreTestSupport.session(CoreTestSupport.plan(weight: nil)),
                                   step: 0, history: [])
        XCTAssertEqual(first.reps, 8); XCTAssertNil(first.weight)
        XCTAssertNil(first.suggestion, "\"Try 8 reps · The plan's target\" under a field reading 8 said nothing")
        // The second set carries the typed weight forward; the plan's chip, which has no
        // opinion on the weight, is still only repeating the reps field.
        var weightless = CoreTestSupport.session(CoreTestSupport.plan(weight: nil))
        weightless.steps[0].status = .logged
        weightless.steps[0].result = .reps(count: 8, weight: 135)
        weightless.steps[0].loggedAt = CoreTestSupport.now
        let second = Prefill.values(session: weightless, step: 1, history: [])
        XCTAssertEqual(second.reps, 8); XCTAssertEqual(second.weight, 135)
        XCTAssertNil(second.suggestion)

        // A held set keeps its chip: it is judged by its seconds, which the fields do not show.
        let held = CoreTestSupport.plan(work: .duration(seconds: 45), weight: nil)
        var longer = CoreTestSupport.session(held, start: CoreTestSupport.now.addingTimeInterval(-86400))
        for index in longer.steps.indices {
            longer.steps[index].status = .logged
            longer.steps[index].result = .duration(seconds: 60, weight: nil)
            longer.steps[index].loggedAt = longer.startedAt.addingTimeInterval(Double(index) * 90)
        }
        longer.endedAt = longer.steps.last?.loggedAt
        let hold = Prefill.values(session: CoreTestSupport.session(held), step: 0, history: [longer])
        XCTAssertEqual(hold.suggestion?.text, "60 s")
    }

    // U5: the right sentence for a paste that is not JSON.
    func testAPlanInWordsIsNotACutOffReply() {
        let words = PlanImport.run("Monday: bench press 3x8 at 60 kg, squat 3x5 at 80 kg, rest 2 minutes")
        XCTAssertEqual(words.errors.first?.code, "E_NOT_JSON")
        XCTAssertEqual(IssueText.friendly(words.errors[0]),
                       "This is a plan in words. Send it to a chatbot with the prompt and paste back what it writes.")
        // JSON that will not parse is still a reply that looks cut off.
        let cut = PlanImport.run(String(CoreTestSupport.planJSON().dropLast(20)))
        XCTAssertEqual(cut.errors.first?.code, "E_NOT_JSON")
        XCTAssertTrue(IssueText.friendly(cut.errors[0]).contains("looks cut off"))
    }

    // U6: the overview's rows carry the set's target, never the exercise's note.
    func testTheOverviewRowLeavesTheNoteToTheExercise() {
        var plan = CoreTestSupport.plan()
        plan.days[0].exercises[0].notes = "Bar on the upper back, big breath, sit down between the knees."
        let session = CoreTestSupport.session(plan)
        XCTAssertEqual(StepCard.targetLine(session: session, step: 0, notes: false),
                       "Aim 8–12 reps · 60 kg")
        XCTAssertEqual(StepCard.targetLine(session: session, step: 0),
                       "Aim 8–12 reps · 60 kg · Bar on the upper back, big breath, sit down between the knees.")
    }

    // MARK: - U2 (D56): nothing unreachable

    // U8: the stage is said once — the small line is nil when it would only repeat it.
    func testTheProgressLineIsNilWhenItWouldRepeatTheStage() throws {
        let now = CoreTestSupport.now
        var engine = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3))   // no warm-up: working
        let working = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now))
        XCTAssertEqual(working.stage.title, "Exercise 1 of 1 · Set 1 of 3")
        XCTAssertEqual(working.progress, working.stage.title, "the audit saw this printed twice")
        XCTAssertNil(working.progressLine)

        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        let resting = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                        now: now.addingTimeInterval(1)))
        XCTAssertEqual(resting.stage.title, "Resting")
        XCTAssertEqual(resting.progressLine, "Exercise 1 of 1 · Set 2 of 3")

        // A superset member's line names the round and the exercise, which the stage does not.
        let grouped = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3, secondExercise: true, group: "A"))
        let member = try XCTUnwrap(WorkoutScreen.model(active: grouped.active, history: [], now: now))
        let line = try XCTUnwrap(member.progressLine)
        XCTAssertNotEqual(line, member.stage.title)
        XCTAssertTrue(line.contains("Round"), line)
    }

    // MARK: - U3 (D57): the first five minutes

    // U15: a fresh install has no warm-up; a settings file written before v1.2 still does.
    func testTheWarmUpIsOffForAFreshInstallAndOnForAnOldFile() throws {
        XCTAssertEqual(Settings().warmUpSeconds, 0)
        let old = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.warmUpSeconds, Settings.warmUpBeforeV16)
        XCTAssertEqual(old.warmUpSeconds, 300, "D32's phones keep their five minutes")
        let off = try JSONDecoder().decode(Settings.self, from: Data(#"{"warmUpSeconds": 0}"#.utf8))
        XCTAssertEqual(off.warmUpSeconds, 0, "a file that says Off means Off")
        XCTAssertEqual(old.transitionRestSeconds, 120, "the walk between exercises is unchanged")
    }

    // U16: during the warm-up the primary button starts the set; it never logs one.
    func testTheWarmUpsPrimaryButtonStartsTheFirstSet() throws {
        let now = CoreTestSupport.now
        XCTAssertEqual(WorkoutScreen.primary(work: .reps(.fixed(5)), running: false, resting: .warmUp),
                       PrimaryAction(title: "Start first set", kind: .startSet))
        XCTAssertEqual(WorkoutScreen.primary(work: .duration(seconds: 45), running: false, resting: .warmUp).kind,
                       .startSet, "a hold's card starts the same way")
        XCTAssertEqual(WorkoutScreen.primary(work: .reps(.fixed(5)), running: false, resting: .betweenSets),
                       PrimaryAction(title: "Log set", kind: .log), "a set has been done by then")
        XCTAssertEqual(WorkoutScreen.primary(work: .reps(.fixed(5)), running: false, resting: .betweenExercises).kind, .log)

        var engine = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3), settings: Settings(warmUpSeconds: 300))
        let warming = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now))
        XCTAssertEqual(warming.stage, .warmUp)
        XCTAssertEqual(warming.primary.kind, .startSet)
        engine.apply(.skipRest, now: now.addingTimeInterval(10))
        let working = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                        now: now.addingTimeInterval(10)))
        XCTAssertEqual(working.primary, PrimaryAction(title: "Log set", kind: .log))
    }

    // U17: the first empty weight explains itself, until it has a value or a history.
    func testTheFirstEmptyWeightExplainsItself() throws {
        let now = CoreTestSupport.now
        let weightless = CoreTestSupport.plan(weight: nil)
        var engine = CoreTestSupport.engine(weightless)
        let first = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now))
        XCTAssertEqual(first.inputs.weight, "")
        XCTAssertEqual(first.inputs.weightHint, WorkoutText.weightHint)
        XCTAssertTrue(WorkoutText.weightHint.hasPrefix("Type the weight"))

        // Typed once, carried forward: the hint is gone from the second set.
        engine.apply(.logSet(step: 0, result: .reps(count: 8, weight: 40)), now: now)
        engine.apply(.skipRest, now: now.addingTimeInterval(1))
        let second = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                       now: now.addingTimeInterval(1)))
        XCTAssertEqual(second.inputs.weight, "40")
        XCTAssertNil(second.inputs.weightHint)

        // A history takes it away, and a bodyweight exercise never shows it.
        let history = [CoreTestSupport.completed([10, 10, 8], weights: [40, 40, 40], plan: weightless)]
        let known = try XCTUnwrap(WorkoutScreen.model(active: CoreTestSupport.engine(weightless).active,
                                                      history: history, now: now))
        XCTAssertNil(known.inputs.weightHint)
        let body = try XCTUnwrap(WorkoutScreen.model(
            active: CoreTestSupport.engine(CoreTestSupport.plan(weight: nil, bodyweight: true)).active,
            history: [], now: now))
        XCTAssertFalse(body.inputs.showsWeight)
        XCTAssertNil(body.inputs.weightHint)
    }

    // U18: the import says whether the plan named its unit, so the review can ask.
    func testTheImportSaysWhetherTheUnitWasStated() {
        let exercises = #"[{"name":"Bench Press","sets":3,"reps":"8-12","repRange":"8-12"}]"#
        let stated = PlanImport.run(#"{"schemaVersion":1,"name":"P","units":"lb","days":[{"name":"A","exercises":"# + exercises + "}]}")
        XCTAssertNotNil(stated.plan, "\(stated.issues)")
        XCTAssertTrue(stated.unitsStated)
        XCTAssertEqual(stated.plan?.units, .lb)
        let silent = PlanImport.run(#"{"schemaVersion":1,"name":"P","days":[{"name":"A","exercises":"# + exercises + "}]}",
                                    settings: Settings(units: .kg))
        XCTAssertNotNil(silent.plan, "\(silent.issues)")
        XCTAssertFalse(silent.unitsStated, "the setting filled it in; the review should ask")
        XCTAssertEqual(silent.plan?.units, .kg)
        XCTAssertTrue(PlanImport.run("not a plan").unitsStated, "a refusal says nothing about units")
    }

    // U19: the picker recommends Full Body, and its sentence names controls on the screen it sends you to.
    func testThePickerRecommendsAndPointsBack() {
        XCTAssertEqual(BuiltInPlans.entry(BuiltInPlans.recommendedId)?.name, "Full Body")
        XCTAssertTrue(BuiltInPlans.all.contains { $0.id == BuiltInPlans.recommendedId })
        XCTAssertTrue(BuiltInPlans.buildYourOwn.contains("Add plan"))
        XCTAssertTrue(BuiltInPlans.buildYourOwn.contains("Copy prompt"))
        XCTAssertTrue(BuiltInPlans.buildYourOwn.contains("Create with a chatbot"))
    }

    // U20: Home led with the workout on a rest day (D57) until v1.8, whose D71 reverses it on
    // Today: a rest day says rest, and the workout is one tap away on the strip.
    func testARestDaySaysRestAndTheWorkoutIsOneTapAway() throws {
        // Push / Pull / Legs / rest with Legs done on the 7th: the 8th is a rest day, Push is the 9th.
        var library = PlanLibrary()
        library.save(rotation(anchor: 7, position: 2), makeActive: true)
        let card = HomeStart.current(library: library, now: day(8), calendar: calendar)
        XCTAssertEqual(card.title, "Rest")
        XCTAssertEqual(card.buttonTitle, "No exercise Today")
        XCTAssertNil(card.sentence)
        XCTAssertNil(card.missed)
        let push = HomeStart.current(library: library, now: day(8), calendar: calendar, showing: 1)
        XCTAssertEqual(push.title, "Push")
        XCTAssertEqual(push.buttonTitle, "Start Tomorrow's Push")
        // The weekday case is HomeAndAddPlanTests' O63.
    }

    // U21: the Summary says what comes next, from the schedule after the rotation advanced.
    func testTheSummarySaysWhatComesNext() throws {
        let target = SetTarget(work: .reps(.fixed(5)), weight: 100, restSeconds: 90)
        func day(_ name: String, _ weekday: Weekday? = nil) -> Day {
            Day(name: name, weekday: weekday, exercises: [Exercise(name: "\(name) Press", sets: [target])])
        }
        func session(_ plan: Plan, dayIndex: Int, on date: Date) throws -> Session {
            var session = try XCTUnwrap(Session.start(plan: plan, dayIndex: dayIndex, now: date))
            session.endedAt = date.addingTimeInterval(1800)
            return session
        }

        // A rotation: Push done on Wednesday the 9th, Pull is tomorrow.
        var ppl = Plan(name: "PPL", units: .kg, schedule: .rotation,
                       days: [day("Push"), day("Pull"), day("Legs")],
                       importedAt: self.day(1), sourceText: "", cycle: [.day(0), .day(1), .day(2), .rest])
        var library = PlanLibrary()
        library.save(ppl, makeActive: true)
        let push = try session(library.plans[0], dayIndex: 0, on: self.day(9))
        PlanSchedule.advance(&library.plans[0], completedDayName: "Push", on: self.day(9), calendar: calendar)
        XCTAssertEqual(SummaryText.next(after: push, library: library, now: self.day(9), calendar: calendar),
                       "Next: Pull, tomorrow")

        // With a rest day in between, the weekday is named.
        ppl.cycle = [.day(0), .rest, .day(1), .rest, .day(2), .rest]
        library.plans[0] = ppl
        PlanSchedule.advance(&library.plans[0], completedDayName: "Push", on: self.day(9), calendar: calendar)
        XCTAssertEqual(SummaryText.next(after: push, library: library, now: self.day(9), calendar: calendar),
                       "Next: Pull, Friday")

        // A week or more away is a date.
        ppl.cycle = [.day(0), .rest, .rest, .rest, .rest, .rest, .rest, .rest]
        library.plans[0] = ppl
        PlanSchedule.advance(&library.plans[0], completedDayName: "Push", on: self.day(9), calendar: calendar)
        let far = try XCTUnwrap(SummaryText.next(after: push, library: library, now: self.day(9), calendar: calendar))
        XCTAssertTrue(far.hasPrefix("Next: Push, on "), far)

        // A weekday plan: Upper on Monday the 7th, Lower is Thursday.
        let weekly = Plan(name: "UL", units: .kg, schedule: .weekday,
                          days: [day("Upper", .monday), day("Lower", .thursday)],
                          importedAt: self.day(1), sourceText: "", cycle: [])
        var weekLibrary = PlanLibrary()
        weekLibrary.save(weekly, makeActive: true)
        let upper = try session(weekLibrary.plans[0], dayIndex: 0, on: self.day(7))
        XCTAssertEqual(SummaryText.next(after: upper, library: weekLibrary, now: self.day(7), calendar: calendar),
                       "Next: Lower, Thursday")

        // A plan that is gone, or a session that never had one, says nothing.
        weekLibrary.plans = []
        XCTAssertNil(SummaryText.next(after: upper, library: weekLibrary, now: self.day(7), calendar: calendar))
        var imported = push
        imported.planId = nil
        XCTAssertNil(SummaryText.next(after: imported, library: library, now: self.day(9), calendar: calendar))
    }

    // MARK: - U5 (D59): hierarchy

    // U24: the row that carries Undo is the step just logged, while the undo is still valid.
    func testTheUndoRowIsTheStepJustLogged() throws {
        let now = CoreTestSupport.now
        var engine = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3))
        XCTAssertNil(try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now)).undoStep)
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        XCTAssertEqual(try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                         now: now.addingTimeInterval(1))).undoStep, 0)
        engine.apply(.undoLog(step: 0), now: now.addingTimeInterval(2))
        XCTAssertNil(try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                       now: now.addingTimeInterval(2))).undoStep)
    }

    // U25: the idle strip says what the button will start.
    func testTheIdleStripSaysWhatFollows() throws {
        let now = CoreTestSupport.now
        // A straight exercise with 90 s of rest: the first set's card says so.
        let plan = CoreTestSupport.plan(sets: 2, secondExercise: true)
        let session = CoreTestSupport.session(plan)
        XCTAssertEqual(WorkoutScreen.idleLine(session: session, step: 0), "Rest 1:30 starts when you log")
        // The block's last set names what comes after it.
        let last = try XCTUnwrap(session.steps.lastIndex { $0.exerciseIndex == 0 })
        XCTAssertEqual(WorkoutScreen.idleLine(session: session, step: last),
                       "Then on to \(session.exercises[1].name)")
        // The day's last set has nothing to announce.
        XCTAssertNil(WorkoutScreen.idleLine(session: session, step: session.steps.count - 1))
        // And the strip carries it while working, never while resting.
        let engine = CoreTestSupport.engine(plan)
        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now))
        XCTAssertEqual(screen.strip.kind, .empty)
        XCTAssertEqual(screen.strip.title, "Rest 1:30 starts when you log")
    }

    // U26: a History row reads in words a stranger knows.
    func testTheHistoryRowIsLabelled() {
        let summary = ExerciseText.summary(CoreTestSupport.completed([10, 10, 8], weights: [60, 60, 60]))
        XCTAssertTrue(summary.hasSuffix(" min · 3 sets · 1,680 kg lifted"), summary)
        XCTAssertFalse(summary.contains(":"), "a duration is minutes, not a clock time: \(summary)")
    }


    // MARK: - U4 (D58): plain words

    // U34: the grammar itself. Every form the audit named as unreadable, said in words — and
    // the numbers a coach acts on still on the same line, in the same order.
    func testThePlainGrammar() throws {
        let range = SetTarget(work: .reps(.range(min: 4, max: 6)), weight: 100, restSeconds: 90)
        XCTAssertEqual(TargetText.target(range, range: nil, units: .kg), "Aim 4–6 reps · 100 kg")

        // A fixed count inside a range says the range: it is what is being asked of you, and
        // the prefill puts the exact number in the field.
        let fixed = SetTarget(work: .reps(.fixed(5)), weight: 100, restSeconds: 90)
        XCTAssertEqual(TargetText.target(fixed, range: RepRange(min: 4, max: 6), units: .kg),
                       "Aim 4–6 reps · 100 kg")
        XCTAssertEqual(TargetText.target(fixed, range: nil, units: .kg), "Aim 5 reps · 100 kg")

        // "AMRAP" is the audit's own example of a word nobody outside a gym knows.
        let amrap = SetTarget(work: .reps(.amrap(min: nil)), weight: 20, restSeconds: 60)
        XCTAssertEqual(TargetText.target(amrap, range: nil, units: .kg),
                       "As many reps as you can · 20 kg")
        let atLeast = SetTarget(work: .reps(.amrap(min: 10)), weight: 20, restSeconds: 60)
        XCTAssertEqual(TargetText.target(atLeast, range: nil, units: .kg),
                       "Aim at least 10 reps · 20 kg")

        // Timed work is a duration, not "45 s".
        let held = SetTarget(work: .duration(seconds: 45), weight: nil, restSeconds: 60)
        XCTAssertEqual(TargetText.target(held, range: nil, units: .kg), "For 45 seconds")
        let open = SetTarget(work: .openDuration(minSeconds: 30), weight: nil, restSeconds: 60)
        XCTAssertEqual(TargetText.target(open, range: nil, units: .kg), "For at least 30 seconds")

        // The effort target says what being "in reserve" means.
        var reserved = range
        reserved.inReserve = 2
        XCTAssertEqual(TargetText.target(reserved, range: nil, units: .kg),
                       "Aim 4–6 reps · 100 kg · stop 2 short of failure")

        // An exercise in one line: sets, not multiplication; a drop said as what it is.
        let exercise = Exercise(name: "Curl", repRange: RepRange(min: 8, max: 12),
                                sets: Array(repeating: SetTarget(work: .reps(.range(min: 8, max: 12)),
                                                                 weight: 60, restSeconds: 90),
                                            count: 3))
        XCTAssertEqual(TargetText.summary(exercise, units: .kg), "3 sets of 8–12 reps · 60 kg")
        let dropped = Exercise(name: "Curl", sets: [
            SetTarget(work: .reps(.fixed(10)), weight: 20, restSeconds: 60,
                      drops: [DropTarget(work: .reps(.amrap(min: nil)), weight: 15)])])
        XCTAssertEqual(TargetText.summary(dropped, units: .kg),
                       "1 set of 10 reps · 20 kg · then lighter, as many as you can")
    }

    // U34: and on the workout screen — the set row's own line, the pairing, the lighter set.
    func testThePlainGrammarOnTheCard() throws {
        let now = CoreTestSupport.now
        let grouped = CoreTestSupport.plan(sets: 2, secondExercise: true,
                                           drops: [DropTarget(work: .reps(.amrap(min: nil)), weight: 40)],
                                           group: "A")
        let session = CoreTestSupport.session(grouped)
        // "A" is a label for a pair; the pair is the fact.
        XCTAssertEqual(StepCard.setLine(session: session, step: 0),
                       "Set 1 of 2 · paired with \(session.exercises[1].name)")
        let dropStep = try XCTUnwrap(session.steps.firstIndex { $0.dropIndex == 1 })
        XCTAssertTrue(StepCard.setLine(session: session, step: dropStep).hasSuffix("lighter set 1 of 1"),
                      StepCard.setLine(session: session, step: dropStep))
        // A row that names its own exercise does not also carry the pairing.
        XCTAssertEqual(StepCard.rowLabel(session: session, step: 0, naming: true),
                       "\(session.exercises[0].name) · Set 1 of 2")

        // The second line of the current row is a sentence, with its unit, and never "@". Since
        // v1.10 (D81) the Workout screen draws last time as a line over a cell; the row is Core's.
        let plan = CoreTestSupport.plan(sets: 3)
        let history = [CoreTestSupport.completed([9, 9, 9], weights: [60, 60, 60])]
        let rows = StepCard.setRows(session: CoreTestSupport.engine(plan).session, step: 0, history: history)
        let last = try XCTUnwrap(rows.first { $0.isCurrent }?.lastTime)
        XCTAssertEqual(last, "Last time 9 × 60 kg")
        XCTAssertFalse(rows.contains { $0.value.contains("@") }, "no row uses @")
    }

    // U35: the coach's switch. The same session in the same app, in v1.5's forms — and the
    // setting is what chooses, so no screen decides for itself.
    func testCompactNotationRestoresTheOldForms() throws {
        let now = CoreTestSupport.now
        let plan = CoreTestSupport.plan(sets: 3)
        var history = [CoreTestSupport.completed([9, 9, 9], weights: [60, 60, 60])]
        history[0].units = .kg
        let engine = CoreTestSupport.engine(plan)

        var settings = CoreTestSupport.classic
        settings.compactNotation = true
        XCTAssertEqual(settings.wording, .compact)
        XCTAssertEqual(Settings().wording, .plain, "words are the default, on a fresh install")

        // The Overview's line reads the switch. Since v1.10 (D81) the Workout screen's exercise
        // block has no sentence to choose for: the card is the same either way.
        let session = engine.session
        XCTAssertEqual(StepCard.targetLine(session: session, step: 0, notes: false, wording: settings.wording),
                       "8–12 · 60 kg")
        XCTAssertEqual(StepCard.setRows(session: session, step: 0, history: history, wording: settings.wording)
                        .first { $0.isCurrent }?.lastTime, "last 9 @ 60")

        var plain = settings
        plain.compactNotation = false
        XCTAssertEqual(StepCard.targetLine(session: session, step: 0, notes: false, wording: plain.wording),
                       "Aim 8–12 reps · 60 kg")
        let compact = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: history,
                                                        now: now, settings: settings))
        let words = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: history,
                                                      now: now, settings: plain))
        XCTAssertEqual(compact.card, words.card, "the card has no words to choose")
        XCTAssertEqual(compact.dots, words.dots)
    }

    // U35: and it survives the launch — a setting that resets is worse than none.
    func testCompactNotationRoundTripsThroughTheStore() throws {
        var settings = Settings()
        settings.compactNotation = true
        let data = try StoreCoder.encoder.encode(settings)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("compactNotation"))
        XCTAssertTrue(try JSONDecoder().decode(Settings.self, from: data).compactNotation)

        // A file written before v1.6 does not mention it, and reads as words.
        let old = Data(#"{ "units": "kg", "defaultRestSeconds": 90 }"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Settings.self, from: old).compactNotation)
    }

    // U35: and the switch itself — Settings' toggle calls this, and a relaunch reads it back.
    @MainActor func testTheSwitchIsWrittenAndReadBack() async throws {
        let root = CoreTestSupport.makeRoot("U4Tests")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil }, practiceJSON: { nil })
        await model.load()
        XCTAssertFalse(model.settings.compactNotation)

        await model.setCompactNotation(true)
        XCTAssertTrue(model.settings.compactNotation, "the toggle's own call has to take")
        XCTAssertEqual(model.settings.wording, .compact)

        let relaunched = AppModel(store: Store(root: root), sampleJSON: { nil }, practiceJSON: { nil })
        await relaunched.load()
        XCTAssertTrue(relaunched.settings.compactNotation, "and survive the launch")

        await model.setCompactNotation(false)
        XCTAssertFalse(model.settings.compactNotation)
    }

    // U36: what the chatbot is told does not change with the app's voice. The prompt is read
    // by a machine, PROMPT.md pins it, and a plan's JSON is the same either way.
    func testThePromptIsUnaffectedByTheSetting() throws {
        var settings = Settings()
        let words = Prompts.render(settings: settings)
        settings.compactNotation = true
        XCTAssertEqual(Prompts.render(settings: settings), words)
    }
}
