import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// R5.4 (v1.1) — restoring a backup (D31): K22–K26. The export format was always the on-disk
/// format (SPEC §8.5); this is the read side of it.
final class RestoreTests: XCTestCase {
    private let now = CoreTestSupport.now

    private func makeRoot() -> URL { CoreTestSupport.makeRoot() }
    private func discard(_ root: URL) { CoreTestSupport.discard(root) }

    private func session(_ name: String, daysAgo: Int) -> Session {
        var s = CoreTestSupport.completed([10, 10, 8],
                                          start: CoreTestSupport.days(-daysAgo))
        s.id = UUID()
        s.dayName = name
        return s
    }

    /// A store holding one plan and `sessions`, and the backup bytes for it.
    private func seeded(_ root: URL, plans: [Plan], sessions: [Session],
                        settings: Settings = Settings()) async throws -> Data {
        let store = Store(root: root)
        try await store.save(settings: settings)
        try await store.save(plans: plans, activePlanId: plans.first?.id)
        for session in sessions { try await store.save(session: session) }
        let data = await store.exportData(appVersion: "1.1")
        return try XCTUnwrap(data)
    }

    // K22: reading a backup says what is in it and changes nothing.
    func testReadingABackupChangesNothing() async throws {
        let source = makeRoot(), target = makeRoot()
        defer { discard(source); discard(target) }
        let plan = CoreTestSupport.plan()
        let data = try await seeded(source, plans: [plan], sessions: [session("Push", daysAgo: 3),
                                                                      session("Pull", daysAgo: 1)])

        let store = Store(root: target)
        try await store.save(plans: [], activePlanId: nil)
        let (document, summary) = try await store.readBackup(data)
        XCTAssertEqual(summary.plans, 1)
        XCTAssertEqual(summary.sessions, 2)
        XCTAssertEqual(summary.newPlans, 1, "nothing here yet, so everything would be added")
        XCTAssertEqual(summary.newSessions, 2)
        XCTAssertEqual(summary.appVersion, "1.1")
        XCTAssertEqual(document.plans.count, 1)
        // Reading is a read: the target store is untouched until a restore is asked for.
        let after = await store.load()
        XCTAssertTrue(after.plans.isEmpty)
        XCTAssertTrue(after.sessions.isEmpty)
    }

    // K23: Replace all ends with exactly what the backup held, and nothing else.
    func testReplaceAllEndsWithExactlyTheBackup() async throws {
        let source = makeRoot(), target = makeRoot()
        defer { discard(source); discard(target) }
        var settings = Settings()
        settings.units = .lb
        settings.defaultRestSeconds = 120
        let plan = CoreTestSupport.plan()
        let backup = try await seeded(source, plans: [plan], sessions: [session("Push", daysAgo: 3)],
                                      settings: settings)

        // The target has different data of its own, which Replace all must remove.
        let store = Store(root: target)
        let mine = CoreTestSupport.plan()
        try await store.save(plans: [mine], activePlanId: mine.id)
        try await store.save(session: session("Legs", daysAgo: 1))

        let (document, _) = try await store.readBackup(backup)
        try await store.restore(document, mode: .replaceAll)
        let after = await store.load()
        XCTAssertEqual(after.plans.map(\.id), [plan.id])
        XCTAssertEqual(after.sessions.map(\.dayName), ["Push"])
        XCTAssertEqual(after.activePlanId, plan.id, "the backup's active plan comes back active")
        XCTAssertEqual(after.settings.units, .lb, "Replace all takes the backup's settings")
        XCTAssertEqual(after.settings.defaultRestSeconds, 120)
        XCTAssertTrue(after.corruptFiles.isEmpty)
    }

    // K24: Merge adds what is missing and never overwrites what is here.
    func testMergeAddsOnlyWhatIsMissing() async throws {
        let source = makeRoot(), target = makeRoot()
        defer { discard(source); discard(target) }
        let shared = session("Push", daysAgo: 5)
        let onlyInBackup = session("Pull", daysAgo: 4)
        let plan = CoreTestSupport.plan()
        let backup = try await seeded(source, plans: [plan], sessions: [shared, onlyInBackup])

        let store = Store(root: target)
        var mine = CoreTestSupport.plan()
        mine.name = "Mine"
        try await store.save(plans: [mine], activePlanId: mine.id)
        // The same session id, edited here since the backup was taken.
        var edited = shared
        edited.dayName = "Push (edited here)"
        try await store.save(session: edited)
        try await store.save(session: session("Legs", daysAgo: 1))
        var settings = Settings()
        settings.units = .lb
        try await store.save(settings: settings)

        let (document, summary) = try await store.readBackup(backup)
        XCTAssertEqual(summary.sessions, 2)
        XCTAssertEqual(summary.newSessions, 1, "one of the two is already here, by id")
        try await store.restore(document, mode: .merge)

        let after = await store.load()
        XCTAssertEqual(Set(after.sessions.map(\.dayName)),
                       ["Push (edited here)", "Pull", "Legs"],
                       "the edited copy survives; only the missing one is added")
        XCTAssertEqual(after.plans.count, 2)
        XCTAssertEqual(after.activePlanId, mine.id, "merging does not change which plan is active")
        XCTAssertEqual(after.settings.units, .lb, "merging leaves the current settings alone")
    }

    // K25: a file that isn't a backup is refused before anything is written.
    func testBadFilesAreRefused() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)

        for bad in ["not json at all", "{}", "[1,2,3]", ""] {
            do {
                _ = try await store.readBackup(Data(bad.utf8))
                XCTFail("\(bad) should not read as a backup")
            } catch let error as StoreError {
                XCTAssertEqual(error, .notABackup, bad)
                XCTAssertFalse(error.message.isEmpty)
            }
        }

        // A backup from a newer app version is refused rather than half-understood.
        var future = ExportDocument(exportedAt: now, appVersion: "9.0", settings: Settings(),
                                    plans: [], sessions: [])
        future.fileVersion = storeFileVersion + 1
        let data = try StoreCoder.encoder.encode(future)
        do {
            _ = try await store.readBackup(data)
            XCTFail("a newer file version should be refused")
        } catch let error as StoreError {
            XCTAssertEqual(error, .unsupportedFileVersion(storeFileVersion + 1))
        }
    }

    // K26: the whole round trip through AppModel, which is what Settings actually calls.
    @MainActor func testRestoreThroughTheModelReloadsTheApp() async throws {
        let source = makeRoot(), target = makeRoot()
        defer { discard(source); discard(target) }
        let plan = CoreTestSupport.plan()
        let data = try await seeded(source, plans: [plan], sessions: [session("Push", daysAgo: 2)])
        let file = source.appendingPathComponent("backup.json")
        try data.write(to: file)

        let model = AppModel(store: Store(root: target), scheduler: RecordingAlerts(),
                             alerts: RecordingAlerts(), sampleJSON: { nil })
        await model.load()
        XCTAssertTrue(model.plans.isEmpty)

        guard case let .read(pending) = await model.readBackup(at: file) else {
            return XCTFail("the backup should have been readable")
        }
        XCTAssertEqual(pending.summary.plans, 1)
        let failure = await model.restore(pending, mode: .replaceAll)
        XCTAssertNil(failure)
        XCTAssertEqual(model.plans.map(\.id), [plan.id], "the app shows what was written")
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.activePlanId, plan.id)
        XCTAssertTrue(model.loaded)

        // A file that isn't a backup comes back as a message, not a throw.
        let junk = source.appendingPathComponent("junk.json")
        try Data("nope".utf8).write(to: junk)
        guard case let .failed(message) = await model.readBackup(at: junk) else {
            return XCTFail("junk should not read as a backup")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(model.plans.count, 1, "and it changed nothing")
    }
}
