import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// M3 — K1–K15. Every case runs against a temp directory injected into the store.
final class StoreTests: XCTestCase {
    /// A fresh temp directory per case, cleaned up by the caller's `defer`, so these run
    /// identically under XCTest and under the portable Core runner (which has no setUp).
    private func makeRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JimmsBroStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func discard(_ root: URL) { try? FileManager.default.removeItem(at: root) }

    private func contents(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    // K1, K6: save then load; the directory is created on first launch.
    func testSaveAndLoadRoundTripCreatesDirectory() async throws {
        let root = makeRoot()
        defer { discard(root) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let store = Store(root: root)
        let plan = CoreTestSupport.plan(secondExercise: true)
        var settings = Settings()
        settings.units = .lb
        settings.defaultRestSeconds = 120
        let session = CoreTestSupport.completed()

        try await store.save(settings: settings)
        try await store.save(plans: [plan], activePlanId: plan.id)
        try await store.save(session: session)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        let loaded = await store.load()
        XCTAssertEqual(loaded.plans, [plan])
        XCTAssertEqual(loaded.activePlanId, plan.id)
        XCTAssertEqual(loaded.settings, settings)
        XCTAssertEqual(loaded.sessions, [session])
        XCTAssertNil(loaded.active)
        XCTAssertEqual(loaded.corruptFiles, [])

        // A second store over the same directory reads the same thing.
        let reopened = await Store(root: root).load()
        XCTAssertEqual(reopened.plans, [plan])
    }

    // K6: an empty directory is not an error, and yields defaults.
    func testFirstLaunchLoadsDefaults() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let loaded = await Store(root: root).load(defaultSettings: Settings(units: .lb))
        XCTAssertEqual(loaded.settings.units, .lb)
        XCTAssertEqual(loaded.plans, [])
        XCTAssertNil(loaded.activePlanId)
        XCTAssertEqual(loaded.sessions, [])
        XCTAssertNil(loaded.active)
        XCTAssertEqual(loaded.corruptFiles, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions").path))
    }

    // K2: a failure mid-write leaves the old file intact and no partial file behind.
    func testWriteIsAtomicAndLeavesNoPartialFile() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let original = CoreTestSupport.plan()
        try await store.save(plans: [original], activePlanId: original.id)
        let before = try Data(contentsOf: root.appendingPathComponent("plans.json"))

        // Make the directory unwritable so the temp write fails part-way through the save.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        var replacement = CoreTestSupport.plan(sets: 9)
        replacement.name = "Replacement"
        var threw = false
        do { try await store.save(plans: [replacement], activePlanId: replacement.id) } catch { threw = true }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        XCTAssertTrue(threw, "an unwritable directory must surface as a thrown error, not a silent loss")

        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("plans.json")), before)
        let afterFailure = await store.load()
        XCTAssertEqual(afterFailure.plans, [original])
        XCTAssertEqual(contents(root).filter { $0.hasSuffix(".tmp") }, [])
    }

    // K3: garbage bytes in plans.json.
    func testCorruptPlansFileIsSetAside() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let plan = CoreTestSupport.plan()
        try await store.save(plans: [plan], activePlanId: plan.id)
        try Data("not json at all".utf8).write(to: root.appendingPathComponent("plans.json"))

        let loaded = await store.load()
        XCTAssertEqual(loaded.plans, [])
        XCTAssertNil(loaded.activePlanId)
        XCTAssertEqual(loaded.corruptFiles, ["plans.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("plans.json").path))
        let asideNames = contents(root).filter { $0.hasPrefix("plans.json.corrupt-") }
        XCTAssertEqual(asideNames.count, 1)
        // The original bytes are preserved, never deleted.
        let aside = try Data(contentsOf: root.appendingPathComponent(asideNames[0]))
        XCTAssertEqual(String(data: aside, encoding: .utf8), "not json at all")
    }

    // K4: one bad session file among five.
    func testCorruptSessionFileLeavesTheOthers() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        var sessions: [Session] = []
        for index in 0..<5 {
            let session = CoreTestSupport.completed(start: CoreTestSupport.now.addingTimeInterval(Double(index) * 86400))
            sessions.append(session)
            try await store.save(session: session)
        }
        let victim = sessions[2]
        try Data("{".utf8).write(to: root.appendingPathComponent("sessions/\(victim.id.uuidString).json"))

        let loaded = await store.load()
        XCTAssertEqual(loaded.sessions.count, 4)
        XCTAssertFalse(loaded.sessions.contains { $0.id == victim.id })
        XCTAssertEqual(loaded.corruptFiles, ["sessions/\(victim.id.uuidString).json"])
        XCTAssertEqual(contents(root.appendingPathComponent("sessions")).count, 5)
    }

    // K5: an unknown fileVersion is set aside rather than crashing or being read as v1.
    func testUnsupportedFileVersionIsTreatedAsCorrupt() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let plan = CoreTestSupport.plan()
        try await store.save(plans: [plan], activePlanId: plan.id)
        let url = root.appendingPathComponent("plans.json")
        let text = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\"fileVersion\" : 1", with: "\"fileVersion\" : 99")
        XCTAssertTrue(text.contains("99"), "the version key must be present to be overwritten")
        try Data(text.utf8).write(to: url)

        let loaded = await store.load()
        XCTAssertEqual(loaded.plans, [])
        XCTAssertEqual(loaded.corruptFiles, ["plans.json"])

        // And the error itself names the version it found.
        XCTAssertThrowsError(try StoreCoder.decode(PlansPayload.self, from: Data(text.utf8))) { error in
            XCTAssertEqual(error as? StoreError, .unsupportedFileVersion(99))
        }
    }

    // K7: the active session on disk matches the engine after every event.
    func testActiveSessionIsWrittenAfterEachEvent() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        var engine = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3))
        var now = CoreTestSupport.now

        for step in 0..<3 {
            now = now.addingTimeInterval(60)
            _ = engine.apply(.logSet(step: step, result: .reps(count: 10, weight: 60)), now: now)
            try await store.save(activeSession: engine.active)
            let loaded = await store.load()
            XCTAssertEqual(loaded.active, engine.active, "disk must match the engine after event \(step)")
            XCTAssertEqual(loaded.corruptFiles, [])
            now = now.addingTimeInterval(90)
            _ = engine.apply(.restElapsed, now: now)
            try await store.save(activeSession: engine.active)
            let afterRest = await store.load()
            XCTAssertEqual(afterRest.active, engine.active)
        }
    }

    // K8: completing moves the workout from active-session.json into sessions/.
    func testCompleteRemovesActiveAndWritesSessionFile() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let session = CoreTestSupport.completed()
        try await store.save(activeSession: ActiveSession(session: session, phase: .completed))
        let beforeCompletion = await store.load()
        XCTAssertNotNil(beforeCompletion.active)

        try await store.complete(session: session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions/\(session.id.uuidString).json").path))
        let loaded = await store.load()
        XCTAssertNil(loaded.active)
        XCTAssertEqual(loaded.sessions, [session])
    }

    // K9: discarding removes the active session and writes no session file.
    func testDiscardRemovesActiveAndWritesNoSession() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let session = CoreTestSupport.session()
        try await store.save(activeSession: ActiveSession(session: session, phase: .working(step: 0)))

        try await store.clearActiveSession()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))
        let loaded = await store.load()
        XCTAssertNil(loaded.active)
        XCTAssertEqual(loaded.sessions, [])
        XCTAssertEqual(contents(root.appendingPathComponent("sessions")), [])
        // Clearing again is not an error.
        try await store.clearActiveSession()
    }

    // K10: dates survive as ISO-8601 with fractional seconds, to the millisecond.
    func testDatesRoundTripToTheMillisecond() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let precise = Date(timeIntervalSince1970: 1_700_000_000.123)
        var plan = CoreTestSupport.plan()
        plan.importedAt = precise
        try await store.save(plans: [plan], activePlanId: nil)

        let text = try String(contentsOf: root.appendingPathComponent("plans.json"), encoding: .utf8)
        XCTAssertTrue(text.contains("2023-11-14T22:13:20.123Z"), "expected fractional ISO-8601, got:\n\(text)")

        let loaded = await store.load()
        let importedAt = try XCTUnwrap(loaded.plans.first?.importedAt)
        XCTAssertEqual(importedAt.timeIntervalSince1970, precise.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(loaded.plans.first?.name, plan.name)
    }

    // K11: sorted keys, so the same value always produces the same bytes.
    func testEncoderUsesSortedKeysAndIsStable() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let plan = CoreTestSupport.plan(secondExercise: true)
        let once = try StoreCoder.encode(PlansPayload(activePlanId: plan.id, plans: [plan]))
        let twice = try StoreCoder.encode(PlansPayload(activePlanId: plan.id, plans: [plan]))
        XCTAssertEqual(once, twice)

        let text = try XCTUnwrap(String(data: once, encoding: .utf8))
        let topLevel = ["\"activePlanId\"", "\"fileVersion\"", "\"plans\""].compactMap { text.range(of: $0)?.lowerBound }
        XCTAssertEqual(topLevel.count, 3)
        XCTAssertEqual(topLevel, topLevel.sorted(), "top-level keys must appear in sorted order")

        // Writing the same value twice leaves byte-identical files.
        let store = Store(root: root)
        try await store.save(plans: [plan], activePlanId: plan.id)
        let first = try Data(contentsOf: root.appendingPathComponent("plans.json"))
        try await store.save(plans: [plan], activePlanId: plan.id)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("plans.json")), first)
    }

    // K12: 1000 session files load in well under a second.
    func testLoadsAThousandSessionsQuickly() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        // Write the files directly: this case measures load, not save.
        let template = CoreTestSupport.completed()
        for index in 0..<1000 {
            var session = template
            session.id = UUID()
            session.startedAt = CoreTestSupport.now.addingTimeInterval(Double(index) * 3600)
            try StoreCoder.encode(session)
                .write(to: root.appendingPathComponent("sessions/\(session.id.uuidString).json"))
        }
        let started = Date()
        let loaded = await store.load()
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(loaded.sessions.count, 1000)
        XCTAssertEqual(loaded.corruptFiles, [])
        XCTAssertLessThan(elapsed, 1.0, "1000 sessions took \(elapsed)s")
        // Sorted oldest first, so history and charts get a stable order.
        XCTAssertEqual(loaded.sessions.map(\.startedAt), loaded.sessions.map(\.startedAt).sorted())
    }

    // K13: the export carries settings, plans and sessions, and decodes back into the same types.
    func testExportContainsEverythingAndDecodesBack() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        var settings = Settings()
        settings.units = .lb
        let plans = [CoreTestSupport.plan(), CoreTestSupport.plan(secondExercise: true)]
        let sessions = [CoreTestSupport.completed(),
                        CoreTestSupport.completed(start: CoreTestSupport.now.addingTimeInterval(-172_800))]
        try await store.save(settings: settings)
        try await store.save(plans: plans, activePlanId: plans[0].id)
        for session in sessions { try await store.save(session: session) }

        let now = CoreTestSupport.now
        let exported = await store.exportData(appVersion: "1.0", now: now)
        let data = try XCTUnwrap(exported)
        let document = try StoreCoder.decoder.decode(ExportDocument.self, from: data)
        XCTAssertEqual(document.exportedAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(document.appVersion, "1.0")
        XCTAssertEqual(document.fileVersion, storeFileVersion)
        XCTAssertEqual(document.settings, settings)
        XCTAssertEqual(document.plans, plans)
        XCTAssertEqual(Set(document.sessions.map(\.id)), Set(sessions.map(\.id)))

        let url = try await store.exportFile(appVersion: "1.0", now: now)
        XCTAssertEqual(try Data(contentsOf: url), data)
        try? FileManager.default.removeItem(at: url)
    }

    // K14: delete all data empties the store and resets what a reload reports.
    func testDeleteAllEmptiesTheStore() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let plan = CoreTestSupport.plan()
        try await store.save(settings: Settings(units: .lb))
        try await store.save(plans: [plan], activePlanId: plan.id)
        try await store.save(session: CoreTestSupport.completed())
        try await store.save(activeSession: ActiveSession(session: CoreTestSupport.session(), phase: .working(step: 0)))

        try await store.deleteAll()

        XCTAssertEqual(contents(root), ["sessions"])
        XCTAssertEqual(contents(root.appendingPathComponent("sessions")), [])
        let loaded = await store.load(defaultSettings: Settings())
        XCTAssertEqual(loaded.plans, [])
        XCTAssertNil(loaded.activePlanId)
        XCTAssertEqual(loaded.sessions, [])
        XCTAssertNil(loaded.active)
        XCTAssertEqual(loaded.settings, Settings())
        XCTAssertEqual(loaded.corruptFiles, [])
        // The store is usable again immediately afterwards.
        try await store.save(plans: [plan], activePlanId: plan.id)
        let reusable = await store.load()
        XCTAssertEqual(reusable.plans, [plan])
    }

    // K15: concurrent writes are serialized by the actor; one of them wins whole, none interleave.
    func testRapidWritesAreSerialized() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let store = Store(root: root)
        let plans = (0..<20).map { index -> Plan in
            var plan = CoreTestSupport.plan(sets: index + 1)
            plan.name = "Plan \(index)"
            return plan
        }
        await withTaskGroup(of: Void.self) { group in
            for plan in plans {
                group.addTask { try? await store.save(plans: [plan], activePlanId: plan.id) }
            }
        }
        let loaded = await store.load()
        XCTAssertEqual(loaded.corruptFiles, [], "a torn file would have been set aside")
        XCTAssertEqual(loaded.plans.count, 1)
        let winner = try XCTUnwrap(loaded.plans.first)
        XCTAssertTrue(plans.contains(winner), "the surviving file must be exactly one of the writes")
        XCTAssertEqual(loaded.activePlanId, winner.id)

        // Sequential writes: the last one wins.
        for plan in plans { try await store.save(plans: [plan], activePlanId: plan.id) }
        let last = await store.load()
        XCTAssertEqual(last.plans, [plans[19]])
    }

    /// K18 (D24, v1.1): a session write genuinely throws rather than silently no-op'ing when
    /// its directory can't be created — the honesty `AppModel.trySaveSession` depends on.
    func testSessionWriteThrowsWhenItsDirectoryIsBlocked() async throws {
        let root = makeRoot()
        defer { discard(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A plain file at "sessions" means the store can never create that directory.
        try Data().write(to: root.appendingPathComponent("sessions"))
        let store = Store(root: root)
        do {
            try await store.save(session: CoreTestSupport.completed())
            XCTFail("Expected the write to throw")
        } catch {}
        // Once unblocked, the identical call succeeds.
        try FileManager.default.removeItem(at: root.appendingPathComponent("sessions"))
        try await store.save(session: CoreTestSupport.completed())
    }
}
