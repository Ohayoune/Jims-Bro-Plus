import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// M7 — the remaining Settings rows, export, delete-all, and the spoken step card behind O19.
final class SettingsPolishTests: XCTestCase {
    private func makeRoot() -> URL { CoreTestSupport.makeRoot() }
    private func discard(_ root: URL) { CoreTestSupport.discard(root) }

    // Every toggle and stepper persists, and none of them disturbs the others.
    @MainActor func testRemainingSettingsPersist() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        XCTAssertTrue(model.settings.sound)
        XCTAssertTrue(model.settings.vibration)
        XCTAssertTrue(model.settings.keepAwake)

        await model.setSound(false)
        await model.setVibration(false)
        await model.setKeepAwake(false)
        await model.setWeightStep(1.25, for: .kg)
        await model.setWeightStep(10, for: .lb)

        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertFalse(reloaded.settings.sound)
        XCTAssertFalse(reloaded.settings.vibration)
        XCTAssertFalse(reloaded.settings.keepAwake)
        XCTAssertEqual(reloaded.settings.weightStepKg, 1.3, accuracy: 0.001, "one decimal place is kept")
        XCTAssertEqual(reloaded.settings.weightStepLb, 10)
        XCTAssertEqual(reloaded.settings.units, Settings.defaults().units, "untouched settings survive")

        // The step is per unit, so setting one never moves the other.
        await reloaded.setWeightStep(5, for: .kg)
        XCTAssertEqual(reloaded.settings.weightStepLb, 10)
        // And it is clamped rather than allowed to reach zero, which would make ± useless.
        await reloaded.setWeightStep(0, for: .kg)
        XCTAssertEqual(reloaded.settings.weightStepKg, 0.1)
        await reloaded.setWeightStep(9999, for: .kg)
        XCTAssertEqual(reloaded.settings.weightStepKg, 100)
    }

    // A silenced app plays nothing at all (SPEC §6.4: no audio session activity).
    @MainActor func testSoundAndVibrationOffPlayNothing() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        await model.setSound(false)
        await model.setVibration(false)

        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        let start = CoreTestSupport.now
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: start)
        await model.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: start)
        await model.tick(now: start.addingTimeInterval(90))
        XCTAssertEqual(recorder.played, [], "nothing plays with both settings off")

        // Notifications are still scheduled: they are the locked-phone path, not the sound setting.
        XCTAssertFalse(recorder.scheduled.isEmpty)

        // With vibration alone back on, the alert is delivered again. It has to be caught as
        // the rest ends: one that expired while the app was away deliberately stays silent.
        await model.setVibration(true)
        await model.apply(.logSet(step: 1, result: .reps(count: 10, weight: 60)),
                          now: start.addingTimeInterval(100))
        await model.tick(now: start.addingTimeInterval(190))
        XCTAssertEqual(recorder.played, [.end])

        // And a rest that ended long ago is silent even with the settings on.
        await model.apply(.logSet(step: 2, result: .reps(count: 10, weight: 60)),
                          now: start.addingTimeInterval(200))
        await model.tick(now: start.addingTimeInterval(400))
        XCTAssertEqual(recorder.played, [.end], "no catch-up beep for a rest that expired while away")
    }

    // Delete all data empties the store and leaves the app usable with defaults.
    @MainActor func testDeleteAllData() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        await model.setUnits(.lb)
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0,
                                 now: CoreTestSupport.now)
        await model.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: CoreTestSupport.now)

        recorder.reset()
        await model.deleteAllData(locale: Locale(identifier: "en_GB"))

        XCTAssertEqual(model.plans, [])
        XCTAssertEqual(model.sessions, [])
        XCTAssertNil(model.activePlanId)
        XCTAssertFalse(model.hasActiveSession)
        XCTAssertNil(model.justCompleted)
        XCTAssertEqual(model.settings, Settings.defaults(locale: Locale(identifier: "en_GB")))
        // Anything that might still fire is cancelled.
        XCTAssertEqual(Set(recorder.cancelled), Set(AlertIdentifier.all))

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(),
                       ["sessions", "settings.json"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("sessions").path), [])

        // A relaunch sees the defaults that were written, not the locale's.
        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load(locale: Locale(identifier: "en_US"))
        XCTAssertEqual(reloaded.settings.units, .kg, "the written en_GB defaults win")
        XCTAssertEqual(reloaded.plans, [])

        // And the store still works afterwards.
        await reloaded.save(try XCTUnwrap(reloaded.runImport(CoreTestSupport.planJSON()).plan))
        XCTAssertEqual(reloaded.plans.count, 1)
    }

    // The backup of SPEC §8.5, written where ShareLink can pick it up.
    @MainActor func testExportBackup() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        try await model.store.save(session: CoreTestSupport.completed())

        let exported = await model.exportBackup(now: CoreTestSupport.now)
        let url = try XCTUnwrap(exported)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "json")

        let document = try StoreCoder.decoder.decode(ExportDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.plans.map(\.id), [plan.id])
        XCTAssertEqual(document.sessions.count, 1)
        XCTAssertEqual(document.settings, model.settings)
        XCTAssertFalse(document.appVersion.isEmpty)
        XCTAssertEqual(document.fileVersion, storeFileVersion)
    }

    // The notification row reports what the system says, not what the app hoped.
    @MainActor func testNotificationStateRow() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()

        await model.refreshNotificationState()
        XCTAssertEqual(model.notificationState, .notAsked)
        XCTAssertEqual(NotificationState.notAsked.label, "Not asked yet")
        XCTAssertNil(NotificationState.notAsked.explanation)

        recorder.authorized = false
        _ = await model.requestNotificationAuthorization()
        await model.refreshNotificationState()
        XCTAssertEqual(model.notificationState, .denied)
        XCTAssertEqual(model.notificationState.label, "Off")
        XCTAssertNotNil(model.notificationState.explanation, "a refusal is worth explaining")

        recorder.authorized = true
        await model.refreshNotificationState()
        XCTAssertEqual(model.notificationState, .allowed)
        XCTAssertEqual(model.notificationState.label, "On")
        XCTAssertNil(model.notificationState.explanation)
    }

    // O19: the card reads as one sentence, not as the visual text full of dots and dashes.
    func testSpokenStepCard() throws {
        var plan = CoreTestSupport.plan(sets: 4, work: .reps(.range(min: 8, max: 12)))
        plan.days[0].exercises[0].name = "Bench Press"
        plan.days[0].exercises[0].notes = "Pause on chest"
        let session = CoreTestSupport.session(plan)
        XCTAssertEqual(StepCard.spoken(session: session, step: 1),
                       "Bench Press, set 2 of 4, target 8 to 12 reps, at 60 kilograms, Pause on chest")
        XCTAssertFalse(StepCard.spoken(session: session, step: 1).contains("·"))
        XCTAssertFalse(StepCard.spoken(session: session, step: 1).contains("–"))

        // Every target kind gets words rather than punctuation.
        let cases: [(WorkTarget, String)] = [
            (.reps(.fixed(10)), "10 reps, range 8 to 12"),
            (.reps(.amrap(min: nil)), "as many reps as possible"),
            (.reps(.amrap(min: 10)), "at least 10 reps"),
            (.duration(seconds: 45), "45 seconds"),
            (.openDuration(minSeconds: 30), "at least 30 seconds"),
        ]
        for (work, expected) in cases {
            var one = CoreTestSupport.plan(sets: 1, work: work)
            one.days[0].exercises[0].name = "Move"
            one.days[0].exercises[0].repRange = RepRange(min: 8, max: 12)
            let spoken = StepCard.spoken(session: CoreTestSupport.session(one), step: 0)
            XCTAssertTrue(spoken.contains(expected), "\(spoken) should contain \(expected)")
        }

        // Pounds are said as pounds, and a drop names its position.
        var pounds = CoreTestSupport.plan(sets: 1, drops: [DropTarget(work: .reps(.amrap(min: nil)), weight: 40)])
        pounds.units = .lb
        let dropSession = CoreTestSupport.session(pounds)
        XCTAssertTrue(StepCard.spoken(session: dropSession, step: 0).contains("pounds"))
        // D58 (v1.6): VoiceOver speaks plainly too — a drop is a lighter set.
        XCTAssertTrue(StepCard.spoken(session: dropSession, step: 1).contains("lighter set 1 of 1"))

        // A bodyweight exercise says no weight at all.
        let bodyweight = CoreTestSupport.session(
            CoreTestSupport.plan(sets: 2, weight: nil, bodyweight: true))
        XCTAssertFalse(StepCard.spoken(session: bodyweight, step: 0).contains("kilograms"))
    }

}
