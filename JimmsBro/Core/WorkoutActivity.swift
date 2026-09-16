import Foundation

/// D40 (v1.2): how a running workout becomes the `WorkoutActivityState` the Lock Screen and the
/// Dynamic Island draw, and the seam that keeps ActivityKit out of Core.
///
/// The state is resolved from the same `ActiveSession` the workout screen reads, so what the
/// Island says can never disagree with what the app says. ActivityKit itself lives in the
/// widget extension and behind `ActivityPresenting`, exactly as UserNotifications lives behind
/// `NotificationScheduling` — which is what makes this testable without a device.
extension WorkoutActivityState {
    /// `plans` give the day its colour (D65, §6.41): the workout's day in its plan. Without
    /// them the state carries none, and the Lock Screen draws no square.
    static func of(_ active: ActiveSession, now: Date = Date(), wording: Wording = .plain,
                   plans: [Plan] = []) -> WorkoutActivityState? {
        var state = resolved(active, now: now, wording: wording)
        state?.dayColour = DayColour.of(session: active.session, plans: plans)
        return state
    }

    private static func resolved(_ active: ActiveSession, now: Date,
                                 wording: Wording) -> WorkoutActivityState? {
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

        // D82 (v1.10): the walk between exercises counts up, on the Lock Screen as on the strip
        // — no `endsAt`, so the system draws it upward from the walk's start — and it goes on
        // past the ring's minimum until the next set is logged or started.
        if case let .resting(rest) = active.phase, rest.kind == .betweenExercises {
            return WorkoutActivityState(title: rest.kind.title, detail: detail, endsAt: nil,
                                        startedAt: active.blockDone?.startedAt ?? rest.startedAt,
                                        done: done, total: session.steps.count, isBreak: true)
        }
        if case let .resting(rest) = active.phase {
            return WorkoutActivityState(title: rest.kind.title, detail: detail,
                                        endsAt: rest.endsAt, startedAt: rest.startedAt,
                                        done: done, total: session.steps.count, isBreak: true)
        }
        if let blockDone = active.blockDone, !active.timerRunning {
            return WorkoutActivityState(title: RestKind.betweenExercises.title, detail: detail,
                                        endsAt: nil, startedAt: blockDone.startedAt,
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
