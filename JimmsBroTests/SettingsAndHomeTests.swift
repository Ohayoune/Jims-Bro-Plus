import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// M4 — N1, N2, N8, N9, N10, plus the Core state behind the Home, Plan detail and Import screens.
final class SettingsAndHomeTests: XCTestCase {
    private func makeRoot() -> URL { CoreTestSupport.makeRoot() }
    private func discard(_ root: URL) { CoreTestSupport.discard(root) }
    private func sample() throws -> String { try FixtureLoader.text("valid/weekly-rotation.json") }

    // N1: default units follow the locale's region, not its language.
    func testDefaultUnitsByLocale() throws {
        XCTAssertEqual(Settings.defaults(locale: Locale(identifier: "en_US")).units, .lb)
        for identifier in ["en_GB", "de_DE", "fr_CA"] {
            XCTAssertEqual(Settings.defaults(locale: Locale(identifier: identifier)).units, .kg,
                           "\(identifier) should default to kg")
        }
    }

    // N2: the weight step depends on the unit, not on the setting in force.
    func testWeightStepDefaults() {
        let settings = Settings()
        XCTAssertEqual(settings.weightStepKg, 2.5)
        XCTAssertEqual(settings.weightStepLb, 5.0)
        XCTAssertEqual(settings.weightStep(for: .kg), 2.5)
        XCTAssertEqual(settings.weightStep(for: .lb), 5.0)
    }

    // N8: a default rest of 0 is allowed, and a plan that states no rest inherits it.
    @MainActor func testDefaultRestOfZeroIsAllowedAndInherited() async throws {
        let root = makeRoot()
        defer { discard(root) }
        var settings = Settings()
        settings.defaultRestSeconds = 0
        let json = """
        { "schemaVersion": 1, "name": "No Rest", "units": "kg", "days": [
          { "name": "Day", "exercises": [ { "name": "Bench Press", "sets": 2, "reps": 10, "weight": 60 } ] } ] }
        """
        let result = PlanImport.run(json, settings: settings)
        XCTAssertEqual(result.errors, [])
        let plan = try XCTUnwrap(result.plan)
        XCTAssertEqual(plan.days[0].exercises[0].sets.map(\.restSeconds), [0, 0])

        // And the setting survives a round trip through the store at 0.
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        await model.setDefaultRest(0)
        XCTAssertEqual(model.settings.defaultRestSeconds, 0)
        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.settings.defaultRestSeconds, 0)
    }

    // N9: switching units leaves imported plans exactly as they were.
    @MainActor func testChangingUnitsLeavesExistingPlansUnchanged() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        XCTAssertEqual(model.settings.units, Settings.defaults().units)
        await model.setUnits(.kg)

        let imported = try XCTUnwrap(model.runImport(try sample()).plan)
        await model.save(imported, makeActive: true)
        let before = try XCTUnwrap(model.plans.first)
        XCTAssertEqual(before.units, .kg)

        await model.setUnits(.lb)
        XCTAssertEqual(model.settings.units, .lb)
        XCTAssertEqual(model.plans, [before], "existing plans must not be rewritten")
        XCTAssertEqual(model.plans.first?.units, .kg)

        // Only the prompt and unit-less future imports follow the new setting.
        XCTAssertTrue(Prompts.render(settings: model.settings).contains("\"units\": \"lb\""))
        let unitless = """
        { "schemaVersion": 1, "name": "Later", "days": [
          { "name": "D", "exercises": [ { "name": "Squat", "sets": 1, "reps": 5, "weight": 100 } ] } ] }
        """
        XCTAssertEqual(model.runImport(unitless).plan?.units, .lb)
        // A plan that states its units still wins over the setting.
        XCTAssertEqual(model.runImport(try sample()).plan?.units, .kg)
    }

    // N10: with no settings file, the defaults are used and written on first launch.
    @MainActor func testMissingSettingsFileWritesDefaults() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let settingsURL = root.appendingPathComponent("settings.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))

        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load(locale: Locale(identifier: "en_US"))
        XCTAssertEqual(model.settings, Settings.defaults(locale: Locale(identifier: "en_US")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path),
                      "first launch must write the defaults it used")

        let written = try StoreCoder.decode(Settings.self, from: Data(contentsOf: settingsURL))
        XCTAssertEqual(written, model.settings)

        // A later launch reads the file rather than re-deriving from the locale.
        let second = AppModel(store: Store(root: root), sampleJSON: { nil })
        await second.load(locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(second.settings.units, .lb, "the stored file must win over the locale")
    }

    // O1: the empty-Home sample import lands as an active plan.
    @MainActor func testSamplePlanImportsAndActivates() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let text = try sample()
        let model = AppModel(store: Store(root: root), sampleJSON: { text })
        await model.load()
        XCTAssertEqual(model.startCard, .noPlan)
        XCTAssertEqual(model.startCard.buttonTitle, "Import")

        let result = await model.importSamplePlan()
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(model.plans.count, 1)
        XCTAssertEqual(model.activePlanId, model.plans.first?.id)
        if case let .nextUp(_, _, dayName) = model.startCard {
            XCTAssertEqual(dayName, "Push")
            XCTAssertEqual(model.startCard.title, "Next up · Push")
            XCTAssertEqual(model.startCard.buttonTitle, "Start")
        } else {
            XCTFail("expected Next up, got \(model.startCard)")
        }

        // It survives relaunch, still active.
        let reloaded = AppModel(store: Store(root: root), sampleJSON: { text })
        await reloaded.load()
        XCTAssertEqual(reloaded.plans.count, 1)
        XCTAssertEqual(reloaded.activePlanId, reloaded.plans.first?.id)

        // A missing bundle resource reports an error instead of crashing.
        let bare = AppModel(store: Store(root: makeRoot()), sampleJSON: { nil })
        await bare.load()
        let missing = await bare.importSamplePlan()
        XCTAssertEqual(missing.errors.map(\.code), ["E_NO_SAMPLE"])
    }

    // The start card wording of SPEC §4.1 for each schedule.
    @MainActor func testStartCardStates() async throws {
        var library = PlanLibrary()
        XCTAssertEqual(StartCard.current(library: library), .noPlan)
        XCTAssertEqual(StartCard.noPlan.title, "No plan yet")

        // Weekday plan: today, then a rest day naming the next day and its weekday.
        var plan = CoreTestSupport.plan()
        plan.schedule = .weekday
        plan.days[0].weekday = .wednesday
        plan.cycle = [.day(0)]
        library.plans = [plan]
        library.activePlanId = plan.id
        let wednesday = CoreTestSupport.date(2)   // 2026-09-02 is a Wednesday
        let calendar = CoreTestSupport.utc()
        XCTAssertEqual(StartCard.current(library: library, now: wednesday, calendar: calendar),
                       .today(planId: plan.id, dayIndex: 0, dayName: "Push"))
        XCTAssertEqual(StartCard.current(library: library, now: wednesday, calendar: calendar).title,
                       "Today · Push")
        let thursday = CoreTestSupport.date(3)
        let rest = StartCard.current(library: library, now: thursday, calendar: calendar)
        XCTAssertEqual(rest, .restDay(planId: plan.id, dayIndex: 0, dayName: "Push",
                                      weekday: .wednesday, daysAway: 6))
        XCTAssertEqual(rest.title, "Rest day · next Push, Wed")
        XCTAssertEqual(rest.buttonTitle, "Start")

        // A plan whose cycle resolves to nothing offers no button.
        var empty = CoreTestSupport.plan()
        empty.cycle = []
        empty.schedule = .rotation
        library.plans = [empty]
        library.activePlanId = empty.id
        XCTAssertEqual(StartCard.current(library: library), .nothingScheduled)
        XCTAssertNil(StartCard.nothingScheduled.buttonTitle)

        // In progress wins over everything, and names the day and elapsed minutes.
        library.plans = [plan]
        library.activePlanId = plan.id
        library.engine = CoreTestSupport.engine()
        let card = StartCard.current(library: library,
                                     now: CoreTestSupport.now.addingTimeInterval(23 * 60 + 40))
        XCTAssertEqual(card.title, "Push in progress · 23 min")
        XCTAssertEqual(card.buttonTitle, "Resume")
        XCTAssertNil(card.target)
    }

    // O35 / O38: the repeat block chips, caption, and highlighted position.
    func testRepeatBlockChips() throws {
        let plan = try XCTUnwrap(PlanImport.run(try sample()).plan)
        let chips = CycleSquare.of(plan).map(\.name)
        XCTAssertEqual(chips, ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "Rest"])
        XCTAssertEqual(RepeatBlock.caption(plan), "repeats every 7 days")
        XCTAssertEqual(RepeatBlock.highlighted(plan, today: Date()), 0, "with no position yet, Next up is the first day")

        var advanced = plan
        PlanSchedule.advance(&advanced, completedDayName: "Push")
        XCTAssertEqual(RepeatBlock.highlighted(advanced, today: Date()), 1, "after Push, Pull is next")

        var weekly = plan
        weekly.schedule = .weekday
        XCTAssertEqual(RepeatBlock.caption(weekly), "Every week")
        XCTAssertNil(RepeatBlock.highlighted(weekly, today: Date()))
    }

    // O4: every error row carries a path, a message and a code, and drives the fix-it prompt.
    @MainActor func testImportErrorRowsAndFixItPrompt() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()

        let broken = try FixtureLoader.text("invalid/reps-zero.json")
        let result = model.runImport(broken)
        XCTAssertNil(result.plan)
        XCTAssertFalse(result.errors.isEmpty)
        for error in result.errors {
            XCTAssertFalse(error.code.isEmpty)
            XCTAssertFalse(error.message.isEmpty)
            XCTAssertTrue(error.code.hasPrefix("E_"))
        }
        let fixIt = Prompts.render(errors: result.errors)
        XCTAssertTrue(fixIt.hasPrefix(Prompts.marker))
        for error in result.errors.prefix(20) {
            XCTAssertTrue(fixIt.contains(error.message), "fix-it prompt must quote \(error.code)")
        }
    }

    // O5: the preview's warning list and day table counts come straight from the plan.
    @MainActor func testPreviewWarningsAndDayCounts() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()

        let result = model.runImport(try FixtureLoader.text("valid/unknown-fields.json"))
        let plan = try XCTUnwrap(result.plan)
        XCTAssertEqual(result.errors, [])
        XCTAssertFalse(plan.warnings.isEmpty, "this fixture is expected to warn")
        XCTAssertEqual(plan.warnings, result.issues.filter { $0.severity == .warning })
        XCTAssertTrue(plan.warnings.allSatisfy { $0.code.hasPrefix("W_") })

        let full = try XCTUnwrap(model.runImport(try sample()).plan)
        XCTAssertEqual(full.days.map(\.name), ["Push", "Pull", "Legs"])
        for day in full.days {
            let sets = day.exercises.reduce(0) { $0 + $1.sets.count }
            XCTAssertEqual(sets, flatten(day: day).filter { $0.dropIndex == 0 }.count,
                           "\(day.name)'s set count must match its flattened steps")
        }
    }

    // O6: Replace, Keep both and Cancel each do what the dialog says.
    @MainActor func testNameConflictChoices() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        let text = try sample()
        let first = try XCTUnwrap(model.runImport(text).plan)
        await model.save(first, makeActive: true)
        let originalId = try XCTUnwrap(model.activePlanId)

        // Cancel: nothing changes.
        let again = try XCTUnwrap(model.runImport(text).plan)
        XCTAssertNotNil(model.conflict(for: again))
        let cancelled = await model.save(again, conflict: .cancel)
        XCTAssertNil(cancelled)
        XCTAssertEqual(model.plans.count, 1)
        XCTAssertEqual(model.activePlanId, originalId)

        // Replace: same slot, same id, one plan.
        let replaced = await model.save(again, conflict: .replace)
        XCTAssertEqual(replaced, originalId)
        XCTAssertEqual(model.plans.count, 1)
        XCTAssertEqual(model.activePlanId, originalId)

        // Keep both: a second plan with a suffixed name.
        let kept = await model.save(try XCTUnwrap(model.runImport(text).plan), conflict: .keepBoth)
        XCTAssertEqual(model.plans.count, 2)
        XCTAssertNotEqual(kept, originalId)
        XCTAssertEqual(model.plans.map(\.name), ["Push Pull Legs", "Push Pull Legs (2)"])
        XCTAssertEqual(model.activePlanId, originalId, "keep both must not steal the active slot")

        // And all of it is on disk.
        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.plans.map(\.name), ["Push Pull Legs", "Push Pull Legs (2)"])
        XCTAssertEqual(reloaded.activePlanId, originalId)
    }

    // Plans list actions: activate, rename, delete, all persisted.
    @MainActor func testPlanListActionsPersist() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        let text = try sample()
        await model.save(try XCTUnwrap(model.runImport(text).plan), makeActive: true)
        await model.save(try XCTUnwrap(model.runImport(text).plan), conflict: .keepBoth)
        let second = try XCTUnwrap(model.plans.last?.id)

        await model.setActivePlan(second)
        XCTAssertEqual(model.activePlanId, second)
        await model.renamePlan(second, to: "  Renamed  ")
        XCTAssertEqual(model.plans.last?.name, "Renamed")
        XCTAssertTrue(model.plans.last?.sourceText.contains("\"Renamed\"") == true, "the text follows the name (TL36)")
        await model.renamePlan(second, to: "   ")
        XCTAssertEqual(model.plans.last?.name, "Renamed", "an empty name is ignored")

        await model.deletePlan(second)
        XCTAssertEqual(model.plans.count, 1)
        XCTAssertEqual(model.activePlanId, model.plans.first?.id,
                       "deleting the active plan falls back to the only one left")

        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.plans.count, 1)
        XCTAssertEqual(reloaded.activePlanId, reloaded.plans.first?.id)
    }

    /// L36 (D25/D26, v1.1): a second import is not made active unless asked; the choice persists.
    @MainActor func testImportMakeActiveToggle() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        let text = try sample()
        let first = try XCTUnwrap(model.runImport(text).plan)
        await model.save(first, makeActive: true)
        let firstId = try XCTUnwrap(model.activePlanId)

        let second = try XCTUnwrap(model.runImport(text).plan)
        await model.save(second, conflict: .keepBoth, makeActive: false)
        XCTAssertEqual(model.activePlanId, firstId, "declining the toggle must not switch Home's plan")

        let third = try XCTUnwrap(model.runImport(text).plan)
        let savedThirdId = await model.save(third, conflict: .keepBoth, makeActive: true)
        let thirdId = try XCTUnwrap(savedThirdId)
        XCTAssertEqual(model.activePlanId, thirdId)

        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.activePlanId, thirdId)
    }

    /// L37 (D25, v1.1): a whole plan put in a plan's place — Plan detail's Replace then, its Edit
    /// the text since v1.12's L5, saved as `PlanEdit.Operation.replacePlanJSON` through
    /// `AppModel.editPlan` — keeps the plan's id and active status, unlike the name-based conflict
    /// flow, and persists. (Say what should change's Apply is TN35's.)
    @MainActor func testReplacePlanKeepsIdAndActiveStatus() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        let original = try XCTUnwrap(model.runImport(try sample()).plan)
        await model.save(original, makeActive: true)
        let id = try XCTUnwrap(model.activePlanId)

        var revised = original
        revised.name = "A Completely Different Name"
        let text = PlanJSON.render(revised)
        let issues = await model.editPlan(id, .replacePlanJSON(text: text))
        XCTAssertEqual(issues, [])
        XCTAssertEqual(model.plans.count, 1, "replace does not add a second plan")
        XCTAssertEqual(model.plans.first?.id, id)
        XCTAssertEqual(model.plans.first?.name, "A Completely Different Name")
        XCTAssertEqual(model.activePlanId, id, "replacing the active plan keeps it active")

        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.plans.first?.name, "A Completely Different Name")
        XCTAssertEqual(reloaded.activePlanId, id)

        let missing = await model.editPlan(UUID(), .replacePlanJSON(text: text))
        XCTAssertEqual(missing.map(\.code), ["E_EDIT_INVALID"], "a missing id is a no-op")
        XCTAssertEqual(model.plans.map(\.id), [id])
    }

    // SPEC §8.3: a corrupt file surfaces as one alert and the app carries on.
    @MainActor func testCorruptFileSurfacesOnceAtLaunch() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        await model.save(try XCTUnwrap(model.runImport(try sample()).plan), makeActive: true)
        try Data("wrecked".utf8).write(to: root.appendingPathComponent("plans.json"))

        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.corruptFiles, ["plans.json"])
        XCTAssertTrue(reloaded.showCorruptAlert)
        XCTAssertEqual(reloaded.plans, [], "the app continues with the file treated as absent")
        reloaded.dismissCorruptAlert()
        XCTAssertFalse(reloaded.showCorruptAlert)

        // A clean launch raises nothing.
        let clean = AppModel(store: Store(root: makeRoot()), sampleJSON: { nil })
        await clean.load()
        XCTAssertFalse(clean.showCorruptAlert)
    }

}
