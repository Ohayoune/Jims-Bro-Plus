import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// T1 (v1.7) — Today is one card (D61): the one message, the ··· items, the exercise block
/// that is the preview, and the empty card's two choices. T1–T4. S1 (v1.8) — nothing without a
/// cue (D69): no sentence on a day's card, the rows and their sets, the step line. TS1–TS4.
/// S2 (v1.8) — the week is the strip (D70): seven squares from the calendar's own projection, a
/// tapped square's card and its button's words, Another day gone, nothing stored. TS6–TS10.
/// S3 (v1.8) — a rest day says rest (D71): the rest card, the next workout one tap away, the
/// message still speaking, and Done Today once today's workout is done. TS13–TS15, TS17.
/// Q3 (v1.9) — the ··· speaks in squares (D75): Change plan with the plan's cycle, Change *day*'s
/// exercises with the shown day's square, the progression gone from Today, the rows the
/// preview and nothing more. TQ21–TQ22 (T2 and T3 rewritten; TS4 removed with the step line).
final class TodayTests: XCTestCase {
    private let calendar = CoreTestSupport.utc()

    private func day(_ n: Int) -> Date { CoreTestSupport.date(n) }

    /// Push (7 exercises) / Pull (2) / Legs (1) / rest, imported on the 1st. `anchor` is the
    /// day Push was last done, so the 8th is Pull and the 9th is Legs.
    private func rotation(anchor: Int? = nil, progression: Progression? = nil) -> Plan {
        func day(_ name: String, _ names: [String]) -> Day {
            Day(name: name, exercises: names.map {
                Exercise(name: $0, repRange: RepRange(min: 8, max: 12),
                         sets: [SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 60, restSeconds: 90)])
            })
        }
        var plan = Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation,
                        days: [day("Push", ["Bench Press", "Incline Press", "Lateral Raise",
                                            "Tricep Pushdown", "Plank", "Cable Fly", "Dip"]),
                               day("Pull", ["Deadlift", "Row"]),
                               day("Legs", ["Squat"])],
                        importedAt: self.day(1), sourceText: "",
                        cycle: [.day(0), .day(1), .day(2), .rest])
        plan.cyclePosition = anchor.map { _ in 0 }
        plan.cycleAnchor = anchor.map { calendar.startOfDay(for: self.day($0)) }
        plan.progression = progression
        return plan
    }

    /// One week for Squat, started on the 1st and already earned — over by the 8th in either
    /// mode (D53: by the calendar, or by the step).
    private func finishedByTheNinth() -> Progression {
        var entry = ProgressionEntry(dayName: "Legs", exerciseName: "Squat", weeks: [ProgressionWeek(weight: 100)])
        entry.step = 1
        return Progression(startDate: calendar.startOfDay(for: day(1)), weeks: 1, entries: [entry])
    }

    /// A library holding one plan. Fresh each time: saving a second plan of the same name is
    /// a conflict the library cancels (§6.8), so a scenario never reuses another's library.
    private func library(_ plan: Plan) -> PlanLibrary {
        var library = PlanLibrary()
        library.save(plan, makeActive: true)
        return library
    }

    private func card(_ library: PlanLibrary, on n: Int, notificationsOff: Bool = false,
                      missedDismissed: Bool = false, showing: Int = 0) -> HomeStart {
        HomeStart.current(library: library, now: day(n), calendar: calendar,
                          notificationsOff: notificationsOff, missedDismissed: missedDismissed,
                          showing: showing)
    }

    /// Mon Push (Bench Press, 3 sets) / Wed Pull (Row) / Fri Legs (Squat): a weekday plan, so
    /// the strip's seven days come from the days' weekdays. September 2026 starts on a Tuesday:
    /// the 14th is a Monday.
    private func weekdayPlan() -> Plan {
        let set = SetTarget(work: .reps(.fixed(5)), weight: 100, restSeconds: 180)
        func day(_ name: String, _ weekday: Weekday, _ names: [String], sets: Int = 1) -> Day {
            Day(name: name, weekday: weekday,
                exercises: names.map { Exercise(name: $0, sets: Array(repeating: set, count: sets)) })
        }
        return Plan(name: "Push Pull Legs", units: .kg, schedule: .weekday,
                    days: [day("Push", .monday, ["Bench Press"], sets: 3),
                           day("Pull", .wednesday, ["Row"]),
                           day("Legs", .friday, ["Squat"])],
                    importedAt: self.day(1), sourceText: "", cycle: [])
    }

    // T1: the one message, by priority — missed > finished progression > notifications off —
    // and never two.
    func testAtMostOneMessage() throws {
        XCTAssertNil(card(PlanLibrary(), on: 9, notificationsOff: true).message, "no plan: no message")

        // An ordinary day says nothing; notifications off is the lowest message.
        let ordinary = library(rotation())
        XCTAssertNil(card(ordinary, on: 9).message)
        XCTAssertEqual(card(ordinary, on: 9, notificationsOff: true).message, .notificationsOff)

        // A progression that has run its course outranks notifications off.
        let finished = card(library(rotation(progression: finishedByTheNinth())), on: 9, notificationsOff: true)
        XCTAssertTrue(finished.progressionFinished)
        XCTAssertEqual(finished.message, .progressionFinished)

        // A missed workout outranks both — until it is dismissed, when the next one speaks.
        let both = library(rotation(anchor: 7, progression: finishedByTheNinth()))
        let missed = card(both, on: 9, notificationsOff: true)
        let expected = try XCTUnwrap(missed.missed)
        XCTAssertEqual(expected.dayName, "Pull")
        XCTAssertEqual(missed.message, .missed(expected))
        XCTAssertTrue(missed.progressionFinished, "the other message is still true, just not shown")
        XCTAssertEqual(card(both, on: 9, notificationsOff: true, missedDismissed: true).message,
                       .progressionFinished)
        let missedOnly = library(rotation(anchor: 7))
        XCTAssertEqual(card(missedOnly, on: 9, notificationsOff: true, missedDismissed: true).message,
                       .notificationsOff)
        XCTAssertNil(card(missedOnly, on: 9, missedDismissed: true).message)

        // Each reads as it read in v1.6, with the actions it had.
        XCTAssertTrue(HomeStart.Message.missed(expected).text.hasPrefix("Pull was due "))
        XCTAssertEqual(HomeStart.Message.missed(expected).actions, ["Do it now", "Dismiss"])
        XCTAssertEqual(HomeStart.Message.progressionFinished.text, "Your progression has run its course.")
        XCTAssertEqual(HomeStart.Message.progressionFinished.actions, ["Plan the next one"])
        XCTAssertEqual(HomeStart.Message.notificationsOff.text,
                       "Notifications are off, so alerts only sound while the app is open.")
        XCTAssertEqual(HomeStart.Message.notificationsOff.actions, [])
    }

    // T2, TQ21 (D75, v1.9): the ··· — Change plan with the plan's cycle, then Change *day*'s
    // exercises with the shown day's name and square; while a session is open, Change plan and
    // Discard workout; nothing at all with no plan. (Another day was the first item until v1.8,
    // D70; Plan a progression joined while D50 offered it until v1.9, D75.)
    func testAlternatives() throws {
        XCTAssertEqual(card(PlanLibrary(), on: 9).alternatives, [], "no plan: no ···")

        // Push Pull Legs Rest: the cycle as written, grey (nil) for rest.
        let cycle: [DayColour?] = [.green, .orange, .purple, nil]
        let anchored = library(rotation(anchor: 7))
        let legs = card(anchored, on: 9)
        XCTAssertEqual(legs.title, "Legs")
        XCTAssertEqual(legs.alternatives, [.changePlan(cycle: cycle),
                                           .changeExercises(dayName: "Legs", colour: .purple, outlined: false)])
        // A tapped square names its day — D85 (v1.10): after the day, "Change Rest" on a grey
        // square — and brings its square.
        XCTAssertEqual(card(anchored, on: 9, showing: 1).alternatives,
                       [.changePlan(cycle: cycle), .changeExercises(dayName: "Rest", colour: nil, outlined: false)],
                       "a rest day's date can take a workout too")
        XCTAssertEqual(card(anchored, on: 9, showing: 2).alternatives,
                       [.changePlan(cycle: cycle), .changeExercises(dayName: "Push", colour: .green, outlined: false)])

        // A one-day plan, before and after every exercise has history — what D50 offered Plan a
        // progression on until v1.9: the same two items.
        let oneDay = CoreTestSupport.plan()
        var single = library(oneDay)
        let two: [HomeStart.Alternative] = [.changePlan(cycle: [.green]),
                                            .changeExercises(dayName: "Push", colour: .green, outlined: false)]
        XCTAssertEqual(card(single, on: 9).alternatives, two)
        single.sessions = [CoreTestSupport.completed(plan: oneDay)]
        XCTAssertEqual(card(single, on: 9).alternatives, two)

        // Today's workout done: nothing about the day can change, so Change plan alone.
        single.sessions = [CoreTestSupport.completed(plan: oneDay, start: day(9))]
        let done = card(single, on: 9)
        XCTAssertEqual(done.buttonTitle, HomeStart.doneTitle)
        XCTAssertEqual(done.alternatives, [.changePlan(cycle: [.green])])

        // While a session is open the menu is v1.8's — Change plan, then Discard — on the
        // session's card and on a tapped square's alike.
        let plan = rotation()
        var running = library(plan)
        running.engine = SessionEngine(session: CoreTestSupport.session(plan, start: day(9)),
                                       settings: CoreTestSupport.classic, now: day(9))
        let inProgress = card(running, on: 9)
        XCTAssertTrue(inProgress.isInProgress)
        XCTAssertEqual(inProgress.alternatives, [.changePlan(cycle: cycle), .discardWorkout])
        XCTAssertEqual(card(running, on: 9, showing: 2).alternatives,
                       [.changePlan(cycle: cycle), .discardWorkout])

        // The titles the menu shows.
        XCTAssertEqual(HomeStart.Alternative.changePlan(cycle: cycle).title, "Change plan")
        XCTAssertEqual(HomeStart.Alternative.changeExercises(dayName: "Push", colour: .green, outlined: false).title,
                       "Change Push")
        XCTAssertEqual(HomeStart.Alternative.discardWorkout.title, "Discard workout")
    }

    // T3: the exercise block is the preview, and says so to VoiceOver — and since D75 (v1.9)
    // it is nothing more: its label no longer ends "Opens Push".
    func testExerciseBlockIsThePreview() throws {
        let plan = rotation()
        let push = card(library(plan), on: 1)
        XCTAssertEqual(push.title, "Push")
        XCTAssertEqual(push.exerciseLabel,
                       "Exercises: Bench Press, Incline Press, Lateral Raise, Tricep Pushdown, Plank, and 2 more")

        // Fewer than five: no "and N more".
        let legs = card(library(rotation(anchor: 7)), on: 9)
        XCTAssertEqual(legs.title, "Legs")
        XCTAssertEqual(legs.exerciseLabel, "Exercises: Squat")

        // In progress the block still stands, from the session, and the clock says how long so
        // far (D69, v1.8); Resume still goes to the session, not to a day.
        var running = library(plan)
        running.engine = SessionEngine(session: CoreTestSupport.session(plan, start: day(9)),
                                       settings: CoreTestSupport.classic, now: day(9))
        let inProgress = HomeStart.current(library: running, now: day(9).addingTimeInterval(23 * 60),
                                           calendar: calendar)
        XCTAssertEqual(inProgress.clock, HomeStart.Clock(minutes: "23 min", caption: "so far"))
        XCTAssertNil(inProgress.sentence)
        XCTAssertEqual(inProgress.buttonTitle, "Resume Push · 23 min")
        XCTAssertEqual(inProgress.rows.count, 5)
        XCTAssertEqual(inProgress.more, 2)
        XCTAssertEqual(inProgress.exerciseLabel,
                       "Exercises: Bench Press, Incline Press, Lateral Raise, Tricep Pushdown, Plank, and 2 more")
        XCTAssertNil(inProgress.planId)
        XCTAssertNil(inProgress.dayIndex)
    }

    // T4: the empty card — two choices where there were three.
    func testEmptyCard() throws {
        let empty = card(PlanLibrary(), on: 9)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.title, "No plan yet")
        XCTAssertEqual(empty.sentence, "Choose a built-in plan to start today, or have a chatbot write yours.")
        XCTAssertNil(empty.clock)
        XCTAssertEqual(empty.buttonTitle, "Choose a plan")
        XCTAssertEqual(empty.buttonTitle, Introduction.choosePlan, "the intro's button says the same")
        XCTAssertEqual(empty.link, "Try a short practice workout")
        XCTAssertEqual(empty.alternatives, [])
        XCTAssertNil(empty.message)
        XCTAssertTrue(empty.rows.isEmpty)
        XCTAssertNil(empty.exerciseLabel)

        // Only the empty card has the link.
        XCTAssertNil(card(library(rotation()), on: 9).link)
    }

    // T7 (D62): the tab bar is SPEC §4.0's list — Today · History, in that order — and the app
    // draws `AppTab.allCases` and nothing else, so a third tab needs SPEC's word first.
    func testTheTabsAreSpecsList() throws {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Today", "History"])
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["today", "history"])
        let spec = try FixtureLoader.requiredDoc("docs/SPEC.md")
        let root = try FixtureLoader.requiredDoc("JimmsBro/RootView.swift")
        let rule = try XCTUnwrap(spec.components(separatedBy: "\n").first(where: { $0.hasPrefix("- Tab bar with ") }),
                                 "SPEC §4.0 no longer has its tab rule")
        // The rule's first bold run is the list.
        let list = try XCTUnwrap(rule.components(separatedBy: "**").dropFirst().first)
        XCTAssertEqual(list.components(separatedBy: " · "), AppTab.allCases.map(\.title))
        XCTAssertTrue(root.contains("ForEach(AppTab.allCases"), "RootView no longer draws AppTab's list")
        XCTAssertEqual(root.components(separatedBy: ".tabItem").count, 2, "a tab drawn outside AppTab's list")
    }

    // TS1 (D69): a day's card carries no sentence — no plan name, no "Planned for", no count —
    // on a workout day, on a rest day (which says rest since D71) and the workout tapped from
    // it, and mid-session.
    func testADaysCardCarriesNoSentence() throws {
        XCTAssertFalse(Mirror(reflecting: card(PlanLibrary(), on: 9)).children.contains { $0.label == "subtitle" },
                       "HomeStart has no subtitle")

        // A one-day plan with last time's workout: the clock, not a fragment.
        let oneDay = CoreTestSupport.plan()
        var trained = library(oneDay)
        trained.sessions = [CoreTestSupport.completed(plan: oneDay)]
        let workout = card(trained, on: 9)
        XCTAssertEqual(workout.clock, HomeStart.Clock(minutes: "2 min", caption: "last time"))

        // A weekday plan on a Tuesday: a rest day, which says rest (D71); Thursday's Lower is the
        // strip's third square, and its button says when.
        let target = SetTarget(work: .reps(.fixed(5)), weight: 100, restSeconds: 180)
        let weekday = Plan(name: "Upper Lower", units: .kg, schedule: .weekday,
                           days: [Day(name: "Upper", weekday: .monday, exercises: [Exercise(name: "Press", sets: [target])]),
                                  Day(name: "Lower", weekday: .thursday, exercises: [Exercise(name: "Squat", sets: [target])])],
                           importedAt: day(1), sourceText: "", cycle: [])
        let rest = card(library(weekday), on: 1)
        XCTAssertEqual(rest.buttonTitle, "No exercise Today")
        let thursday = card(library(weekday), on: 1, showing: 2)
        XCTAssertEqual(thursday.buttonTitle, "Start Thursday's Lower")

        // Mid-session.
        let push = rotation()
        var running = library(push)
        running.engine = SessionEngine(session: CoreTestSupport.session(push, start: day(9)),
                                       settings: CoreTestSupport.classic, now: day(9))
        let open = card(running, on: 9)
        XCTAssertTrue(open.isInProgress)

        for (start, plan) in [(workout, oneDay), (rest, weekday), (thursday, weekday), (open, push)] {
            XCTAssertNil(start.sentence, start.title)
            let shown = [start.title, start.buttonTitle, start.clock?.minutes, start.clock?.caption,
                         start.message?.text].compactMap { $0 } + start.rows.map(\.name)
            for text in shown + [start.exerciseLabel ?? ""] {
                XCTAssertFalse(text.contains("Planned for"), text)
                XCTAssertFalse(text.contains(plan.name), text)
            }
            for text in shown { XCTAssertFalse(text.contains("exercises"), text) }
        }
    }

    // TS2 (D69): the rows are the first five exercises with their sets — a drop set is one
    // block — and the rest are "and N more".
    func testRowsCarryTheirSets() throws {
        let set = SetTarget(work: .reps(.fixed(8)), weight: 60, restSeconds: 90)
        var drop = set
        drop.drops = [DropTarget(work: .reps(.fixed(8)), weight: 45)]
        let names = ["Squat", "Bench Press", "Row", "Plank", "Curl", "Calf Raise"]
        var exercises = zip(names, [4, 3, 2, 1, 5, 2]).map { name, count in
            Exercise(name: name, sets: Array(repeating: set, count: count))
        }
        exercises[2].sets = [set, drop]
        let plan = Plan(name: "Full Body", units: .kg, schedule: .rotation,
                        days: [Day(name: "Full", exercises: exercises)],
                        importedAt: day(1), sourceText: "", cycle: [.day(0)])
        let full = card(library(plan), on: 9)
        XCTAssertEqual(full.rows, [HomeStart.PreviewRow(name: "Squat", sets: 4),
                                   HomeStart.PreviewRow(name: "Bench Press", sets: 3),
                                   HomeStart.PreviewRow(name: "Row", sets: 2),
                                   HomeStart.PreviewRow(name: "Plank", sets: 1),
                                   HomeStart.PreviewRow(name: "Curl", sets: 5)])
        XCTAssertEqual(full.more, 1)
        XCTAssertEqual(full.exerciseLabel, "Exercises: Squat, Bench Press, Row, Plank, Curl, and 1 more")
        XCTAssertTrue(full.rows.allSatisfy { $0.logged == nil }, "nothing fills before a session")
    }

    // TS3 (D69): mid-session a row's blocks are the session's sets and the filled ones are the
    // engine's logged sets — a drop set counts once, its drop logged or not.
    func testLoggedSetsAreTheEngines() throws {
        let plan = CoreTestSupport.plan(sets: 2, secondExercise: true,
                                        drops: [DropTarget(work: .reps(.fixed(8)), weight: 40)])
        var engine = SessionEngine(session: CoreTestSupport.session(plan, start: day(9)),
                                   settings: CoreTestSupport.classic, now: day(9))
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: day(9).addingTimeInterval(60))
        engine.apply(.logSet(step: 1, result: .reps(count: 8, weight: 40)), now: day(9).addingTimeInterval(90))
        XCTAssertEqual(engine.session.steps.prefix(2).map(\.status), [.logged, .logged], "the set and its drop")
        var running = library(plan)
        running.engine = engine
        let open = HomeStart.current(library: running, now: day(9).addingTimeInterval(120), calendar: calendar)
        XCTAssertEqual(open.rows, [HomeStart.PreviewRow(name: "Bench Press", sets: 2, logged: 1),
                                   HomeStart.PreviewRow(name: "Row", sets: 2, logged: 0)])
        let engineCount = engine.session.steps.filter { $0.exerciseIndex == 0 && $0.dropIndex == 0 && $0.status == .logged }.count
        XCTAssertEqual(open.rows.first?.logged, engineCount)
        XCTAssertEqual(open.clock, HomeStart.Clock(minutes: "2 min", caption: "so far"))
        // The plan's own card has the same blocks, none filled.
        XCTAssertEqual(card(library(plan), on: 9).rows.map(\.sets), [2, 2])
    }

    // TQ22 (D75, v1.9): the progression left Today — no step line, no offer to plan one, and
    // the rows open nothing; History's Progression row (D67) is the way. (TS4, the step line,
    // went with it; a progression that has run its course still speaks, T1.)
    func testTheProgressionLeftToday() throws {
        let labels = Mirror(reflecting: card(library(rotation()), on: 9)).children.compactMap(\.label)
        for gone in ["stepLine", "offersProgression", "previewPlanId"] {
            XCTAssertFalse(labels.contains(gone), "HomeStart has \(gone) again")
        }
        // A plan with no progression whose day has history for every exercise — what D50
        // offered on — and one mid-progression: neither card names a progression.
        let oneDay = CoreTestSupport.plan()
        var single = library(oneDay)
        single.sessions = [CoreTestSupport.completed(plan: oneDay)]
        var stepped = oneDay
        stepped.progression = Progression(startDate: calendar.startOfDay(for: day(1)), weeks: 4,
                                          entries: [ProgressionEntry(dayName: "Push", exerciseName: "Bench Press",
                                                                     weeks: Array(repeating: ProgressionWeek(weight: 62.5), count: 4))],
                                          mode: .performance)
        for start in [card(single, on: 9), card(library(stepped), on: 9)] {
            XCTAssertEqual(start.alternatives.map(\.title), ["Change plan", "Change Push"])
            XCTAssertNil(start.message)
        }

        let home = try FixtureLoader.requiredDoc("JimmsBro/Core/HomeCard.swift")
        let gates = try FixtureLoader.requiredDoc("JimmsBro/Core/Gates.swift")
        let prompts = try FixtureLoader.requiredDoc("JimmsBro/Core/Prompts.swift")
        let today = try FixtureLoader.requiredDoc("JimmsBro/Features/Home/HomeView.swift")
        XCTAssertFalse(home.contains("case planProgression"), "Today's ··· offers a progression again")
        XCTAssertFalse(gates.contains("func planProgression"), "Gates has Plan a progression's gate again")
        XCTAssertFalse(prompts.contains("static let planProgression"), "PromptText names Today's link again")
        XCTAssertFalse(today.contains("stepLine"), "Today draws a step line again")
        XCTAssertFalse(today.contains("previewing = PlanRoute(id: planId"), "Today's rows open Plan detail again")
    }

    // TS6 (D70): seven squares, today first, on a weekday plan — Push rest Pull rest Legs rest
    // rest from a Monday — each with its colour and its "when"; the card carries the same
    // strip, the empty card none, and Nothing scheduled seven grey ones under a moon button.
    func testTheStripOnAWeekdayPlan() throws {
        let plan = weekdayPlan()
        XCTAssertEqual(calendar.component(.weekday, from: day(14)), 2, "the 14th is a Monday")
        let strip = WeekStrip.days(plan: plan, sessions: [], swaps: [], today: day(14), calendar: calendar)
        XCTAssertEqual(strip.count, 7)
        XCTAssertEqual(strip.map(\.offset), Array(0..<7))
        XCTAssertEqual(strip.map(\.dayName), ["Push", nil, "Pull", nil, "Legs", nil, nil])
        XCTAssertEqual(strip.map(\.dayIndex), [0, nil, 1, nil, 2, nil, nil])
        XCTAssertEqual(strip.map(\.colour), [.green, nil, .orange, nil, .purple, nil, nil])
        XCTAssertEqual(strip.map(\.when),
                       ["Today", "Tomorrow", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
        XCTAssertEqual(strip.map(\.isRest), [false, true, false, true, false, true, true])
        XCTAssertEqual(strip[0].spoken, "Today, Push")
        XCTAssertEqual(strip[1].spoken, "Tomorrow, rest")
        XCTAssertEqual(strip[2].spoken, "Wednesday, Pull")

        // From a Thursday the week wraps: rest, Legs, rest, rest, Push, rest, Pull.
        let thursday = WeekStrip.days(plan: plan, sessions: [], swaps: [], today: day(17), calendar: calendar)
        XCTAssertEqual(thursday.map(\.dayName), [nil, "Legs", nil, nil, "Push", nil, "Pull"])
        XCTAssertEqual(thursday.map(\.when),
                       ["Today", "Tomorrow", "Saturday", "Sunday", "Monday", "Tuesday", "Wednesday"])

        // The card's strip is this one, today's square shown; the empty card has no week.
        let monday = card(library(plan), on: 14)
        XCTAssertEqual(monday.strip, strip)
        XCTAssertEqual(monday.shownOffset, 0)
        XCTAssertTrue(card(PlanLibrary(), on: 14).strip.isEmpty)
        XCTAssertNil(card(PlanLibrary(), on: 14).buttonMark, "Choose a plan has no mark")

        // A plan with no day to schedule: seven grey squares, the moon's button, Change plan.
        var nothing = plan
        nothing.days = nothing.days.map { var day = $0; day.weekday = nil; return day }
        let grey = card(library(nothing), on: 14)
        XCTAssertEqual(grey.title, "Nothing scheduled")
        XCTAssertEqual(grey.strip.count, 7)
        XCTAssertTrue(grey.strip.allSatisfy { $0.colour == nil && $0.isRest })
        XCTAssertEqual(grey.buttonTitle, "No exercise Today")
        XCTAssertEqual(grey.buttonMark, .moon)
        XCTAssertFalse(grey.buttonEnabled)
        XCTAssertEqual(grey.alternatives, [.changePlan(cycle: DayColour.cycle(of: nothing))],
                       "no day to change: Change plan alone (D75)")
        XCTAssertNotNil(grey.sentence, "not a day of the plan: it keeps its sentence")
    }

    // TS7 (D70): on a rotation the strip is the calendar's own projection for the same seven
    // dates — the month grid says the same for each — across a month boundary too; and today's
    // square after today's workout is the workout's, as the calendar draws it.
    func testTheStripAgreesWithTheCalendar() throws {
        let plan = rotation(anchor: 7)
        for start in [9, 28] {
            let strip = WeekStrip.days(plan: plan, sessions: [], swaps: [], today: day(start), calendar: calendar)
            let run = CalendarProjection.next(days: 7, from: day(start), activePlan: plan, sessions: [],
                                              swaps: [],
                                              today: day(start), calendar: calendar)
            XCTAssertEqual(run.count, 7)
            for (offset, square) in strip.enumerated() {
                let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset,
                                                       to: calendar.startOfDay(for: day(start))))
                XCTAssertTrue(calendar.isDate(run[offset].date, inSameDayAs: date))
                let grid = CalendarProjection.entries(month: date, activePlan: plan, sessions: [],
                                                      swaps: [],
                                                      today: day(start), calendar: calendar)
                let cell = try XCTUnwrap(grid.first { calendar.isDate($0.date, inSameDayAs: date) })
                XCTAssertEqual(cell.entry, run[offset].entry, "the strip and the grid disagree on day \(offset)")
                switch cell.entry {
                case let .projected(_, dayIndex):
                    XCTAssertEqual(square.dayIndex, dayIndex)
                    XCTAssertEqual(square.dayName, plan.days[dayIndex].name)
                    XCTAssertEqual(square.colour, DayColour.of(dayIndex: dayIndex))
                case .rest:
                    XCTAssertTrue(square.isRest)
                    XCTAssertNil(square.dayIndex)
                    XCTAssertNil(square.colour)
                default:
                    XCTFail("the grid says nothing about a day within the week: \(cell.entry)")
                }
            }
        }
        // Push done on the 7th, so the 8th is Pull: from the 9th, Legs rest Push Pull Legs rest Push.
        let ninth = WeekStrip.days(plan: plan, sessions: [], swaps: [], today: day(9), calendar: calendar)
        XCTAssertEqual(ninth.map(\.dayName), ["Legs", nil, "Push", "Pull", "Legs", nil, "Push"])
        // The 28th to the 4th of October: still seven, still the pattern — Pull Legs rest Push
        // Pull Legs rest, the rest days falling on the 30th and the 4th.
        let straddling = WeekStrip.days(plan: plan, sessions: [], swaps: [], today: day(28), calendar: calendar)
        XCTAssertEqual(straddling.map(\.dayName), ["Pull", "Legs", nil, "Push", "Pull", "Legs", nil])
        XCTAssertEqual(straddling.map(\.when),
                       ["Today", "Tomorrow", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])

        // Today's workout done: today's square is the workout's day and colour, the rest as before.
        let done = CoreTestSupport.completed(plan: plan, start: day(9))
        XCTAssertEqual(done.dayName, "Push")
        let after = WeekStrip.days(plan: plan, sessions: [done], swaps: [], today: day(9), calendar: calendar)
        XCTAssertEqual(after[0].dayName, "Push")
        XCTAssertEqual(after[0].dayIndex, 0)
        XCTAssertEqual(after[0].colour, .green)
        XCTAssertFalse(after[0].isRest)
        XCTAssertEqual(Array(after[1...]), Array(ninth[1...]))
    }

    // TS8 (D70): the button names when — for the strip's offsets and for a rest square at each
    // — and a tap shows that day: its name, colour, rows, minutes and button; a grey square's
    // card says rest (D71); the first square is Today's own card; the strip stays live while a
    // session is open.
    func testTheButtonNamesWhen() throws {
        XCTAssertEqual(WeekStrip.buttonTitle(dayName: "Push", offset: 0, weekday: .monday), "Start Today's Push")
        XCTAssertEqual(WeekStrip.buttonTitle(dayName: "Pull", offset: 1, weekday: .tuesday), "Start Tomorrow's Pull")
        XCTAssertEqual(WeekStrip.buttonTitle(dayName: "Legs", offset: 4, weekday: .friday), "Start Friday's Legs")
        XCTAssertEqual(WeekStrip.buttonTitle(dayName: nil, offset: 0, weekday: .monday), "No exercise Today")
        XCTAssertEqual(WeekStrip.buttonTitle(dayName: nil, offset: 1, weekday: .tuesday), "No exercise Tomorrow")
        XCTAssertEqual(WeekStrip.buttonTitle(dayName: nil, offset: 4, weekday: .friday), "No exercise Friday")

        // Monday, with a two-minute Pull behind it; tap Wednesday's square.
        let plan = weekdayPlan()
        var pullSession = try XCTUnwrap(Session.start(plan: plan, dayIndex: 1, now: day(9)))
        pullSession.endedAt = day(9).addingTimeInterval(120)
        var trained = library(plan)
        trained.sessions = [pullSession]
        let pull = card(trained, on: 14, showing: 2)
        XCTAssertEqual(pull.shownOffset, 2)
        XCTAssertEqual(pull.title, "Pull")
        XCTAssertEqual(pull.dayColour, .orange)
        XCTAssertEqual(pull.rows, [HomeStart.PreviewRow(name: "Row", sets: 1)])
        XCTAssertEqual(pull.clock, HomeStart.Clock(minutes: "2 min", caption: "last time"))
        XCTAssertEqual(pull.buttonTitle, "Start Wednesday's Pull")
        XCTAssertEqual(pull.buttonMark, .play)
        XCTAssertTrue(pull.buttonEnabled)
        XCTAssertEqual(pull.planId, plan.id)
        XCTAssertEqual(pull.dayIndex, 1)
        XCTAssertEqual(pull.exerciseLabel, "Exercises: Row")
        XCTAssertNil(pull.sentence)
        XCTAssertFalse(pull.isRest)
        XCTAssertEqual(pull.alternatives, [.changePlan(cycle: DayColour.cycle(of: plan)),
                                           .changeExercises(dayName: "Pull", colour: .orange, outlined: false)])

        // Tomorrow is grey: the rest card — Rest, no colour, no rows, no clock, a moon's button.
        let rest = card(trained, on: 14, showing: 1)
        XCTAssertEqual(rest.title, "Rest")
        XCTAssertTrue(rest.isRest)
        XCTAssertNil(rest.dayColour)
        XCTAssertTrue(rest.rows.isEmpty)
        XCTAssertNil(rest.clock)
        XCTAssertNil(rest.sentence)
        XCTAssertNil(rest.exerciseLabel)
        XCTAssertEqual(rest.buttonTitle, "No exercise Tomorrow")
        XCTAssertEqual(rest.buttonMark, .moon)
        XCTAssertFalse(rest.buttonEnabled)
        XCTAssertNil(rest.planId)
        XCTAssertNil(rest.dayIndex)
        XCTAssertEqual(rest.alternatives, [.changePlan(cycle: DayColour.cycle(of: plan)),
                                           .changeExercises(dayName: "Rest", colour: nil, outlined: false)])
        XCTAssertEqual(rest.strip, pull.strip, "the strip does not change with the tap")

        // The first square is Today's own card, as S1 left it; a tap past the strip is clamped.
        let today = card(trained, on: 14, showing: 0)
        XCTAssertEqual(today, card(trained, on: 14))
        XCTAssertEqual(today.title, "Push")
        XCTAssertEqual(today.buttonTitle, "Start Today's Push")
        XCTAssertEqual(today.buttonMark, .play)
        XCTAssertEqual(card(trained, on: 14, showing: 9).shownOffset, 6)
        XCTAssertEqual(card(trained, on: 14, showing: -1).shownOffset, 0)

        // While a session is open the strip is still live — the tapped day's card, its Start
        // (which raises the switch popup, O36), and Discard still last in the ···.
        var running = trained
        running.engine = SessionEngine(session: CoreTestSupport.session(plan, start: day(14)),
                                       settings: CoreTestSupport.classic, now: day(14))
        XCTAssertTrue(card(running, on: 14).isInProgress)
        XCTAssertEqual(card(running, on: 14).buttonMark, .play)
        let tapped = card(running, on: 14, showing: 2)
        XCTAssertFalse(tapped.isInProgress)
        XCTAssertEqual(tapped.title, "Pull")
        XCTAssertEqual(tapped.buttonTitle, "Start Wednesday's Pull")
        XCTAssertEqual(tapped.planId, plan.id)
        XCTAssertEqual(tapped.alternatives, [.changePlan(cycle: DayColour.cycle(of: plan)), .discardWorkout],
                       "mid-workout the ··· is v1.8's (D75)")
        XCTAssertEqual(card(running, on: 14, showing: 1).alternatives,
                       [.changePlan(cycle: DayColour.cycle(of: plan)), .discardWorkout])
    }

    // TS9 (D70): Another day is not in the ··· — the strip is the way — and neither `Gates`
    // nor Today has its gate or its chooser any more.
    func testAnotherDayLeftTheMenu() throws {
        let plan = weekdayPlan()
        var nothing = plan
        nothing.days = nothing.days.map { var day = $0; day.weekday = nil; return day }
        let cards = [card(library(rotation()), on: 9), card(library(plan), on: 14),
                     card(library(plan), on: 15), card(library(nothing), on: 14),
                     card(library(plan), on: 14, showing: 3)]
        for start in cards {
            XCTAssertFalse(start.alternatives.map(\.title).contains("Another day"), start.title)
        }
        XCTAssertEqual(card(library(rotation()), on: 9).alternatives.map(\.title),
                       ["Change plan", "Change Push"])
        XCTAssertEqual(card(library(nothing), on: 14).alternatives.map(\.title), ["Change plan"],
                       "nothing scheduled offered Another day until v1.8; the strip is the way")

        let core = try FixtureLoader.requiredDoc("JimmsBro/Core/HomeCard.swift")
        let gates = try FixtureLoader.requiredDoc("JimmsBro/Core/Gates.swift")
        let today = try FixtureLoader.requiredDoc("JimmsBro/Features/Home/HomeView.swift")
        XCTAssertFalse(core.contains("case anotherDay"), "HomeStart offers Another day again")
        XCTAssertFalse(gates.contains("func anotherDay"), "Gates has Another day's gate again")
        XCTAssertFalse(today.contains("Which day?"), "Today draws the day chooser again")
        XCTAssertTrue(today.contains("WeekStripView("), "Today no longer draws the strip")
    }

    // TS10 (D70): the shown day is not in `Settings` — the frozen v1.1 file decodes unchanged,
    // the type has no field for it, and the decoder gained no key.
    func testTheShownDayIsNotStored() throws {
        let frozen = try StoreCoder.decode(Settings.self, from: try FixtureLoader.data("store/v1/settings.json"))
        XCTAssertEqual(frozen.defaultRestSeconds, 90)
        XCTAssertEqual(try StoreCoder.decode(Settings.self, from: try StoreCoder.encode(frozen)), frozen)
        let labels = Mirror(reflecting: Settings()).children.compactMap(\.label)
        let words = ["shown", "strip", "offset", "week"]
        for label in labels {
            for word in words {
                XCTAssertFalse(label.lowercased().contains(word), "Settings carries \(label)")
            }
        }
        // And HomeStart does carry it, as a value: the strip's shown square is Today's, not the disk's.
        XCTAssertTrue(Mirror(reflecting: card(PlanLibrary(), on: 14)).children.contains { $0.label == "shownOffset" })

        let source = try FixtureLoader.requiredDoc("JimmsBro/Core/Persistence.swift")
        let block = try XCTUnwrap(source.components(separatedBy: "extension Settings {").last?
                                    .components(separatedBy: "\nextension ").first)
        let keys = block.components(separatedBy: "container.value(.").dropFirst()
            .map { String($0.prefix { $0.isLetter || $0.isNumber }) }
        XCTAssertEqual(keys.count, 13, "the Settings decoder gained a key: \(keys)")
        XCTAssertTrue(Set(keys).isSubset(of: Set(labels)), "a decoded key that is not a field")
        for key in keys {
            for word in words {
                XCTAssertFalse(key.lowercased().contains(word), "the decoder reads \(key)")
            }
        }
    }

    /// The weekday plan with a two-minute Pull finished on Wednesday the 9th.
    private func trainedWeekdayPlan() throws -> (Plan, PlanLibrary) {
        let plan = weekdayPlan()
        var pull = try XCTUnwrap(Session.start(plan: plan, dayIndex: 1, now: day(9)))
        pull.endedAt = day(9).addingTimeInterval(120)
        var trained = library(plan)
        trained.sessions = [pull]
        return (plan, trained)
    }

    // TS13 (D71): a rest day says rest — "Rest" after a grey square, no rows, no clock and no
    // target, and the moon's disabled "No exercise Today" — on a weekday plan and on a
    // rotation's rest entry; the schedule's own answer still names the next workout.
    func testARestDaySaysRest() throws {
        let (plan, trained) = try trainedWeekdayPlan()
        XCTAssertEqual(calendar.component(.weekday, from: day(15)), 3, "the 15th is a Tuesday")
        let rest = card(trained, on: 15)
        XCTAssertEqual(rest.title, "Rest")
        XCTAssertTrue(rest.isRest)
        XCTAssertNil(rest.dayColour, "the square before Rest is grey")
        XCTAssertTrue(rest.rows.isEmpty)
        XCTAssertEqual(rest.more, 0)
        XCTAssertNil(rest.exerciseLabel)
        XCTAssertNil(rest.planId, "the button has no target")
        XCTAssertNil(rest.dayIndex)
        XCTAssertNil(rest.clock, "the moon stands where the clock would, and no minutes — not Pull's")
        XCTAssertNil(rest.sentence)
        XCTAssertEqual(rest.buttonTitle, "No exercise Today")
        XCTAssertEqual(rest.buttonMark, .moon)
        XCTAssertFalse(rest.buttonEnabled)
        XCTAssertEqual(rest.alternatives, [.changePlan(cycle: DayColour.cycle(of: plan)),
                                           .changeExercises(dayName: "Rest", colour: nil, outlined: false)],
                       "a rest date can take a workout for that date (D75)")
        XCTAssertEqual(rest.shownOffset, 0)
        XCTAssertEqual(rest.strip.map(\.dayName), [nil, "Pull", nil, "Legs", nil, nil, "Push"])
        XCTAssertTrue(rest.strip[0].isRest, "the first square is grey")
        // The schedule still knows the next workout; Today's button no longer starts it.
        XCTAssertEqual(StartCard.current(library: trained, now: day(15), calendar: calendar),
                       .restDay(planId: plan.id, dayIndex: 1, dayName: "Pull", weekday: .wednesday, daysAway: 1))

        // A rotation's rest entry: Legs done on the 9th, so the 10th rests and Push is the 11th.
        var rotating = rotation(anchor: 9)
        rotating.cyclePosition = 2
        let resting = card(library(rotating), on: 10)
        XCTAssertEqual(resting.title, "Rest")
        XCTAssertTrue(resting.isRest)
        XCTAssertNil(resting.missed, "the day before was the anchor: nothing was missed")
        XCTAssertNil(resting.message)
        XCTAssertTrue(resting.rows.isEmpty)
        XCTAssertNil(resting.planId)
        XCTAssertEqual(resting.buttonTitle, "No exercise Today")
        XCTAssertEqual(resting.buttonMark, .moon)
        XCTAssertEqual(resting.strip.map(\.dayName), [nil, "Push", "Pull", "Legs", nil, "Push", "Pull"])
    }

    // TS14 (D71): on a rest day the next workout is one tap away — its square yields that day's
    // card, target and rows, and a button that says when; a later grey square is a rest card.
    func testTheNextWorkoutIsOneTapAway() throws {
        let (plan, trained) = try trainedWeekdayPlan()
        let pull = card(trained, on: 15, showing: 1)
        XCTAssertFalse(pull.isRest)
        XCTAssertEqual(pull.title, "Pull")
        XCTAssertEqual(pull.dayColour, .orange)
        XCTAssertEqual(pull.planId, plan.id)
        XCTAssertEqual(pull.dayIndex, 1)
        XCTAssertEqual(pull.rows, [HomeStart.PreviewRow(name: "Row", sets: 1)])
        XCTAssertEqual(pull.clock, HomeStart.Clock(minutes: "2 min", caption: "last time"))
        XCTAssertEqual(pull.buttonTitle, "Start Tomorrow's Pull")
        XCTAssertEqual(pull.buttonMark, .play)
        XCTAssertTrue(pull.buttonEnabled)

        let legs = card(trained, on: 15, showing: 3)
        XCTAssertEqual(legs.title, "Legs")
        XCTAssertEqual(legs.dayIndex, 2)
        XCTAssertEqual(legs.rows, [HomeStart.PreviewRow(name: "Squat", sets: 1)])
        XCTAssertEqual(legs.buttonTitle, "Start Friday's Legs")

        let saturday = card(trained, on: 15, showing: 4)
        XCTAssertTrue(saturday.isRest)
        XCTAssertEqual(saturday.buttonTitle, "No exercise Saturday")
        XCTAssertEqual(saturday.buttonMark, .moon)

        // A rotation's rest day: tomorrow's Push, all seven of its exercises behind the five.
        var rotating = rotation(anchor: 9)
        rotating.cyclePosition = 2
        let push = card(library(rotating), on: 10, showing: 1)
        XCTAssertEqual(push.title, "Push")
        XCTAssertEqual(push.dayIndex, 0)
        XCTAssertEqual(push.rows.count, 5)
        XCTAssertEqual(push.more, 2)
        XCTAssertEqual(push.buttonTitle, "Start Tomorrow's Push")
    }

    // TS15 (D71, D37): a missed workout still speaks on a rest day — with Do it now, whose target
    // is the missed day, exactly as before — and a progression that has run its course still
    // says so once that is dismissed: the message is the plan's, not the day's (§6.44).
    func testAMissedWorkoutStillSpeaksOnARestDay() throws {
        // Push done on the 7th: Pull on the 8th and Legs on the 9th never happened; the 10th rests.
        let both = library(rotation(anchor: 7, progression: finishedByTheNinth()))
        let rest = card(both, on: 10)
        XCTAssertTrue(rest.isRest)
        XCTAssertEqual(rest.buttonTitle, "No exercise Today")
        XCTAssertNil(rest.planId)
        let missed = try XCTUnwrap(rest.missed)
        XCTAssertEqual(missed.dayName, "Legs")
        XCTAssertEqual(missed.dayIndex, 2, "Do it now starts the missed day")
        XCTAssertTrue(calendar.isDate(missed.date, inSameDayAs: day(9)))
        XCTAssertTrue(missed.text.hasPrefix("Legs was due "))
        XCTAssertEqual(rest.message, .missed(missed))
        XCTAssertEqual(rest.message?.actions, ["Do it now", "Dismiss"])

        // Dismissed, the progression that has run its course speaks, on the rest card as on a
        // workout's — and on a tapped grey square too: the message does not follow the square.
        let next = card(both, on: 10, missedDismissed: true)
        XCTAssertTrue(next.progressionFinished)
        XCTAssertEqual(next.message, .progressionFinished)
        let later = card(both, on: 10, missedDismissed: true, showing: 4)
        XCTAssertTrue(later.isRest)
        XCTAssertEqual(later.message, .progressionFinished)
    }

    // TS17 (D71, the owner's reading of 2026-09-13): once a workout was finished today, today's
    // card is the rest card and says so truthfully — "Done Today" under a check, disabled, while
    // today's square is the workout's colour — on every plan: a rotation (re-anchored on the day,
    // so its next workout is tomorrow's), a weekday plan's own day (which keeps its day, and would
    // otherwise offer the same workout again), and a weekday rest day with a workout done early.
    func testAfterTheWorkoutTheRestCardSaysDone() throws {
        // Push finished on the 9th: the rotation re-anchored there, and Pull is tomorrow.
        let plan = rotation(anchor: 9)
        var trained = library(plan)
        trained.sessions = [CoreTestSupport.completed(plan: plan, start: day(9))]
        XCTAssertEqual(StartCard.current(library: trained, now: day(9), calendar: calendar),
                       .restDay(planId: plan.id, dayIndex: 1, dayName: "Pull", weekday: .thursday, daysAway: 1))
        let done = card(trained, on: 9)
        XCTAssertTrue(done.isRest)
        XCTAssertEqual(done.title, "Rest")
        XCTAssertEqual(done.buttonTitle, "Done Today")
        XCTAssertEqual(done.buttonTitle, HomeStart.doneTitle)
        XCTAssertEqual(done.buttonMark, .check)
        XCTAssertFalse(done.buttonEnabled)
        XCTAssertNil(done.planId)
        XCTAssertTrue(done.rows.isEmpty)
        XCTAssertNil(done.clock)
        XCTAssertNil(done.dayColour, "the square before Rest is grey")
        XCTAssertEqual(done.strip[0].dayName, "Push", "today's square is the workout's")
        XCTAssertEqual(done.strip[0].colour, .green)
        XCTAssertEqual(card(trained, on: 9, showing: 1).buttonTitle, "Start Tomorrow's Pull")
        // A tapped grey square is never "done": that day has not happened.
        XCTAssertEqual(card(trained, on: 9, showing: 3).buttonTitle, "No exercise Saturday")
        XCTAssertEqual(card(trained, on: 9, showing: 3).buttonMark, .moon)

        // A weekday plan's Tuesday, with Wednesday's Pull done early from the strip.
        let weekly = weekdayPlan()
        var early = try XCTUnwrap(Session.start(plan: weekly, dayIndex: 1, now: day(15)))
        early.endedAt = day(15).addingTimeInterval(1800)
        var extra = library(weekly)
        extra.sessions = [early]
        let doneEarly = card(extra, on: 15)
        XCTAssertEqual(doneEarly.title, "Rest")
        XCTAssertEqual(doneEarly.buttonTitle, "Done Today")
        XCTAssertEqual(doneEarly.buttonMark, .check)
        XCTAssertEqual(doneEarly.strip[0].dayName, "Pull")

        // A weekday plan's own Monday, after its Push: the schedule still says today's Push, and
        // the card says it is done rather than offering it again.
        var push = try XCTUnwrap(Session.start(plan: weekly, dayIndex: 0, now: day(14)))
        push.endedAt = day(14).addingTimeInterval(1800)
        var monday = library(weekly)
        monday.sessions = [push]
        XCTAssertEqual(StartCard.current(library: monday, now: day(14), calendar: calendar),
                       .today(planId: weekly.id, dayIndex: 0, dayName: "Push"))
        let doneMonday = card(monday, on: 14)
        XCTAssertTrue(doneMonday.isRest)
        XCTAssertEqual(doneMonday.title, "Rest")
        XCTAssertEqual(doneMonday.buttonTitle, "Done Today")
        XCTAssertEqual(doneMonday.buttonMark, .check)
        XCTAssertFalse(doneMonday.buttonEnabled)
        XCTAssertNil(doneMonday.planId, "the workout just done is not offered again")
        XCTAssertTrue(doneMonday.rows.isEmpty)
        XCTAssertEqual(doneMonday.strip[0].dayName, "Push")
        XCTAssertEqual(doneMonday.strip[0].colour, .green)
        XCTAssertEqual(card(monday, on: 14, showing: 2).buttonTitle, "Start Wednesday's Pull")
        // A week later it is an ordinary Monday again.
        XCTAssertEqual(card(monday, on: 21).buttonTitle, "Start Today's Push")
    }
}
