import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// V2 (v1.2) — G59 and Q12–Q17: a file written by an older version still decodes.
///
/// `examples/store/v1/` holds one real file of every type, captured from v1.1 before v1.2 added
/// a field to anything. These tests are the reason a later release can add a setting without
/// silently moving every user's plans and history aside as "corrupt". If one of them goes red,
/// the fix is in `JimmsBro/Core/Persistence.swift` — never in the fixture.
final class StoreMigrationTests: XCTestCase {
    private func decode<T: Codable>(_ type: T.Type, _ file: String) throws -> T {
        try StoreCoder.decode(type, from: try FixtureLoader.data("store/v1/\(file)"))
    }

    // Q12: a v1.1 settings.json still loads, with every value it held.
    func testV1SettingsDecode() throws {
        let settings = try decode(Settings.self, "settings.json")
        XCTAssertEqual(settings.units, .kg)
        XCTAssertEqual(settings.defaultRestSeconds, 90)
        XCTAssertEqual(settings.weightStepKg, 2.5)
        XCTAssertEqual(settings.weightStepLb, 5)
        XCTAssertTrue(settings.sound)
        XCTAssertTrue(settings.keepAwake)
    }

    // Q13: a v1.1 plans.json still loads, superset round rest and all.
    func testV1PlansDecode() throws {
        let payload = try decode(PlansPayload.self, "plans.json")
        let plan = try XCTUnwrap(payload.plans.first)
        XCTAssertEqual(payload.activePlanId, plan.id)
        XCTAssertEqual(plan.name, "Circuit Day")
        XCTAssertEqual(plan.units, .kg)
        XCTAssertEqual(plan.cyclePosition, 0)
        XCTAssertEqual(plan.days.count, 1)
        XCTAssertEqual(plan.days[0].exercises.count, 4)
        XCTAssertEqual(plan.days[0].exercises[0].group, "A")
        XCTAssertEqual(plan.days[0].exercises[0].sets.first?.groupRestSeconds, 90)
        // And it still runs: the shape survived, not just the bytes.
        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: Date()))
        XCTAssertFalse(session.steps.isEmpty)
    }

    // Q14: a v1.1 session.json still loads, with what was logged and what was skipped.
    func testV1SessionDecodes() throws {
        let session = try decode(Session.self, "session.json")
        XCTAssertEqual(session.dayName, "Circuit")
        XCTAssertNotNil(session.endedAt)
        XCTAssertEqual(session.steps.filter { $0.status == .logged }.count, 4)
        XCTAssertTrue(session.steps.contains { $0.status == .skipped })
        XCTAssertEqual(session.steps.first?.result, .reps(count: 10, weight: 20))
        XCTAssertEqual(session.steps.first?.setSeconds, 34)
    }

    // Q15: a workout interrupted mid-rest resumes from a v1.1 file (SPEC §5.4).
    func testV1ActiveSessionDecodesAndResumes() throws {
        let active = try decode(ActiveSession.self, "active-session.json")
        guard case let .resting(rest) = active.phase else {
            return XCTFail("expected the frozen file to be mid-rest, got \(active.phase)")
        }
        XCTAssertEqual(rest.nextStep, 4)
        XCTAssertEqual(active.workWeight, 20)
        XCTAssertEqual(active.lastCompletedStep, 3)
        XCTAssertTrue(active.canUndo)
        let engine = SessionEngine(active: active)
        XCTAssertEqual(engine.loggedCount, 4)
    }

    // Q16: the general rule. A file may leave out anything with a default; it may not leave out
    // what makes the thing itself.
    func testOptionalKeysMayBeMissingAndIdentityKeysMayNot() throws {
        let minimalSettings = Data(#"{"fileVersion":1}"#.utf8)
        XCTAssertEqual(try StoreCoder.decode(Settings.self, from: minimalSettings), Settings())

        // A plan with only its identity: no cycle, no warnings, no sourceText, no id.
        let minimalPlan = Data("""
        {"fileVersion":1,"name":"P","units":"kg","schedule":"rotation",
         "days":[{"name":"D","exercises":[{"name":"E",
           "sets":[{"work":{"reps":{"_0":{"fixed":{"_0":8}}}},"restSeconds":60}]}]}]}
        """.utf8)
        let plan = try StoreCoder.decode(Plan.self, from: minimalPlan)
        XCTAssertEqual(plan.name, "P")
        XCTAssertEqual(plan.cycle, [.day(0)], "a plan with no cycle repeats its days in order")
        XCTAssertEqual(plan.warnings, [])
        XCTAssertEqual(plan.days[0].exercises[0].sets[0].drops, [])
        XCTAssertFalse(plan.days[0].exercises[0].bodyweight)

        // But a day with no name is not a day.
        let broken = Data("""
        {"fileVersion":1,"name":"P","units":"kg","schedule":"rotation",
         "days":[{"exercises":[]}]}
        """.utf8)
        XCTAssertThrowsError(try StoreCoder.decode(Plan.self, from: broken))
    }

    // Q17: a reader reads its own version and older, and refuses only what is newer than it.
    func testFileVersions() throws {
        let older = Data(#"{"fileVersion":0,"units":"lb"}"#.utf8)
        XCTAssertEqual(try StoreCoder.decode(Settings.self, from: older).units, .lb)
        let newer = Data(#"{"fileVersion":2,"units":"lb"}"#.utf8)
        XCTAssertThrowsError(try StoreCoder.decode(Settings.self, from: newer)) { error in
            XCTAssertEqual(error as? StoreError, .unsupportedFileVersion(2))
        }
    }

    // Q18: a whole store of v1.1 files loads through the real Store, with nothing set aside.
    func testAStoreOfV1FilesLoadsWithNoCorruption() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JimmsBroV2Tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        for name in ["settings.json", "plans.json", "active-session.json"] {
            try FixtureLoader.data("store/v1/\(name)").write(to: root.appendingPathComponent(name))
        }
        try FixtureLoader.data("store/v1/session.json")
            .write(to: sessions.appendingPathComponent("frozen.json"))

        let snapshot = await Store(root: root).load()
        XCTAssertEqual(snapshot.corruptFiles, [], "a v1.1 store must not read as corrupt")
        XCTAssertTrue(snapshot.hasSettingsFile)
        XCTAssertEqual(snapshot.plans.count, 1)
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertNotNil(snapshot.active)
    }
}
