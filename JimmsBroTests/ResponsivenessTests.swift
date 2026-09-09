import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// A scheduler that holds every `schedule` call until it is released, so a test can look at
/// the model while the system is still being told. The real one takes a round-trip per request
/// and the Live Activity behind it takes longer; this one takes for ever until asked not to.
final class BlockingAlerts: NotificationScheduling, AlertPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var _held = 0

    /// How many `schedule` calls have arrived, released or not.
    var held: Int { lock.withLock { _held } }

    func requestAuthorization() async -> Bool { true }
    func authorizationState() async -> NotificationState { .allowed }
    func schedule(_ request: NotificationRequest) async {
        await withCheckedContinuation { continuation in
            lock.withLock { waiters.append(continuation); _held += 1 }
        }
    }
    /// Lets every held call return, in the order they arrived.
    func release() {
        let waiting = lock.withLock { let all = waiters; waiters = []; return all }
        waiting.forEach { $0.resume() }
    }
    func cancel(ids: [AlertIdentifier]) async {}
    func play(_ beep: TimerBeep, sound: Bool, vibration: Bool) {}
    func play(feedback: Feedback, vibration: Bool) {}
}

/// Y1 (v1.4) — D48: a tap's visible result is on screen before its side effects run.
final class ResponsivenessTests: XCTestCase {
    private let now = CoreTestSupport.now

    // Y1: while the scheduler is still holding the first notification, the workout exists and
    // the count the cover opens on has already moved.
    @MainActor func testTheWorkoutExistsBeforeTheSystemHasBeenTold() async throws {
        let root = CoreTestSupport.makeRoot("Responsiveness")
        defer { CoreTestSupport.discard(root) }
        let alerts = BlockingAlerts()
        // With a warm-up (D32) on, starting schedules its end at once. (D57, v1.6: a fresh
        // install's warm-up is off, so it is turned on here.)
        let model = AppModel(store: Store(root: root), scheduler: alerts, alerts: alerts)
        await model.load()
        await model.setWarmUp(300)
        let plan = CoreTestSupport.plan()
        await model.save(plan, makeActive: true)
        XCTAssertEqual(model.startedWorkouts, 0)

        let start = Task { @MainActor in
            try await model.startDay(planId: plan.id, dayIndex: 0, now: self.now)
        }
        // Let the start run up to the first thing it waits for: the scheduler that never returns.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while alerts.held == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(alerts.held, 1, "the start must actually be held on a notification")

        // The system has not answered, and the screen already has everything it needs.
        XCTAssertTrue(model.hasActiveSession)
        XCTAssertEqual(model.startedWorkouts, 1)
        XCTAssertEqual(model.session?.dayName, "Push")

        alerts.release()
        try await start.value
        XCTAssertEqual(model.startedWorkouts, 1, "finishing the start does not count it again")
        XCTAssertTrue(model.hasActiveSession)
    }

    // Y2: a refused start does not count, a switch does, and a launch that restores a running
    // session never opens the cover on its own.
    @MainActor func testWhatCountsAsAStart() async throws {
        let root = CoreTestSupport.makeRoot("Responsiveness")
        defer { CoreTestSupport.discard(root) }
        let alerts = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: alerts, alerts: alerts)
        await model.load()
        let plan = CoreTestSupport.plan()
        await model.save(plan, makeActive: true)

        try await model.startDay(planId: plan.id, dayIndex: 0, now: now)
        XCTAssertEqual(model.startedWorkouts, 1)

        // D17: starting again mid-session is refused before anything changes.
        do {
            try await model.startDay(planId: plan.id, dayIndex: 0, now: now.addingTimeInterval(60))
            XCTFail("a second start with no choice must be refused")
        } catch LibraryError.sessionInProgress {
        }
        XCTAssertEqual(model.startedWorkouts, 1, "a refusal is not a start")

        // A switch is a new workout, so the cover has to open for it.
        try await model.startDay(planId: plan.id, dayIndex: 0, switching: .discard,
                                 now: now.addingTimeInterval(120))
        XCTAssertEqual(model.startedWorkouts, 2)
        XCTAssertTrue(model.hasActiveSession)

        // A fresh launch over the same store restores the session — as Resume, not as a start.
        let relaunched = AppModel(store: Store(root: root), scheduler: alerts, alerts: alerts)
        await relaunched.load()
        XCTAssertTrue(relaunched.hasActiveSession, "the active session is on disk")
        XCTAssertEqual(relaunched.startedWorkouts, 0, "load never opens the cover")
        guard case .inProgress = relaunched.startCard(now: now.addingTimeInterval(180)) else {
            return XCTFail("the card offers Resume")
        }
    }
}
