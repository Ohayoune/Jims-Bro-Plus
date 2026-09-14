import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// R3 (v1.1) — Home leading with the workout (D18) and Add plan replacing the JSON editor as the
/// front door (D26): L38, M8, O63–O71.
final class HomeAndAddPlanTests: XCTestCase {
    private let now = CoreTestSupport.now

    private func makeRoot() -> URL { CoreTestSupport.makeRoot() }
    private func discard(_ root: URL) { CoreTestSupport.discard(root) }

    /// A three-day rotation whose days have different exercise counts.
    private func rotation() -> Plan {
        func day(_ name: String, _ names: [String]) -> Day {
            Day(name: name, exercises: names.map {
                Exercise(name: $0, repRange: RepRange(min: 8, max: 12),
                         sets: [SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 60, restSeconds: 90)])
            })
        }
        return Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation,
                    days: [day("Push", ["Bench Press", "Incline Press", "Lateral Raise",
                                        "Tricep Pushdown", "Plank", "Cable Fly", "Dip"]),
                           day("Pull", ["Deadlift", "Row"]),
                           day("Legs", ["Squat"])],
                    importedAt: now, sourceText: "", cycle: [.day(0), .day(1), .day(2)])
    }

    // O63/O64: the card's wording, its target and its preview, per schedule state.
    func testStartCardWordingAndPreview() throws {
        var library = PlanLibrary()
        XCTAssertEqual(HomeStart.current(library: library, now: now).title, "No plan yet")
        XCTAssertEqual(HomeStart.current(library: library, now: now).buttonTitle, "Choose a plan")
        XCTAssertTrue(HomeStart.current(library: library, now: now).isEmpty)

        library.save(rotation(), makeActive: true)
        let card = HomeStart.current(library: library, now: now)
        XCTAssertEqual(card.title, "Push")
        XCTAssertEqual(card.buttonTitle, "Start Today's Push")
        XCTAssertEqual(card.dayIndex, 0)
        XCTAssertEqual(card.planId, library.activePlanId)
        // The five names, then a count of what is left — Start is never blind (T1).
        XCTAssertEqual(card.rows.map(\.name), ["Bench Press", "Incline Press", "Lateral Raise",
                                               "Tricep Pushdown", "Plank"])
        XCTAssertEqual(card.more, 2)
        XCTAssertNil(card.clock, "no history yet, so no clock")
        XCTAssertNil(card.sentence, "D69: the plan's name and the count left with the subtitle")

        // With history for that day, the clock says how long it took last time.
        var done = CoreTestSupport.session(rotation(), start: now.addingTimeInterval(-86_400))
        done.endedAt = done.startedAt.addingTimeInterval(48 * 60)
        library.sessions = [done]
        XCTAssertEqual(HomeStart.current(library: library, now: now).clock,
                       HomeStart.Clock(minutes: "48 min", caption: "last time"))

        // A workout in progress takes over the card.
        var running = library
        running.engine = SessionEngine(session: CoreTestSupport.session(rotation(), start: now),
                                      settings: CoreTestSupport.classic,
                                       now: now)
        let inProgress = HomeStart.current(library: running, now: now.addingTimeInterval(23 * 60))
        XCTAssertEqual(inProgress.title, "Push")
        XCTAssertEqual(inProgress.buttonTitle, "Resume Push · 23 min")
        XCTAssertTrue(inProgress.isInProgress)
        XCTAssertNil(inProgress.planId, "Resume goes back to the running session, not to a day")
    }

    // O63 / L38: a weekday plan's rest day still offers the next day, by name, to start early —
    // since v1.8 (D71) one tap away on the strip, while the card itself says rest.
    func testRestDayOffersTheNextDayEarly() throws {
        let target = SetTarget(work: .reps(.fixed(5)), weight: 100, restSeconds: 180)
        let plan = Plan(name: "Upper Lower", units: .kg, schedule: .weekday,
                        days: [Day(name: "Upper", weekday: .monday,
                                   exercises: [Exercise(name: "Press", sets: [target])]),
                               Day(name: "Lower", weekday: .thursday,
                                   exercises: [Exercise(name: "Squat", sets: [target])])],
                        importedAt: now, sourceText: "", cycle: [])
        var library = PlanLibrary()
        library.save(plan, makeActive: true)

        // A Tuesday: nothing scheduled today, Thursday's Lower is next.
        let tuesday = CoreTestSupport.date(1)   // 2026-09-01 is a Tuesday
        let calendar = CoreTestSupport.utc()
        XCTAssertEqual(calendar.component(.weekday, from: tuesday), 3, "the fixture day is a Tuesday")

        // D57 (v1.6) made the workout the headline on a rest day; D71 (v1.8) reverses that on
        // Today: the card says rest, and Thursday's Lower is the strip's third square, whose
        // button says when.
        let card = HomeStart.current(library: library, now: tuesday, calendar: calendar)
        XCTAssertEqual(card.title, "Rest")
        XCTAssertEqual(card.buttonTitle, "No exercise Today")
        XCTAssertNil(card.dayIndex)
        XCTAssertTrue(card.rows.isEmpty)
        XCTAssertNil(card.sentence)
        let lower = HomeStart.current(library: library, now: tuesday, calendar: calendar, showing: 2)
        XCTAssertEqual(lower.title, "Lower")
        XCTAssertEqual(lower.buttonTitle, "Start Thursday's Lower")
        XCTAssertEqual(lower.dayIndex, 1)
        XCTAssertEqual(lower.rows.map(\.name), ["Squat"], "the day you would start is the one previewed")
        XCTAssertNil(lower.sentence)

        // And on its own day the same plan simply starts it.
        let monday = CoreTestSupport.date(7)
        XCTAssertEqual(calendar.component(.weekday, from: monday), 2)
        let onDay = HomeStart.current(library: library, now: monday, calendar: calendar)
        XCTAssertEqual(onDay.title, "Upper")
        XCTAssertEqual(onDay.buttonTitle, "Start Today's Upper")
    }

    // O65: the week strip is the same projection the month grid uses, for seven days.
    func testWeekStripMatchesTheMonthGrid() throws {
        var library = PlanLibrary()
        library.save(rotation(), makeActive: true)
        let calendar = CoreTestSupport.utc()
        // 2026-10-01 is a Thursday, so this week straddles September and October.
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!

        let week = CalendarProjection.week(containing: today, activePlan: library.activePlan,
                                           sessions: [], swaps: [], today: today, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: week[0].date), calendar.firstWeekday)
        XCTAssertTrue(week.contains { calendar.isDate($0.date, inSameDayAs: today) })
        XCTAssertEqual(Set(week.map { calendar.component(.month, from: $0.date) }), [9, 10],
                       "a week across a month boundary carries both months' days")

        // Every day the week reports matches what the month grid says about the same day.
        for day in week {
            let month = CalendarProjection.entries(month: day.date, activePlan: library.activePlan,
                                                    sessions: [], swaps: [], today: today, calendar: calendar)
            let same = try XCTUnwrap(month.first { calendar.isDate($0.date, inSameDayAs: day.date) })
            XCTAssertEqual(day.entry, same.entry, "\(day.date) disagrees with the month grid")
        }
    }

    // O66 (the week's line) moved to HistoryTests as T10, with the calendar (D63).

    // O68: the review sheet shows what the chatbot actually wrote, per set — in the
    // compact notation, which since D58 (v1.6) is Settings' switch. U34 pins the plain
    // grammar that replaced it as the default.
    func testExerciseSummaryShowsPerSetVariation() throws {
        func sets(_ weights: [Double?], work: WorkTarget = .reps(.range(min: 8, max: 12))) -> [SetTarget] {
            weights.map { SetTarget(work: work, weight: $0, restSeconds: 90) }
        }
        let straight = Exercise(name: "Bench", repRange: RepRange(min: 8, max: 12), sets: sets([60, 60, 60]))
        XCTAssertEqual(TargetText.summary(straight, units: .kg, wording: .compact), "3 × 8–12 · 60 kg")

        // The defect this replaced: v1 repeated the first set and hid the pyramid entirely.
        let pyramid = Exercise(name: "Incline", repRange: RepRange(min: 8, max: 12), sets: sets([24, 26, 28]))
        XCTAssertEqual(TargetText.summary(pyramid, units: .kg, wording: .compact), "3 × 8–12 · 24 / 26 / 28 kg")

        let varied = Exercise(name: "Incline", sets: [
            SetTarget(work: .reps(.fixed(12)), weight: 24, restSeconds: 90),
            SetTarget(work: .reps(.fixed(10)), weight: 26, restSeconds: 90),
            SetTarget(work: .reps(.fixed(8)), weight: 28, restSeconds: 90)])
        XCTAssertEqual(TargetText.summary(varied, units: .kg, wording: .compact), "12 · 24 / 10 · 26 / 8 · 28 kg")

        let bodyweight = Exercise(name: "Push-Up", bodyweight: true, sets: sets([nil, nil]))
        XCTAssertEqual(TargetText.summary(bodyweight, units: .kg, wording: .compact), "2 × 8–12")
        XCTAssertEqual(TargetText.summary(Exercise(name: "Empty", sets: []), units: .kg, wording: .compact), "No sets")

        let dropped = Exercise(name: "Curl", sets: [
            SetTarget(work: .reps(.fixed(10)), weight: 20, restSeconds: 60,
                      drops: [DropTarget(work: .reps(.amrap(min: nil)), weight: 15)])])
        XCTAssertTrue(TargetText.summary(dropped, units: .kg, wording: .compact).hasSuffix("· 1 drop"),
                      TargetText.summary(dropped, units: .kg, wording: .compact))
    }

    // O69: warnings worth reading are shown; tidying goes behind Details.
    func testWarningsSplitIntoMaterialAndCleanup() throws {
        func warning(_ code: String) -> Issue {
            Issue(severity: .warning, code: code, path: "days[0]", message: code)
        }
        let material = ["W_WEIGHT_UNIT_IGNORED", "W_BODYWEIGHT_WEIGHT_IGNORED", "W_GROUP_SPLIT",
                        "W_SCHEDULE_INFERRED", "W_CYCLE_IGNORED", "W_REPRANGE_IGNORED",
                        "W_DROPS_IGNORED", "W_WEEKDAY_IGNORED"]
        let cleanup = ["W_CURLY_QUOTES_FIXED", "W_SURROUNDING_TEXT", "W_UNKNOWN_FIELD",
                       "W_NAME_TRUNCATED", "W_WEIGHT_ROUNDED", "W_DEFAULT_NAME"]
        for code in material { XCTAssertTrue(IssueText.isMaterial(warning(code)), code) }
        for code in cleanup { XCTAssertFalse(IssueText.isMaterial(warning(code)), code) }

        let split = IssueText.split((material + cleanup).map(warning))
        XCTAssertEqual(split.material.count, material.count)
        XCTAssertEqual(split.cleanup.count, cleanup.count)
        // An unrecognized warning is shown rather than hidden: silence is the worse mistake.
        XCTAssertTrue(IssueText.isMaterial(warning("W_SOMETHING_NEW")))
    }

    // M8 / O70: every error code has a plain sentence, and it says where the problem is.
    func testEveryErrorCodeHasAFriendlySentence() throws {
        for code in IssueText.knownErrorCodes {
            let issue = Issue(severity: .error, code: code, path: "", message: "raw decoder text")
            let sentence = IssueText.friendly(issue)
            XCTAssertFalse(sentence.isEmpty, code)
            XCTAssertFalse(sentence.contains(code), "\(code) leaks its code into the sentence")
            XCTAssertNotEqual(sentence, "raw decoder text", "\(code) still shows the raw message")
            XCTAssertTrue(sentence.hasSuffix(".") || sentence.hasSuffix("\"),"),
                          "\(code) should read as a sentence: \(sentence)")
        }
        // A code with no sentence of its own still says something true.
        XCTAssertEqual(IssueText.friendly(Issue(severity: .error, code: "E_FROM_THE_FUTURE",
                                                path: "", message: "raw decoder text")),
                       "raw decoder text")

        // The sentence leads with where it is.
        XCTAssertEqual(IssueText.location("days[0].exercises[1].sets[1]"),
                       "Day 1, exercise 2, set 2")
        XCTAssertEqual(IssueText.location("days[2].weekday"), "Day 3")
        XCTAssertEqual(IssueText.location("cycle[1]"), "repeat block entry 2")
        XCTAssertNil(IssueText.location("units"))
        XCTAssertEqual(IssueText.friendly(Issue(severity: .error, code: "E_TARGET_MISSING",
                                                path: "days[0].exercises[1].sets[1]",
                                                message: "no reps or duration")),
                       "Day 1, exercise 2, set 2 needs either a rep target or a duration.")
    }

    // M8: the codes the importer can actually produce all have a sentence — no code is forgotten.
    func testEveryCodeTheImporterEmitsIsCovered() throws {
        let known = Set(IssueText.knownErrorCodes)
        var emitted: Set<String> = []
        for fixture in try FixtureLoader.manifest().fixtures where fixture.outcome == .invalid {
            let result = PlanImport.run(try FixtureLoader.text(fixture.file), settings: Settings(),
                                        now: now)
            emitted.formUnion(result.issues.filter { $0.severity == .error }.map(\.code))
        }
        XCTAssertFalse(emitted.isEmpty, "the invalid fixtures must actually produce errors")
        XCTAssertTrue(emitted.isSubset(of: known),
                      "no sentence for: \(emitted.subtracting(known).sorted())")
    }

    // O71: the practice plan is a real plan, imported the normal way.
    @MainActor func testPracticePlanImportsAndActivates() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let json = try practiceJSON()
        let model = AppModel(store: Store(root: root), scheduler: RecordingAlerts(),
                             alerts: RecordingAlerts(), sampleJSON: { nil },
                             practiceJSON: { json })
        await model.load()

        let result = await model.importPracticePlan(now: now)
        XCTAssertTrue(result.issues.filter { $0.severity == .error }.isEmpty,
                      "\(result.issues)")
        let plan = try XCTUnwrap(result.plan)
        XCTAssertEqual(plan.days.count, 1)
        let day = try XCTUnwrap(plan.days.first)
        XCTAssertEqual(day.exercises.count, 3)
        XCTAssertEqual(day.exercises.filter(\.bodyweight).count, 1, "one bodyweight exercise")
        XCTAssertTrue(day.exercises.allSatisfy { $0.sets.allSatisfy { $0.restSeconds == 60 } })
        XCTAssertTrue(day.exercises.allSatisfy { set in
            Set(set.sets.map(\.weight)).count == 1
        }, "straight sets only — this is the one you run to learn the app")
        XCTAssertEqual(model.activePlanId, plan.id, "it becomes the current plan")

        // And it actually runs: a short session with no drops, groups or timed work.
        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now))
        XCTAssertEqual(session.steps.count, 6)
        XCTAssertTrue(session.steps.allSatisfy { $0.dropIndex == 0 })
        XCTAssertTrue(session.exercises.allSatisfy { $0.group == nil })
    }

    /// The bundled practice plan itself, not a copy of it.
    private func practiceJSON() throws -> String {
        try FixtureLoader.appResource("PracticePlan", extension: "json")
    }
}
