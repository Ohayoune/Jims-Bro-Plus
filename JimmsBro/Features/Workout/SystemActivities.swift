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
///
/// D60 (v1.6): it keeps **no** handle of its own. An ActivityKit activity outlives the process
/// that started it — that is the point of one — so a remembered `Activity` is a lie the moment
/// the app is terminated mid-workout, and the app that comes back cannot end what it no longer
/// remembers. `Activity.activities` is the system's own list and survives the launch, so it is
/// the only thing worth asking. That makes this type stateless, and an orphan impossible:
/// whatever is on the Lock Screen is either adopted or ended, never ignored.
final class SystemActivityPresenter: ActivityPresenting {
    /// Whether the phone will show one at all. False when the user has turned Live Activities
    /// off for the app, which is a setting only the system can change.
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Everything this app has on screen right now, however long ago it was started, and
    /// whichever process started it. `.stale` counts: the system still draws it.
    private var onScreen: [Activity<WorkoutActivityAttributes>] {
        Activity<WorkoutActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
    }

    func show(_ state: WorkoutActivityState) async {
        guard isAvailable else { return }
        let content = ActivityContent(state: state, staleDate: state.endsAt)
        let running = onScreen
        if let keep = running.first {
            // Two can only ever be the app's own doing. Update the first, end the rest, so a
            // relaunch mid-rest resumes the activity the user is looking at instead of
            // stacking a second one beside it.
            for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            await keep.update(content)
            return
        }
        let attributes = WorkoutActivityAttributes(dayName: state.detail)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    /// Ends every activity this app has, not merely one this process happens to have started.
    func end() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
