import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// V1 (v1.2) — the defects the 2026-09-07 code-health review found, each with the test that
/// would have caught it. Q1–Q9 in `docs/TEST_CASES.md`.
final class DefectFixesTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let settings = Settings()

    /// A superset whose round rest (120 s) is stated on its **first** member, while the other
    /// members fall back to the plan default (90 s). This is the shape that broke: the round
    /// rest lives in `groupRestSeconds`, and nothing but the exercise-level `restSeconds`
    /// puts it there.
    private static let supersetJSON = """
    { "schemaVersion": 1, "name": "Training", "units": "kg", "schedule": "rotation",
      "defaultRestSeconds": 90,
      "days": [ { "name": "Push", "exercises": [
        { "name": "Bench Press", "group": "A", "sets": 3, "reps": 8, "weight": 60, "restSeconds": 120 },
        { "name": "Row", "group": "A", "sets": 3, "reps": 8, "weight": 50 },
        { "name": "Curl", "sets": 2, "reps": 12, "weight": 15 }
      ] } ] }
    """

    private func imported(_ text: String) throws -> Plan {
        let result = PlanImport.run(text, settings: settings, now: now)
        return try XCTUnwrap(result.plan, "\(result.issues)")
    }

    /// The rest the engine would actually take after the last step of the group's first round.
    private func roundRest(_ plan: Plan) throws -> Int {
        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now))
        let last = try XCTUnwrap(session.steps.firstIndex { $0.isLastInRound })
        let advance = RestResolution.after(last, next: last + 1, steps: session.steps,
                                           exercises: session.exercises)
        guard case let .rest(seconds) = advance else {
            XCTFail("expected a rest after the round, got \(advance)")
            return -1
        }
        return seconds
    }

    // Q1: a no-op edit must not change the workout. It used to: the render dropped the
    // exercise-level rest, the re-import found none, and the round rest fell back to the
    // last member's own 90 s.
    func testEditingAPlanKeepsASupersetsRoundRest() throws {
        let original = try imported(Self.supersetJSON)
        XCTAssertEqual(try roundRest(original), 120)

        let result = PlanEdit.apply(.renameExercise(day: 0, exercise: 0, name: "Bench Press"),
                                    to: original, settings: settings, now: now)
        let edited = try XCTUnwrap(result.plan, "\(result.issues)")
        XCTAssertEqual(try roundRest(edited), 120,
                       "a rename must not change the between-round rest")
        XCTAssertEqual(edited.days[0].exercises[0].sets.map(\.groupRestSeconds), [120, 120, 120])
        XCTAssertEqual(edited.days[0].exercises[1].sets.map(\.groupRestSeconds), [120, 120, 120])
    }

    // Q2: the same, through every edit operation — each one re-imports, so each one could
    // have dropped it.
    func testEveryEditKeepsASupersetsRoundRest() throws {
        let plan = try imported(Self.supersetJSON)
        let operations: [PlanEdit.Operation] = [
            .renameExercise(day: 0, exercise: 1, name: "Cable Row"),
            .setWeight(day: 0, exercise: 0, weight: 65),
            .setReps(day: 0, exercise: 1, text: "10"),
            .setRepRange(day: 0, exercise: 0, text: "6-10"),
            .setSetCount(day: 0, exercise: 2, count: 3),
            .moveExercise(day: 0, from: 0, to: 1),
            .renameDay(day: 0, name: "Upper"),
            .duplicateDay(day: 0)
        ]
        for operation in operations {
            let result = PlanEdit.apply(operation, to: plan, settings: settings, now: now)
            let edited = try XCTUnwrap(result.plan, "\(operation): \(result.issues)")
            XCTAssertEqual(try roundRest(edited), 120, "\(operation) changed the round rest")
        }
    }

    // Q3: rest resolution reads `groupRestSeconds` for a grouped exercise, so editing rest on
    // one member is an edit to the round rest the group shares. Before v1.2 it wrote only the
    // per-set value, which nothing in a superset ever reads.
    func testEditingRestOnASupersetMemberChangesTheRoundRest() throws {
        let plan = try imported(Self.supersetJSON)
        let result = PlanEdit.apply(.setRest(day: 0, exercise: 1, seconds: 45),
                                    to: plan, settings: settings, now: now)
        let edited = try XCTUnwrap(result.plan, "\(result.issues)")
        XCTAssertEqual(try roundRest(edited), 45)
        for exercise in edited.days[0].exercises.prefix(2) {
            XCTAssertEqual(exercise.sets.map(\.groupRestSeconds), [45, 45, 45])
        }
        // The ungrouped exercise is untouched, and its own rest still comes from its sets.
        XCTAssertEqual(edited.days[0].exercises[2].sets.map(\.groupRestSeconds), [nil, nil])
    }

    // Q4: an ungrouped exercise gains no exercise-level rest — the round-rest fix must not
    // change what the renderer writes for everything else.
    func testRenderOnlyWritesAnExerciseLevelRestForAGroup() throws {
        let rendered = PlanJSON.render(try imported(Self.supersetJSON))
        let curl = try XCTUnwrap(rendered.range(of: "\"name\": \"Curl\""))
        let afterCurl = String(rendered[curl.upperBound...])
        let bench = try XCTUnwrap(rendered.range(of: "\"name\": \"Bench Press\""))
        let benchBlock = String(rendered[bench.upperBound...]).prefix(200)
        XCTAssertTrue(benchBlock.contains("\"restSeconds\": 120"),
                      "a group member carries the round rest at exercise level")
        XCTAssertFalse(afterCurl.prefix(120).contains("\"restSeconds\": 120"))
    }

    // Q5: typing a weight is not a fact about the workout. One keystroke used to be one
    // engine event *and one write of active-session.json*.
    func testSettingTheDisplayedWeightDoesNotForceAWrite() {
        var engine = CoreTestSupport.engine()
        let effects = engine.apply(.setWorkWeight(step: 0, weight: 62.5), now: now)
        XCTAssertFalse(effects.contains(.persist),
                       "a keystroke must not write the active session file")
        // It still takes effect, and the next real event carries it to disk.
        XCTAssertTrue(engine.apply(.logSet(step: 0, result: .reps(count: 8, weight: 62.5)),
                                   now: now).contains(.persist))
    }

    // Q6: a phase this version does not understand is a corrupt file, not a completed workout.
    func testAnUnknownPhaseFailsToDecode() throws {
        let data = Data(#"{"somethingElse":{"step":2}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Phase.self, from: data))
        // The two shapes it does understand still decode, including v1's `.transition`.
        XCTAssertEqual(try JSONDecoder().decode(Phase.self, from: Data(#"{"completed":{}}"#.utf8)),
                       .completed)
        XCTAssertEqual(try JSONDecoder().decode(Phase.self, from: Data(#"{"working":{"step":3}}"#.utf8)),
                       .working(step: 3))
    }

    // Q7: reading the store to export or to inspect a backup must not quietly rename a file
    // aside. That is a change, and the only place the user is told about it is the launch alert.
    func testExportingDoesNotSetCorruptFilesAside() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JimmsBroV1Tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsFile = root.appendingPathComponent("settings.json")
        try Data("not json at all".utf8).write(to: settingsFile)

        let store = Store(root: root)
        _ = await store.exportData(appVersion: "1.2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsFile.path),
                      "exporting must not move the file")

        // A real load still does set it aside, and says which file it was.
        let snapshot = await store.load()
        XCTAssertEqual(snapshot.corruptFiles, ["settings.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsFile.path))
    }

    // Q8: Retry is handed the failure, because dismissing the alert clears it first. Calling
    // it the old way — reading `saveFailure` after the dismissal — did nothing at all.
    @MainActor func testRetryWorksAfterTheAlertHasClearedTheFailure() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JimmsBroV1Tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil }, practiceJSON: { nil })
        await model.load()

        let broken = Settings(units: .lb, defaultRestSeconds: 120)
        model.saveFailure = .settings(broken)
        let captured = model.saveFailure          // what the alert's button captures
        model.saveFailure = nil                   // what dismissing the alert does
        await model.retrySaveFailure(captured)

        let snapshot = await Store(root: root).load()
        XCTAssertEqual(snapshot.settings, broken, "Retry must actually write the failed value")
        XCTAssertNil(model.saveFailure)
    }

    // Q20: one grouping rule, two screens. The Overview and Session detail had each written
    // this out, and a superset is where the two disagreed.
    func testSessionBlocksGroupsAndNamesTheSameWayForEveryScreen() throws {
        let plan = try imported(Self.supersetJSON)
        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now))
        let blocks = SessionBlocks.indices(session)
        XCTAssertEqual(blocks.count, 2, "the superset is one block, the curl another")
        XCTAssertEqual(blocks.flatMap { $0 }.sorted(), Array(session.steps.indices))
        // Ordered by where the steps sit, so a deferred block moves with them.
        XCTAssertEqual(blocks.map { $0.first }, blocks.map { $0.first }.sorted { ($0 ?? 0) < ($1 ?? 0) })

        XCTAssertEqual(SessionBlocks.names(session, blocks[0]), ["Bench Press", "Row"])
        XCTAssertEqual(SessionBlocks.names(session, blocks[1]), ["Curl"])
        XCTAssertTrue(SessionBlocks.namesRows(session, blocks[0]), "a superset must name its rows")
        XCTAssertFalse(SessionBlocks.namesRows(session, blocks[1]))
        XCTAssertEqual(SessionBlocks.blocks(session).map(\.steps), blocks, "the list both screens draw")
        XCTAssertEqual(SessionBlocks.blocks(session)[0].title, "Bench Press + Row",
                       "no duration until the block is finished")
    }

    // Q9: Replace all deletes before it writes, so its failure message must not claim that
    // nothing changed. Merge's may, because a merge only ever adds.
    func testRestoreFailureTellsTheTruthAboutEachMode() {
        XCTAssertTrue(Store.isDestructive(.replaceAll))
        XCTAssertFalse(Store.isDestructive(.merge))
        XCTAssertTrue(RestoreText.failure(.replaceAll).contains("already cleared"))
        XCTAssertFalse(RestoreText.failure(.replaceAll).lowercased().contains("nothing"))
        XCTAssertTrue(RestoreText.failure(.merge).contains("nothing you already had was changed"))
    }
}
