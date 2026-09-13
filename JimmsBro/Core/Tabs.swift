import Foundation

/// SPEC §4.0 (D62, v1.7): the tab bar — a workout to do and a record of the ones done. Plans is
/// reached from Today's ··· → Change plan and Settings from the gear at the top-left of both
/// tabs, so neither sits as a peer of the daily job. `RootView` draws `allCases` in this order
/// and nothing else, and a test holds the list to SPEC §4.0's (T7).
enum AppTab: String, CaseIterable {
    case today, history

    var title: String {
        switch self {
        case .today: return "Today"
        case .history: return "History"
        }
    }

    /// The SF Symbol above the title.
    var symbol: String {
        switch self {
        case .today: return "calendar"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
