import ActivityKit
import Foundation

/// D40 (v1.2): the app half of the Live Activity. Starts one when a workout starts, updates it
/// as the workout moves, and ends it when the workout does.
///
/// It lives in Features because it imports ActivityKit; Core knows only `ActivityPresenting`.
/// It holds no reference back to the model: everything it needs travels in the state the app
/// pushes, which is also what makes the state the one definition of what is shown.
/// Every failure here is silent by design: a Lock Screen widget that cannot start is a missing
/// convenience, not a lost set, and the workout screen itself is unaffected.
final class SystemActivityPresenter: ActivityPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Activity<WorkoutActivityAttributes>?


    /// Whether the phone will show one at all. False when the user has turned Live Activities
    /// off for the app, which is a setting only the system can change.
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func show(_ state: WorkoutActivityState) async {
        guard isAvailable else { return }
        if let activity = lock.withLock({ current }) {
            await activity.update(ActivityContent(state: state, staleDate: state.endsAt))
            return
        }
        let attributes = WorkoutActivityAttributes(dayName: state.detail)
        let started = try? Activity.request(attributes: attributes,
                                            content: ActivityContent(state: state,
                                                                     staleDate: state.endsAt),
                                            pushType: nil)
        lock.withLock { current = started }
    }

    func end() async {
        guard let activity = lock.withLock({ let value = current; current = nil; return value })
        else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
