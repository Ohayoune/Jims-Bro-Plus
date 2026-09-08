import SwiftUI
import WidgetKit

/// D40 (v1.2): the widget extension that puts the workout on the Lock Screen and in the
/// Dynamic Island. It renders and nothing else — every value it draws was computed in Core
/// (`WorkoutActivityState`) and handed over by the app.
@main
struct JimmsBroActivityBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}
