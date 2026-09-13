import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// T1 (v1.7) — Today is one card (D61): the one message, the ··· items, the exercise block
/// that is the preview, and the empty card's two choices. T1–T4.
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
                      missedDismissed: Bool = false) -> HomeStart {
        HomeStart.current(library: library, now: day(n), calendar: calendar,
                          notificationsOff: notificationsOff, missedDismissed: missedDismissed)
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

    // T2: the ··· items — Another day only with another day, Plan a progression only while
    // D50 offers it, Discard last while a session is open, nothing at all with no plan.
    func testAlternatives() throws {
        XCTAssertEqual(card(PlanLibrary(), on: 9).alternatives, [], "no plan: no ···")
        XCTAssertEqual(card(library(rotation()), on: 9).alternatives, [.anotherDay, .changePlan])

        // A one-day plan has no other day to offer.
        let oneDay = CoreTestSupport.plan()
        XCTAssertEqual(oneDay.days.count, 1)
        var single = library(oneDay)
        XCTAssertEqual(card(single, on: 9).alternatives, [.changePlan])

        // With every exercise on the day logged once, D50's link joins — as the last item.
        single.sessions = [CoreTestSupport.completed(plan: oneDay)]
        let offered = card(single, on: 9)
        XCTAssertTrue(offered.offersProgression)
        XCTAssertEqual(offered.alternatives, [.changePlan, .planProgression])

        // And leaves again the moment the plan carries a progression.
        var progressed = oneDay
        progressed.progression = Progression(startDate: calendar.startOfDay(for: day(9)), weeks: 4, entries: [])
        single.replace(oneDay.id, with: progressed)
        XCTAssertNotNil(single.activePlan?.progression)
        XCTAssertEqual(card(single, on: 9).alternatives, [.changePlan])

        // While a session is open the menu ends with Discard, and Another day is not offered.
        let plan = rotation()
        var running = library(plan)
        running.engine = SessionEngine(session: CoreTestSupport.session(plan, start: day(9)),
                                       settings: CoreTestSupport.classic, now: day(9))
        let inProgress = card(running, on: 9)
        XCTAssertTrue(inProgress.isInProgress)
        XCTAssertEqual(inProgress.alternatives, [.changePlan, .discardWorkout])
        XCTAssertEqual(inProgress.alternatives.last, .discardWorkout)

        // The titles the menu shows.
        XCTAssertEqual(HomeStart.Alternative.anotherDay.title, "Another day")
        XCTAssertEqual(HomeStart.Alternative.changePlan.title, "Change plan")
        XCTAssertEqual(HomeStart.Alternative.planProgression.title, PromptText.planProgression)
        XCTAssertEqual(HomeStart.Alternative.discardWorkout.title, "Discard workout")
    }

    // T3: the exercise block is the preview, and says so to VoiceOver.
    func testExerciseBlockIsThePreview() throws {
        let plan = rotation()
        let push = card(library(plan), on: 1)
        XCTAssertEqual(push.title, "Push")
        XCTAssertEqual(push.exerciseLabel,
                       "Exercises: Bench Press, Incline Press, Lateral Raise, Tricep Pushdown, Plank, and 2 more. Opens Push")
        XCTAssertEqual(push.previewPlanId, plan.id)

        // Fewer than five: no "and N more".
        let legs = card(library(rotation(anchor: 7)), on: 9)
        XCTAssertEqual(legs.title, "Legs")
        XCTAssertEqual(legs.exerciseLabel, "Exercises: Squat. Opens Legs")

        // In progress the block still stands, from the session, and the subtitle says where
        // you are; Resume still goes to the session, not to a day.
        var running = library(plan)
        running.engine = SessionEngine(session: CoreTestSupport.session(plan, start: day(9)),
                                       settings: CoreTestSupport.classic, now: day(9))
        let inProgress = HomeStart.current(library: running, now: day(9).addingTimeInterval(23 * 60),
                                           calendar: calendar)
        XCTAssertEqual(inProgress.subtitle, "In progress · 0 of 7 sets · 23 min")
        XCTAssertEqual(inProgress.buttonTitle, "Resume Push · 23 min")
        XCTAssertEqual(inProgress.exercises.count, 5)
        XCTAssertEqual(inProgress.more, 2)
        XCTAssertEqual(inProgress.exerciseLabel,
                       "Exercises: Bench Press, Incline Press, Lateral Raise, Tricep Pushdown, Plank, and 2 more. Opens Push")
        XCTAssertEqual(inProgress.previewPlanId, plan.id)
        XCTAssertNil(inProgress.planId)
        XCTAssertNil(inProgress.dayIndex)
    }

    // T4: the empty card — two choices where there were three.
    func testEmptyCard() throws {
        let empty = card(PlanLibrary(), on: 9)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.title, "No plan yet")
        XCTAssertEqual(empty.subtitle, "Choose a built-in plan to start today, or have a chatbot write yours.")
        XCTAssertEqual(empty.buttonTitle, "Choose a plan")
        XCTAssertEqual(empty.buttonTitle, Introduction.choosePlan, "the intro's button says the same")
        XCTAssertEqual(empty.link, "Try a short practice workout")
        XCTAssertEqual(empty.alternatives, [])
        XCTAssertNil(empty.message)
        XCTAssertTrue(empty.exercises.isEmpty)
        XCTAssertNil(empty.exerciseLabel)

        // Only the empty card has the link.
        XCTAssertNil(card(library(rotation()), on: 9).link)
    }

    // T7 (D62): the tab bar is SPEC §4.0's list — Today · History, in that order — and the app
    // draws `AppTab.allCases` and nothing else, so a third tab needs SPEC's word first.
    func testTheTabsAreSpecsList() throws {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Today", "History"])
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["today", "history"])
        guard let spec = FixtureLoader.doc("docs/SPEC.md"),
              let root = FixtureLoader.doc("JimmsBro/RootView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        let rule = try XCTUnwrap(spec.components(separatedBy: "\n").first(where: { $0.hasPrefix("- Tab bar with ") }),
                                 "SPEC §4.0 no longer has its tab rule")
        // The rule's first bold run is the list.
        let list = try XCTUnwrap(rule.components(separatedBy: "**").dropFirst().first)
        XCTAssertEqual(list.components(separatedBy: " · "), AppTab.allCases.map(\.title))
        XCTAssertTrue(root.contains("ForEach(AppTab.allCases"), "RootView no longer draws AppTab's list")
        XCTAssertEqual(root.components(separatedBy: ".tabItem").count, 2, "a tab drawn outside AppTab's list")
    }
}
