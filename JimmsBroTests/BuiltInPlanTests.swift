import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Y2 (v1.4) — D46: the four built-in plans, read from the files that actually ship.
///
/// "The built-in plans should all be really well thought out." These tests are what that
/// means in a form that stays true: every plan imports with nothing to say, every rep
/// exercise carries the range the app's advice needs, no plan guesses a stranger's weights,
/// rest never climbs as a day goes on, one movement has one spelling across all of them, and
/// every day runs through the real flattening in the time the picker says it takes.
final class BuiltInPlanTests: XCTestCase {
    private let now = CoreTestSupport.now

    private func text(_ id: String) throws -> String {
        try FixtureLoader.appResource(id, extension: "json")
    }

    /// Imported the way the app imports it, and required to be clean: no errors, and no
    /// warnings of either kind — a plan the app ships has nothing to tidy.
    private func imported(_ entry: BuiltInPlan, settings: Settings = Settings()) throws -> Plan {
        let result = PlanImport.run(try text(entry.id), settings: settings, now: now)
        XCTAssertTrue(result.issues.isEmpty, "\(entry.id): \(result.issues)")
        return try XCTUnwrap(result.plan, entry.id)
    }

    private func entry(_ id: String) throws -> BuiltInPlan {
        try XCTUnwrap(BuiltInPlans.entry(id), id)
    }

    private func trainingDays(_ plan: Plan) -> [Int] {
        plan.cycle.compactMap { if case let .day(index) = $0 { return index } else { return nil } }
    }

    // Y4: the catalogue and the bundle agree, and every plan imports clean in either unit.
    func testEveryBuiltInPlanImportsWithNothingToSay() throws {
        XCTAssertEqual(BuiltInPlans.all.map(\.id), ["FullBody", "UpperLower", "PushPullLegs", "AtHome"])
        for entry in BuiltInPlans.all {
            let plan = try imported(entry)
            XCTAssertEqual(plan.name, entry.name, entry.id)
            XCTAssertEqual(plan.schedule, .rotation, entry.id)
            // No units in the file: the plan takes the setting, whichever it is.
            XCTAssertEqual(plan.units, .kg, entry.id)
            XCTAssertEqual(try imported(entry, settings: Settings(units: .lb)).units, .lb, entry.id)
            XCTAssertFalse(entry.tagline.isEmpty)
            XCTAssertFalse(entry.about.isEmpty)
            XCTAssertFalse(entry.forWhom.isEmpty)
        }
        XCTAssertTrue(BuiltInPlans.buildYourOwn.contains("Create with a chatbot"),
                      "the suggestion names the button that does it")
    }

    // Y5: the splits are what the catalogue says — days a week from the repeat block, the two
    // A/B plans alternating across a fortnight, the other two on a week.
    func testTheSplitsAreWhatTheCatalogueSays() throws {
        for entry in BuiltInPlans.all {
            let plan = try imported(entry)
            XCTAssertEqual(plan.cycle.count % 7, 0, "\(entry.id): whole weeks")
            let weeks = plan.cycle.count / 7
            XCTAssertEqual(trainingDays(plan).count, entry.daysPerWeek * weeks,
                           "\(entry.id): \(entry.daysPerWeek) days a week")
            XCTAssertEqual(Set(trainingDays(plan)), Set(plan.days.indices),
                           "\(entry.id): every day is in the block and nothing else is")
        }
        for id in ["FullBody", "AtHome"] {
            let plan = try imported(try entry(id))
            XCTAssertEqual(plan.cycle.count, 14, id)
            XCTAssertEqual(plan.days.count, 2, id)
            XCTAssertEqual(trainingDays(plan), [0, 1, 0, 1, 0, 1], "\(id): A B A, then B A B")
        }
        let upperLower = try imported(try entry("UpperLower"))
        XCTAssertEqual(upperLower.cycle.count, 7)
        XCTAssertEqual(upperLower.days.map(\.name), ["Upper A", "Lower A", "Upper B", "Lower B"])
        XCTAssertEqual(trainingDays(upperLower), [0, 1, 2, 3])
        let ppl = try imported(try entry("PushPullLegs"))
        XCTAssertEqual(ppl.cycle.count, 7)
        XCTAssertEqual(ppl.days.map(\.name), ["Push", "Pull", "Legs"])
        XCTAssertEqual(trainingDays(ppl), [0, 1, 2, 0, 1, 2])
    }

    // Y6: every rep exercise carries the range the advice needs; every timed one has the
    // warning beep; no weight anywhere; bodyweight where there is nothing to load.
    func testRangesBeepsAndNoWeights() throws {
        let gymBodyweight: Set<String> = ["Plank", "Pull-Up", "Hanging Knee Raise"]
        for entry in BuiltInPlans.all {
            let plan = try imported(entry)
            for day in plan.days {
                for exercise in day.exercises {
                    let label = "\(entry.id) / \(day.name) / \(exercise.name)"
                    let timed = exercise.sets.allSatisfy(\.work.isTimed)
                    let reps = exercise.sets.allSatisfy { !$0.work.isTimed }
                    XCTAssertTrue(timed || reps, "\(label): one kind of set per exercise")
                    if reps {
                        let range = try XCTUnwrap(exercise.repRange, "\(label) needs a rep range")
                        XCTAssertTrue(range.min < range.max, label)
                        for set in exercise.sets {
                            guard case let .reps(.range(min, max)) = set.work else {
                                return XCTFail("\(label): every set is the range")
                            }
                            XCTAssertEqual(RepRange(min: min, max: max), range, label)
                        }
                    } else {
                        XCTAssertNil(exercise.repRange, "\(label): no range on a hold")
                        XCTAssertTrue(exercise.bodyweight, "\(label): a hold has nothing to load")
                        for set in exercise.sets {
                            guard case .duration = set.work else { return XCTFail("\(label): fixed holds only") }
                            XCTAssertNotNil(set.warningBeepSeconds, "\(label): the warning beep is on")
                        }
                    }
                    XCTAssertTrue(exercise.sets.allSatisfy { $0.weight == nil }, "\(label): no weight is guessed")
                    XCTAssertTrue(exercise.sets.allSatisfy(\.drops.isEmpty), "\(label): no drops")
                    if entry.id == "AtHome" {
                        XCTAssertTrue(exercise.bodyweight, "\(label): At Home is all bodyweight")
                    } else if exercise.bodyweight {
                        XCTAssertTrue(gymBodyweight.contains(exercise.name), "\(label): flagged only with nothing to load")
                    }
                }
            }
        }
    }

    // Y7: the shape of a day — biggest first, rest never climbing, a note on everything, and
    // a size that fits in about an hour.
    func testEveryDayIsBuiltBiggestFirst() throws {
        for entry in BuiltInPlans.all {
            let plan = try imported(entry)
            for day in plan.days {
                let label = "\(entry.id) / \(day.name)"
                XCTAssertTrue((5...7).contains(day.exercises.count), "\(label): \(day.exercises.count) exercises")
                let sets = day.exercises.reduce(0) { $0 + $1.sets.count }
                XCTAssertTrue((15...22).contains(sets), "\(label): \(sets) sets")
                let rests = day.exercises.map { $0.sets.first?.restSeconds ?? 0 }
                XCTAssertEqual(rests, rests.sorted(by: >), "\(label): rest never goes up as the day goes on")
                XCTAssertGreaterThanOrEqual(rests[0], entry.id == "AtHome" ? 75 : 150,
                                            "\(label): the day opens with the biggest lift")
                for exercise in day.exercises {
                    let notes = try XCTUnwrap(exercise.notes, "\(label) / \(exercise.name) has a cue")
                    XCTAssertFalse(notes.trimmed.isEmpty)
                    XCTAssertLessThanOrEqual(notes.count, 500)
                    for set in exercise.sets {
                        XCTAssertTrue((30...180).contains(set.restSeconds), "\(label) / \(exercise.name): rest \(set.restSeconds)")
                    }
                }
            }
            // The first thing anyone reads says what to do about the empty weight field.
            let opening = try XCTUnwrap(plan.days[0].exercises[0].notes).lowercased()
            XCTAssertTrue(opening.contains("weight"), "\(entry.id): the first note explains the weights")
        }
    }

    // Y8: one spelling per movement across all four plans and the practice plan, so moving
    // between routines carries history, prefill and records along (§6.9).
    func testOneSpellingPerMovementAcrossAllPlans() throws {
        var spellings: [String: Set<String>] = [:]
        var files = BuiltInPlans.all.map(\.id)
        files.append("PracticePlan")
        for file in files {
            let result = PlanImport.run(try text(file), settings: Settings(), now: now)
            let plan = try XCTUnwrap(result.plan, file)
            for exercise in plan.days.flatMap(\.exercises) {
                let key = exercise.name.lowercased().filter { $0.isLetter || $0.isNumber }
                spellings[key, default: []].insert(exercise.name)
            }
        }
        for (key, names) in spellings where names.count > 1 {
            XCTFail("\(key) is spelt \(names.sorted()) — one movement, one name")
        }
        XCTAssertGreaterThan(spellings.count, 30, "the four plans cover a real range of movements")
    }

    // Y9: every day runs through the real flattening, and takes about what the picker says.
    func testEveryDayRunsInAboutAnHour() throws {
        // The picker's minutes under v1.2's defaults, warm-up and walk included. (D57, v1.6:
        // a fresh install's warm-up is off; the plans' own numbers are judged with it on.)
        let v15 = Settings(warmUpSeconds: 300)
        for entry in BuiltInPlans.all {
            let plan = try imported(entry)
            var minutes: [Int] = []
            for index in plan.days.indices {
                let label = "\(entry.id) / \(plan.days[index].name)"
                let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: index, now: now), label)
                let sets = plan.days[index].exercises.reduce(0) { $0 + $1.sets.count }
                XCTAssertEqual(session.steps.count, sets, "\(label): one step per set, no drops")
                XCTAssertTrue(session.steps.allSatisfy { $0.status == .pending }, label)
                let estimate = try XCTUnwrap(BuiltInPlans.estimatedMinutes(plan, dayIndex: index, settings: v15), label)
                XCTAssertTrue((35...65).contains(estimate), "\(label): about \(estimate) min")
                minutes.append(estimate)
            }
            let typical = try XCTUnwrap(BuiltInPlans.estimatedMinutes(plan, settings: v15))
            XCTAssertEqual(typical % 5, 0, "\(entry.id): to the nearest five minutes")
            XCTAssertTrue(abs(typical - minutes.reduce(0, +) / minutes.count) <= 3, entry.id)
            XCTAssertTrue(BuiltInPlans.summary(entry, minutes: typical)
                .hasPrefix("\(entry.daysPerWeek) days a week · about \(typical) min · "), entry.id)
        }
        // No warm-up and no walk (v1.1's settings) takes the estimate down, never up.
        let plan = try imported(try entry("FullBody"))
        let full = try XCTUnwrap(BuiltInPlans.estimatedMinutes(plan, dayIndex: 0, settings: v15))
        let bare = try XCTUnwrap(BuiltInPlans.estimatedMinutes(plan, dayIndex: 0, settings: CoreTestSupport.classic))
        XCTAssertEqual(full - bare, (300 + 4 * 120) / 60, "the warm-up and four walks")
        XCTAssertNil(BuiltInPlans.estimatedMinutes(plan, dayIndex: 9, settings: v15))
    }

    // Y10: the model reads a built-in plan through the injected reader, refuses an unknown
    // one with a sentence, and saves it like any other plan — twice keeps both.
    @MainActor func testTheModelLoadsAndSavesABuiltInPlan() async throws {
        let root = CoreTestSupport.makeRoot("BuiltIn")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root), scheduler: RecordingAlerts(),
                             alerts: RecordingAlerts(),
                             bundledPlanJSON: { id in try? FixtureLoader.appResource(id, extension: "json") })
        await model.load()

        let missing = model.loadBuiltInPlan("NoSuchPlan", now: now)
        XCTAssertNil(missing.plan)
        XCTAssertEqual(missing.errors.first?.code, "E_NO_BUILT_IN")
        XCTAssertFalse(IssueText.friendly(try XCTUnwrap(missing.errors.first)).isEmpty)

        // Home before: the empty card names the picker.
        let empty = HomeStart.current(library: model.library, now: now)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.subtitle, HomeStart.emptySentence)

        let result = model.loadBuiltInPlan("FullBody", now: now)
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")
        let plan = try XCTUnwrap(result.plan)
        XCTAssertNil(model.plans.first, "loading saves nothing")
        await model.save(plan, conflict: .keepBoth, makeActive: true)
        XCTAssertEqual(model.plans.map(\.name), ["Full Body"])
        XCTAssertEqual(model.activePlanId, plan.id)

        let again = try XCTUnwrap(model.loadBuiltInPlan("FullBody", now: now).plan)
        await model.save(again, conflict: .keepBoth, makeActive: false)
        XCTAssertEqual(model.plans.map(\.name).sorted(), ["Full Body", "Full Body (2)"])
        XCTAssertEqual(model.activePlanId, plan.id, "the second copy did not take over")

        // Home after: the day is named, and Start says what it will do.
        let card = HomeStart.current(library: model.library, now: now)
        XCTAssertEqual(card.title, "Full Body A")
        XCTAssertEqual(card.buttonTitle, "Start Full Body A")
        XCTAssertEqual(card.exercises.first, "Barbell Back Squat")

        // And it is on disk as an ordinary plan.
        let reloaded = AppModel(store: Store(root: root))
        await reloaded.load()
        XCTAssertEqual(reloaded.plans.count, 2)
        XCTAssertEqual(reloaded.activePlanId, plan.id)
    }
}
