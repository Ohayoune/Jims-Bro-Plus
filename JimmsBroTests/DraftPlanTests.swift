import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Z3 (v1.5) — D52: a plan in several pastes. The outline, the days, the assembly, the file,
/// the model, the prompts.
final class DraftPlanTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let settings = Settings()

    private let outlineJSON = """
    {
      "schemaVersion": 1, "name": "Push Pull Legs", "units": "kg", "defaultRestSeconds": 90,
      "schedule": "rotation", "cycle": ["Push", "Pull", "Legs", "rest"],
      "days": [ { "name": "Push" }, { "name": "Pull" }, { "name": "Legs" } ]
    }
    """
    private let pushDay = #"{ "name": "Push", "exercises": [ { "name": "Barbell Bench Press", "sets": 4, "reps": "6-8", "weight": 80, "restSeconds": 150 }, { "name": "Plank", "sets": 3, "durationSeconds": 45, "bodyweight": true, "restSeconds": 45 } ] }"#
    private let pullDay = #"{ "name": "Pull", "exercises": [ { "name": "Barbell Row", "sets": 3, "reps": "8-10", "weight": 70, "restSeconds": 120 } ] }"#
    private let legsExercises = #"[ { "name": "Barbell Back Squat", "sets": 4, "reps": "5", "repRange": "4-6", "weight": 100, "restSeconds": 180 } ]"#

    private func draft() throws -> PlanDraft {
        let read = PlanDrafting.outline(outlineJSON, settings: settings, now: now)
        XCTAssertTrue(read.issues.isEmpty, "\(read.issues)")
        return try XCTUnwrap(read.draft)
    }

    // Z11: the outline — empty days allowed, a full plan accepted, the ordinary refusals kept.
    func testTheOutline() throws {
        let d = try draft()
        XCTAssertEqual(d.outline.name, "Push Pull Legs")
        XCTAssertEqual(d.outline.days.map(\.name), ["Push", "Pull", "Legs"])
        XCTAssertEqual(d.outline.cycle, [.day(0), .day(1), .day(2), .rest])
        XCTAssertEqual(d.dayTexts, [nil, nil, nil])
        XCTAssertEqual(d.filled, 0)
        XCTAssertFalse(d.isComplete)
        XCTAssertEqual(d.progress, "0 of 3 days pasted")

        // A chatbot that wrote the whole plan anyway: its days arrive filled.
        let whole = PlanDrafting.outline(try FixtureLoader.text("valid/weekly-rotation.json"), settings: settings, now: now)
        let full = try XCTUnwrap(whole.draft)
        XCTAssertTrue(full.isComplete)
        XCTAssertEqual(full.filled, 3)
        XCTAssertTrue(try XCTUnwrap(full.dayTexts[0]).contains("Barbell Bench Press"))

        // Everything else the importer refuses, it still refuses.
        XCTAssertEqual(PlanDrafting.outline(Prompts.outline(settings: settings), settings: settings, now: now).issues.first?.code, "E_PROMPT_PASTED")
        XCTAssertEqual(PlanDrafting.outline("not json", settings: settings, now: now).issues.first?.code, "E_NOT_JSON")
        XCTAssertEqual(PlanDrafting.outline(#"{ "name": "X", "days": [] }"#, settings: settings, now: now).issues.first?.code, "E_NO_DAYS")
        let unknownDay = PlanDrafting.outline(#"{ "name": "X", "cycle": ["A", "B"], "days": [ { "name": "A" } ] }"#, settings: settings, now: now)
        XCTAssertEqual(unknownDay.issues.first?.code, "E_CYCLE_UNKNOWN_DAY")
        // And the ordinary importer still refuses an empty day when it is not an outline.
        XCTAssertEqual(PlanImport.run(outlineJSON, settings: settings, now: now).errors.first?.code, "E_NO_EXERCISES")
    }

    // Z12: a day into its slot — named by the slot, chosen by name from a plan, wrapped from a
    // list, refused with the slot's own path.
    func testADayIntoItsSlot() throws {
        var d = try draft()
        let push = PlanDrafting.day(pushDay, into: d, index: 0, settings: settings, now: now)
        XCTAssertTrue(push.issues.isEmpty, "\(push.issues)")
        d = try XCTUnwrap(push.draft)
        XCTAssertEqual(d.filled, 1)

        // A day with the wrong name takes the slot's: the outline decided the names.
        let renamed = PlanDrafting.day(pushDay.replacingOccurrences(of: "\"Push\"", with: "\"Chest\""), into: d, index: 1, settings: settings, now: now)
        XCTAssertNotNil(renamed.draft)
        XCTAssertEqual(PlanDrafting.dayObject(pushDay.replacingOccurrences(of: "\"Push\"", with: "\"Chest\""), for: d.outline.days[1], index: 1).object?["name"]?.string, "Pull")

        // A whole plan with several days: the one named like the slot is taken.
        let plan = try FixtureLoader.text("valid/weekly-rotation.json")
        let fromPlan = PlanDrafting.day(plan, into: d, index: 1, settings: settings, now: now)
        d = try XCTUnwrap(fromPlan.draft, "\(fromPlan.issues)")
        let chosen = try XCTUnwrap(PlanDrafting.dayObject(plan, for: d.outline.days[1], index: 1).object)
        XCTAssertEqual(chosen["name"]?.string, "Pull")
        XCTAssertEqual(chosen["exercises"]?.array?.count, 5, "the fixture's Pull day")

        // A bare list of exercises is a day of them.
        let legs = PlanDrafting.day(legsExercises, into: d, index: 2, settings: settings, now: now)
        d = try XCTUnwrap(legs.draft, "\(legs.issues)")
        XCTAssertTrue(d.isComplete)

        // Refusals name the slot, not "Day 1".
        let bad = PlanDrafting.day(#"{ "exercises": [ { "name": "Curl", "sets": 2, "reps": "ten" } ] }"#, into: d, index: 2, settings: settings, now: now)
        XCTAssertNil(bad.draft)
        let error = try XCTUnwrap(bad.issues.first { $0.severity == .error })
        XCTAssertEqual(error.code, "E_REPS_INVALID")
        XCTAssertEqual(error.path, "days[2].exercises[0].reps")
        XCTAssertTrue(IssueText.friendly(error).hasPrefix("Day 3, exercise 1"), IssueText.friendly(error))
        XCTAssertEqual(d.filled, 3, "a refused paste changes nothing")

        // Two days where one is wanted, and none of them named like the slot.
        let two = PlanDrafting.day("[\(pushDay), \(pullDay)]", into: d, index: 2, settings: settings, now: now)
        XCTAssertEqual(two.issues.first?.code, "E_EDIT_INVALID")
        XCTAssertEqual(two.issues.first?.path, "days[2]")
        XCTAssertEqual(PlanDrafting.day(pushDay, into: d, index: 9, settings: settings, now: now).issues.first?.code, "E_EDIT_INVALID")
        XCTAssertEqual(PlanDrafting.day("", into: d, index: 0, settings: settings, now: now).issues.first?.code, "E_EMPTY")
    }

    // Z13: the assembly — the outline's header and block, every day's exercises, once through
    // the ordinary import, canonical text.
    func testTheAssembly() throws {
        var d = try draft()
        XCTAssertEqual(PlanDrafting.assemble(d, settings: settings, now: now).errors.first?.code, "E_DRAFT_INCOMPLETE")
        XCTAssertEqual(PlanDrafting.assembledText(d).issues.first?.message, "3 of 3 days still to paste.")

        d = try XCTUnwrap(PlanDrafting.day(pushDay, into: d, index: 0, settings: settings, now: now).draft)
        d = try XCTUnwrap(PlanDrafting.day(pullDay, into: d, index: 1, settings: settings, now: now).draft)
        d = try XCTUnwrap(PlanDrafting.day(legsExercises, into: d, index: 2, settings: settings, now: now).draft)
        let result = PlanDrafting.assemble(d, settings: settings, now: now)
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")
        let plan = try XCTUnwrap(result.plan)
        XCTAssertEqual(plan.name, "Push Pull Legs")
        XCTAssertEqual(plan.units, .kg)
        XCTAssertEqual(plan.cycle, [.day(0), .day(1), .day(2), .rest])
        XCTAssertEqual(plan.days.map(\.name), ["Push", "Pull", "Legs"])
        XCTAssertEqual(plan.days.map { $0.exercises.count }, [2, 1, 1])
        XCTAssertEqual(plan.days[0].exercises[0].sets.first?.restSeconds, 150)
        XCTAssertEqual(plan.days[2].exercises[0].repRange, RepRange(min: 4, max: 6))
        XCTAssertEqual(plan.sourceText, PlanJSON.render(plan), "the canonical rendering, as after any edit")
        // And it is a plan the importer would take again.
        XCTAssertTrue(PlanImport.run(plan.sourceText, settings: settings, now: now).issues.isEmpty)

        // A weekday outline lends its weekdays to the days.
        let weekday = try XCTUnwrap(PlanDrafting.outline(#"{ "name": "W", "schedule": "weekday", "days": [ { "name": "A", "weekday": "monday" } ] }"#, settings: settings, now: now).draft)
        let filled = try XCTUnwrap(PlanDrafting.day(legsExercises, into: weekday, index: 0, settings: settings, now: now).draft)
        XCTAssertEqual(PlanDrafting.assemble(filled, settings: settings, now: now).plan?.days.first?.weekday, .monday)
    }

    // Z14: the file — written, read at launch, set aside when corrupt, gone with the plan.
    @MainActor func testTheFile() async throws {
        let root = CoreTestSupport.makeRoot("Draft")
        defer { CoreTestSupport.discard(root) }
        let store = Store(root: root)
        let model = AppModel(store: store)
        await model.load()
        XCTAssertNil(model.draft)

        let r1 = await model.startDraft(outlineJSON, now: now)
        XCTAssertTrue(r1.isEmpty)
        XCTAssertEqual(model.draft?.dayTexts.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("draft.json").path))
        let r2 = await model.pasteDraftDay(pushDay, into: 0, now: now)
        XCTAssertTrue(r2.isEmpty)

        // Relaunch: the draft is where it was.
        let relaunched = AppModel(store: Store(root: root))
        await relaunched.load()
        XCTAssertEqual(relaunched.draft?.filled, 1)
        XCTAssertEqual(relaunched.draft?.outline.name, "Push Pull Legs")
        XCTAssertEqual(relaunched.draft?.dayTexts[0], pushDay)

        // The decoder's rule: what has a default is optional.
        let sparse = Data("""
        { "fileVersion": 1, "outlineText": \(try jsonString(outlineJSON)), "outline": \(String(decoding: try StoreCoder.encoder.encode(try draft().outline), as: UTF8.self)) }
        """.utf8)
        let decoded = try StoreCoder.decode(PlanDraft.self, from: sparse)
        XCTAssertEqual(decoded.dayTexts, [nil, nil, nil])

        // Corrupt: set aside, reported, the app carries on without a draft.
        try Data("{ not json".utf8).write(to: root.appendingPathComponent("draft.json"))
        let corrupt = AppModel(store: Store(root: root))
        await corrupt.load()
        XCTAssertNil(corrupt.draft)
        XCTAssertEqual(corrupt.corruptFiles, ["draft.json"])
        XCTAssertTrue(corrupt.showCorruptAlert)

        // Discard removes the file; Delete all data removes everything.
        let r3 = await corrupt.startDraft(outlineJSON, now: now)
        XCTAssertTrue(r3.isEmpty)
        await corrupt.discardDraft()
        XCTAssertNil(corrupt.draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("draft.json").path))
        let r4 = await corrupt.startDraft(outlineJSON, now: now)
        XCTAssertTrue(r4.isEmpty)
        await corrupt.deleteAllData()
        XCTAssertNil(corrupt.draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("draft.json").path))
    }

    // Z15: the model end to end — outline, days, review, save, and the draft gone.
    @MainActor func testTheModelEndToEnd() async throws {
        let root = CoreTestSupport.makeRoot("Draft")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root))
        await model.load()
        XCTAssertEqual(model.assembleDraft(now: now).errors.first?.code, "E_EDIT_INVALID", "no draft yet")
        let r5 = await model.pasteDraftDay(pushDay, into: 0, now: now)
        XCTAssertEqual(r5.first?.code, "E_EDIT_INVALID")

        let r6 = await model.startDraft(outlineJSON, now: now)
        XCTAssertTrue(r6.isEmpty)
        XCTAssertNil(model.assembleDraft(now: now).plan)
        let r7 = await model.pasteDraftDay(pushDay, into: 0, now: now)
        XCTAssertTrue(r7.isEmpty)
        let r8 = await model.pasteDraftDay(pullDay, into: 1, now: now)
        XCTAssertTrue(r8.isEmpty)
        let bad = await model.pasteDraftDay("[1, 2]", into: 2, now: now)
        XCTAssertEqual(bad.first?.code, "E_NOT_A_PLAN")
        XCTAssertEqual(model.draft?.filled, 2)
        let r9 = await model.pasteDraftDay(legsExercises, into: 2, now: now)
        XCTAssertTrue(r9.isEmpty)
        XCTAssertTrue(model.draft?.isComplete ?? false)

        let result = model.assembleDraft(now: now)
        let plan = try XCTUnwrap(result.plan, "\(result.issues)")
        XCTAssertTrue(model.plans.isEmpty, "assembling saves nothing")
        let id = await model.saveDraftPlan(plan, makeActive: true)
        XCTAssertNotNil(id)
        XCTAssertEqual(model.plans.map(\.name), ["Push Pull Legs"])
        XCTAssertEqual(model.activePlanId, id)
        XCTAssertNil(model.draft, "saved, so the draft goes")
        XCTAssertNil(model.saveFailure)

        // A cancelled name conflict keeps the draft.
        let r10 = await model.startDraft(outlineJSON, now: now)
        XCTAssertTrue(r10.isEmpty)
        for (index, text) in [pushDay, pullDay, legsExercises].enumerated() {
            let r11 = await model.pasteDraftDay(text, into: index, now: now)
            XCTAssertTrue(r11.isEmpty)
        }
        let again = try XCTUnwrap(model.assembleDraft(now: now).plan)
        XCTAssertNotNil(model.conflict(for: again))
        let r12 = await model.saveDraftPlan(again, conflict: .cancel, makeActive: false)
        XCTAssertNil(r12)
        XCTAssertNotNil(model.draft)
        let r13 = await model.saveDraftPlan(again, conflict: .keepBoth, makeActive: false)
        XCTAssertNotNil(r13)
        XCTAssertEqual(model.plans.map(\.name).sorted(), ["Push Pull Legs", "Push Pull Legs (2)"])
        XCTAssertNil(model.draft)

        // Home is unchanged by any of this: the card is the saved plan's.
        XCTAssertEqual(HomeStart.current(library: model.library, now: now).title, "Push")
    }

    // Z16: the prompts — the marker, the outline in the day prompt, the rules shared with the
    // plan prompt so they cannot drift, and sizes a free chatbot can take.
    func testThePrompts() throws {
        let outline = Prompts.outline(settings: Settings(units: .lb, defaultRestSeconds: 120))
        XCTAssertTrue(outline.hasPrefix(PlanImport.promptMarker))
        XCTAssertTrue(outline.contains("\"units\": \"lb\""))
        XCTAssertTrue(outline.contains("\"defaultRestSeconds\": 120"))
        XCTAssertTrue(outline.contains("NO exercises yet"))
        XCTAssertFalse(outline.contains("{{"))
        XCTAssertLessThan(outline.count, 2_000)

        let d = try draft()
        let day = Prompts.day(outline: d.outline, dayIndex: 1, settings: settings)
        XCTAssertTrue(day.hasPrefix(PlanImport.promptMarker))
        XCTAssertTrue(day.contains("ONLY the day \"Pull\""))
        XCTAssertTrue(day.contains("\"name\": \"Pull\""))
        XCTAssertTrue(day.contains("Push Pull Legs · kg · rotation"))
        XCTAssertTrue(day.contains("Repeat block: Push, Pull, Legs, rest"))
        XCTAssertTrue(day.contains("Days: Push, Pull, Legs"))
        XCTAssertTrue(day.contains("weight: number in kg"))
        XCTAssertFalse(day.contains("{{"))
        XCTAssertFalse(day.contains("- days:"), "the outline settled the days")
        XCTAssertFalse(day.contains("- cycle:"))
        XCTAssertLessThan(day.count, 4_000)

        // Every rule the day prompt gives is a rule the plan prompt gives, word for word.
        let planRules = Set(Prompts.planRules.split(separator: "\n").map(String.init))
        for line in Prompts.dayRules.split(separator: "\n").map(String.init) {
            XCTAssertTrue(planRules.contains(line), "the day prompt has a rule of its own: \(line)")
        }
        XCTAssertTrue(Prompts.dayRules.contains("- inReserve:"))

        // The prompts do not survive being pasted back as a plan.
        XCTAssertEqual(PlanImport.run(day, settings: settings, now: now).errors.first?.code, "E_PROMPT_PASTED")

        // A seven-day weekday outline still fits.
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        let days = zip(names, weekdays).map { #"{ "name": "\#($0) Full Body Session", "weekday": "\#($1)" }"# }.joined(separator: ", ")
        let week = try XCTUnwrap(PlanDrafting.outline(#"{ "name": "Seven", "schedule": "weekday", "days": [\#(days)] }"#, settings: settings, now: now).draft)
        XCTAssertLessThan(Prompts.day(outline: week.outline, dayIndex: 6, settings: settings).count, 4_000)
        XCTAssertTrue(Prompts.day(outline: week.outline, dayIndex: 6, settings: settings).contains("Sun Full Body Session (sunday)"))
    }

    private func jsonString(_ text: String) throws -> String {
        String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
    }
}
