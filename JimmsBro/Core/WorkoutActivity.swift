import Foundation

/// D40 (v1.2): how a running workout becomes the `WorkoutActivityState` the Lock Screen and the
/// Dynamic Island draw, and the seam that keeps ActivityKit out of Core.
///
/// The state is resolved from the same `ActiveSession` the workout screen reads, so what the
/// Island says can never disagree with what the app says. ActivityKit itself lives in the
/// widget extension and behind `ActivityPresenting`, exactly as UserNotifications lives behind
/// `NotificationScheduling` — which is what makes this testable without a device.
extension WorkoutActivityState {
    static func of(_ active: ActiveSession, now: Date = Date(),
                   wording: Wording = .plain) -> WorkoutActivityState? {
        let session = active.session
        guard active.phase != .completed, !session.steps.isEmpty else { return nil }
        let index: Int
        switch active.phase {
        case let .working(step): index = step
        case let .resting(rest): index = rest.nextStep
        case .completed: return nil
        }
        let done = session.steps.filter { $0.status != .pending }.count
        let detail = WorkoutScreen.nextLine(session: session, step: index, wording: wording)?
            .replacingOccurrences(of: "Next: ", with: "")
            ?? session.dayName

        if case let .resting(rest) = active.phase {
            return WorkoutActivityState(title: rest.kind.title, detail: detail,
                                        endsAt: rest.endsAt, startedAt: rest.startedAt,
                                        done: done, total: session.steps.count, isBreak: true)
        }
        let name = session.exercises[safe: session.steps[index].exerciseIndex]?.name
            ?? session.dayName
        // A running timed set is the other thing worth watching from the Lock Screen.
        if active.timerRunning, let started = session.steps[safe: index]?.startedAt,
           let target = session.target(at: index), target.work.isTimed {
            var ends: Date?
            if case let .duration(seconds) = target.work {
                ends = started.addingTimeInterval(Double(seconds))
            }
            return WorkoutActivityState(title: name, detail: detail, endsAt: ends,
                                        startedAt: started, done: done,
                                        total: session.steps.count, isBreak: false)
        }
        return WorkoutActivityState(title: name, detail: detail, endsAt: nil, startedAt: nil,
                                    done: done, total: session.steps.count, isBreak: false)
    }
}

/// Injected so the behavior is testable without ActivityKit, and so Core never imports it.
/// The app's implementation lives in Features; the tests use a recorder.
protocol ActivityPresenting: AnyObject, Sendable {
    /// Starts the activity, or updates it when one is already running.
    func show(_ state: WorkoutActivityState) async
    /// The workout ended, was discarded, or the app was told to stop showing it.
    func end() async
}

/// The app's do-nothing implementation, for when Live Activities are unavailable or off.
final class NoActivities: ActivityPresenting, @unchecked Sendable {
    func show(_ state: WorkoutActivityState) async {}
    func end() async {}
}
