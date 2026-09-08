import ActivityKit
import Foundation

/// The ActivityKit contract, compiled into **both** the app and the widget extension: the app
/// starts and updates the activity, the extension draws it, and they must agree byte for byte
/// on the shape.
///
/// Its `ContentState` is the Core type verbatim (`WorkoutActivityState`), so there is one
/// definition of what the Lock Screen shows and it is the one the app's own screen reads.
struct WorkoutActivityAttributes: ActivityAttributes {
    typealias ContentState = WorkoutActivityState

    /// Fixed for the life of the activity: which day is being trained.
    var dayName: String
}
