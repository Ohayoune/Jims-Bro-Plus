import Foundation

/// The sound a scheduled notification carries. `warning` is the bundled short `warning.caf`.
enum AlertSound: String, Equatable, Sendable { case standard, warning }

/// A request the engine's effects turned into something the system can schedule.
struct NotificationRequest: Equatable, Sendable {
    var id: AlertIdentifier
    var date: Date
    var title: String
    var body: String
    var sound: AlertSound
}

/// What the system says about notification permission, for the Settings row.
enum NotificationState: Equatable, Sendable {
    case notAsked, allowed, denied

    var label: String {
        switch self {
        case .notAsked: return "Not asked yet"
        case .allowed: return "On"
        case .denied: return "Off"
        }
    }
    /// Only a refusal is worth explaining, and only the system can undo it.
    var explanation: String? {
        self == .denied
            ? "Rest and timer alerts only sound while the app is open. Turn notifications on in iOS Settings."
            : nil
    }
}

/// Injected so tests can assert on scheduling without touching UserNotifications.
protocol NotificationScheduling: AnyObject, Sendable {
    func requestAuthorization() async -> Bool
    func authorizationState() async -> NotificationState
    func schedule(_ request: NotificationRequest) async
    func cancel(ids: [AlertIdentifier]) async
}

/// Confirmation the app gives an action rather than a clock. Silent — vibration only — so it
/// never competes with the timer beeps. Separate from `TimerBeep`, which is persisted inside
/// `ActiveSession.deliveredBeeps` and must not grow cases that aren't timer moments.
enum Feedback: String, Equatable, Sendable { case logged }

/// Injected so tests can assert on beeps without touching AVFoundation.
protocol AlertPlaying: AnyObject, Sendable {
    func play(_ beep: TimerBeep, sound: Bool, vibration: Bool)
    /// v1.1: the haptic a logged set gets (O59).
    func play(feedback: Feedback, vibration: Bool)
}

/// Every notification identifier the app uses, so cancelling "everything" is not a guess.
/// An enum rather than four constants: the engine used to spell these out as string literals
/// in ten places, where a typo would have scheduled an alert nothing ever cancelled (v1.2).
enum AlertIdentifier: String, CaseIterable, Equatable, Sendable {
    case rest = "rest-timer"
    case setEnd = "set-end"
    case setWarning = "set-warning"
    case setMinimum = "set-minimum"

    static var all: [AlertIdentifier] { allCases }
    /// The three a running timed set may have scheduled, cancelled together when it ends.
    static let work: [AlertIdentifier] = [.setEnd, .setWarning, .setMinimum]

    /// What the notification's title says. The body comes from the engine, which knows the
    /// workout; the title belongs to the identifier.
    var title: String {
        switch self {
        case .rest: return "Rest over"
        case .setEnd: return "Time!"
        case .setWarning: return "Almost there"
        case .setMinimum: return "Minimum reached"
        }
    }

    /// Only the warning gets the short bundled sound; everything else uses the standard one.
    var sound: AlertSound { self == .setWarning ? .warning : .standard }
}

/// Turns an engine effect into a system request. The identifier carries its own title and
/// sound; the engine supplies only the moment and the body, which is all it knows.
enum AlertRouting {
    static func request(id: AlertIdentifier, at date: Date, body: String) -> NotificationRequest {
        NotificationRequest(id: id, date: date, title: id.title, body: body, sound: id.sound)
    }
}

/// The app's own do-nothing implementation, used as the default so `AppModel` can be built
/// without either the system frameworks or a test double. Notifications and beeps are the two
/// things the app asks the system for; a model that has neither simply stays quiet.
///
/// The recorder that *remembers* what was asked for is a test double and lives in the test
/// target (`JimmsBroTests/CoreTestSupport.swift`); it used to ship inside the app.
final class SilentAlerts: NotificationScheduling, AlertPlaying, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }
    func authorizationState() async -> NotificationState { .notAsked }
    func schedule(_ request: NotificationRequest) async {}
    func cancel(ids: [AlertIdentifier]) async {}
    func play(_ beep: TimerBeep, sound: Bool, vibration: Bool) {}
    func play(feedback: Feedback, vibration: Bool) {}
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
