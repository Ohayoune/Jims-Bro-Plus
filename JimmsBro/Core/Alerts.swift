import Foundation

/// The sound a scheduled notification carries. `warning` is the bundled short `warning.caf`.
enum AlertSound: String, Equatable, Sendable { case standard, warning }

/// A request the engine's effects turned into something the system can schedule.
struct NotificationRequest: Equatable, Sendable {
    var id: String
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
    func cancel(ids: [String]) async
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
enum AlertIdentifier {
    static let rest = "rest-timer"
    static let setEnd = "set-end"
    static let setWarning = "set-warning"
    static let setMinimum = "set-minimum"
    static let all = [rest, setEnd, setWarning, setMinimum]
}

/// Turns an engine effect into a system request: the title and sound live here rather than in
/// the engine, which only knows ids, dates and bodies.
enum AlertRouting {
    static func request(id: String, at date: Date, body: String) -> NotificationRequest {
        NotificationRequest(id: id, date: date, title: title(for: id), body: body,
                            sound: id == AlertIdentifier.setWarning ? .warning : .standard)
    }

    static func title(for id: String) -> String {
        switch id {
        case AlertIdentifier.rest: return "Rest over"
        case AlertIdentifier.setEnd: return "Time!"
        case AlertIdentifier.setWarning: return "Almost there"
        case AlertIdentifier.setMinimum: return "Minimum reached"
        default: return "Jimm's Bro+"
        }
    }
}

/// Records what would have been scheduled or played. Used by tests and by previews.
final class RecordingAlerts: NotificationScheduling, AlertPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var _scheduled: [NotificationRequest] = []
    private var _cancelled: [String] = []
    private var _played: [TimerBeep] = []
    private var _feedback: [Feedback] = []
    var authorized = true

    var scheduled: [NotificationRequest] { lock.withLock { _scheduled } }
    var cancelled: [String] { lock.withLock { _cancelled } }
    var played: [TimerBeep] { lock.withLock { _played } }
    var feedback: [Feedback] { lock.withLock { _feedback } }
    /// The requests that have not since been cancelled, in scheduling order.
    var pending: [NotificationRequest] {
        lock.withLock {
            var live: [String: NotificationRequest] = [:]
            var order: [String] = []
            for request in _scheduled {
                if live[request.id] == nil { order.append(request.id) }
                live[request.id] = request
            }
            for id in _cancelled where live[id] != nil { live[id] = nil }
            return order.compactMap { live[$0] }
        }
    }

    var asked = false
    func requestAuthorization() async -> Bool { asked = true; return authorized }
    func authorizationState() async -> NotificationState {
        guard asked else { return .notAsked }
        return authorized ? .allowed : .denied
    }
    func schedule(_ request: NotificationRequest) async {
        lock.withLock { _scheduled.append(request); _cancelled.removeAll { $0 == request.id } }
    }
    func cancel(ids: [String]) async { lock.withLock { _cancelled.append(contentsOf: ids) } }
    func play(_ beep: TimerBeep, sound: Bool, vibration: Bool) {
        lock.withLock { if sound || vibration { _played.append(beep) } }
    }
    func play(feedback: Feedback, vibration: Bool) {
        lock.withLock { if vibration { _feedback.append(feedback) } }
    }
    func reset() { lock.withLock { _scheduled = []; _cancelled = []; _played = []; _feedback = [] } }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
