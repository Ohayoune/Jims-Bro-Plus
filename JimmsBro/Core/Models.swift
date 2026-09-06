import Foundation

enum WeightUnit: String, Codable, CaseIterable { case kg, lb }
enum Schedule: String, Codable { case rotation, weekday }
enum Severity: String, Codable { case error, warning }
enum Weekday: String, Codable, CaseIterable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    var calendarValue: Int { (Self.allCases.firstIndex(of: self).map { ($0 + 1) % 7 + 1 }) ?? 2 }
}
struct Issue: Codable, Equatable {
    var severity: Severity
    var code: String
    var path: String
    var message: String
}
struct Plan: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var units: WeightUnit
    var schedule: Schedule
    var days: [Day]
    var importedAt: Date
    var sourceText: String
    var warnings: [Issue] = []
    var cycle: [CycleEntry]
    var cyclePosition: Int?
}
struct Day: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var weekday: Weekday?
    var exercises: [Exercise]
}
struct Exercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var group: String?
    var notes: String?
    var repRange: RepRange?
    var bodyweight = false
    var sets: [SetTarget]
}
struct RepRange: Codable, Equatable { var min: Int; var max: Int }
struct SetTarget: Codable, Equatable {
    var work: WorkTarget
    var weight: Double?
    var restSeconds: Int
    var warningBeepSeconds: Int?
    var drops: [DropTarget] = []
    // A group's round rest is resolved at import, before explicit/default provenance is lost.
    var groupRestSeconds: Int?
}
struct DropTarget: Codable, Equatable { var work: WorkTarget; var weight: Double? }
enum WorkTarget: Codable, Equatable {
    case reps(RepTarget), duration(seconds: Int), openDuration(minSeconds: Int?)
    var isTimed: Bool { if case .reps = self { return false }; return true }
}
enum RepTarget: Codable, Equatable { case fixed(Int), range(min: Int, max: Int), amrap(min: Int?) }
struct Step: Equatable {
    let exerciseIndex: Int
    let setIndex: Int
    let dropIndex: Int
    let blockIndex: Int
    let isLastInRound: Bool
    let isLastInBlock: Bool
}
enum CycleEntry: Codable, Equatable { case day(Int), rest }
struct Session: Codable, Identifiable, Equatable {
    var id = UUID()
    var planId: UUID?
    var planName: String
    var dayName: String
    var units: WeightUnit
    var startedAt: Date
    var endedAt: Date?
    var exercises: [SessionExercise]
    var steps: [SessionStep]
}
struct SessionExercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var group: String?
    var notes: String?
    var repRange: RepRange?
    var bodyweight = false
    var targets: [SetTarget]
    var advice: Advice?

    /// D11 (v1.1): true when the main-set target weights are not all equal (or all absent) — a
    /// deliberately programmed pyramid, say. Prefill (§6.5) never carries a weight forward
    /// across sets within the same session for one of these; it always reads last session's
    /// same set index, or that set's own target.
    var hasVariedTargets: Bool {
        guard let first = targets.first else { return false }
        return targets.contains { $0.weight != first.weight }
    }
}
enum Advice: Codable, Equatable { case increase(to: Double), increaseLoad, decrease(to: Double), decreaseLoad }
struct ExercisePoint: Equatable {
    var date: Date
    var sets: [SetResult]
    var setSeconds: [Int?]
    var topWeight: Double?
    var topSetReps: Int?
    var topSeconds: Int?
    var volume: Double
    var units: WeightUnit
}
struct SessionStep: Codable, Equatable {
    var exerciseIndex: Int
    var setIndex: Int
    var dropIndex: Int
    var blockIndex: Int
    var isLastInRound: Bool
    var isLastInBlock: Bool
    var status: StepStatus = .pending
    var result: SetResult?
    var startedAt: Date?
    var loggedAt: Date?
    var setSeconds: Int? {
        guard status == .logged, let start = startedAt, let end = loggedAt else { return nil }
        return wholeSeconds(end.timeIntervalSince(start))
    }
}
enum StepStatus: String, Codable { case pending, logged, skipped }
enum SetResult: Codable, Equatable {
    case reps(count: Int, weight: Double?), duration(seconds: Int, weight: Double?)
    var weight: Double? { switch self { case let .reps(_, w), let .duration(_, w): return w } }
    var reps: Int? { if case let .reps(n, _) = self { return n }; return nil }
    var seconds: Int? { if case let .duration(n, _) = self { return n }; return nil }
}
/// The status strip's "block just finished" state (SPEC §4.7, D14 v1.1). Overlaid on a
/// `.working` phase rather than being its own phase, so the next set's card never waits on it;
/// it is cleared by the next log, skip, jump, undo or an explicit `dismissBlockDone`.
struct BlockDone: Codable, Equatable { var finishedBlock: Int; var startedAt: Date }

struct ActiveSession: Codable, Equatable {
    var session: Session
    var phase: Phase
    var lastRestEndedAt: Date?
    var workWeight: Double?
    var timerRunning = false
    var deliveredBeeps: Set<TimerBeep> = []
    var blockDone: BlockDone?
    /// The most recently logged-or-skipped step, valid for `undoLog` until another step is
    /// logged or skipped (D23 v1.1). Not touched by jumping, adjusting rest, or timer starts.
    var lastCompletedStep: Int?

    enum CodingKeys: String, CodingKey {
        case session, phase, lastRestEndedAt, workWeight, timerRunning, deliveredBeeps, blockDone, lastCompletedStep
    }

    /// Whether D23's undo currently applies: there is a most-recent logged-or-skipped step, it
    /// still is one, and the session is still running. `SessionEngine.canUndo` and the status
    /// strip both read this, so the affordance and the event can never disagree.
    var canUndo: Bool {
        guard phase != .completed, let step = lastCompletedStep,
              let status = session.steps[safe: step]?.status else { return false }
        return status != .pending
    }


    init(session: Session, phase: Phase, lastRestEndedAt: Date? = nil, workWeight: Double? = nil,
         timerRunning: Bool = false, deliveredBeeps: Set<TimerBeep> = [], blockDone: BlockDone? = nil,
         lastCompletedStep: Int? = nil) {
        self.session = session; self.phase = phase; self.lastRestEndedAt = lastRestEndedAt
        self.workWeight = workWeight; self.timerRunning = timerRunning; self.deliveredBeeps = deliveredBeeps
        self.blockDone = blockDone; self.lastCompletedStep = lastCompletedStep
    }

    /// A v1 file has no `blockDone` key; if its phase was the old `.transition`, reconstruct one
    /// from that payload so a session saved mid-transition survives the v1.1 upgrade (G53).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decode(Session.self, forKey: .session)
        phase = try container.decode(Phase.self, forKey: .phase)
        lastRestEndedAt = try container.decodeIfPresent(Date.self, forKey: .lastRestEndedAt)
        workWeight = try container.decodeIfPresent(Double.self, forKey: .workWeight)
        timerRunning = try container.decodeIfPresent(Bool.self, forKey: .timerRunning) ?? false
        deliveredBeeps = try container.decodeIfPresent(Set<TimerBeep>.self, forKey: .deliveredBeeps) ?? []
        if let blockDone = try container.decodeIfPresent(BlockDone.self, forKey: .blockDone) {
            self.blockDone = blockDone
        } else {
            self.blockDone = try? Phase.legacyBlockDone(from: container.superDecoder(forKey: .phase))
        }
        lastCompletedStep = try container.decodeIfPresent(Int.self, forKey: .lastCompletedStep)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(session, forKey: .session)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(lastRestEndedAt, forKey: .lastRestEndedAt)
        try container.encodeIfPresent(workWeight, forKey: .workWeight)
        try container.encode(timerRunning, forKey: .timerRunning)
        try container.encode(deliveredBeeps, forKey: .deliveredBeeps)
        try container.encodeIfPresent(blockDone, forKey: .blockDone)
        try container.encodeIfPresent(lastCompletedStep, forKey: .lastCompletedStep)
    }
}
struct RestState: Codable, Equatable { var startedAt: Date; var endsAt: Date; var nextStep: Int; var isWork = false }

/// SPEC §6.6 (v1.1): the `.transition` phase is gone — a finished block advances straight to
/// `working(next)`, with `BlockDone` describing the strip. Kept `Codable` by hand (rather than
/// synthesized) so a v1 `.transition` payload still decodes instead of crashing (G53).
enum Phase: Codable, Equatable {
    case working(step: Int), resting(RestState), completed

    private enum Key: String, CodingKey { case working, resting, completed, transition }
    private enum ZeroKey: String, CodingKey { case _0 = "_0" }
    private struct WorkingPayload: Codable, Equatable { var step: Int }
    /// The v1 shape of the removed `TransitionState`, decoded only for migration.
    private struct LegacyTransition: Decodable { var startedAt: Date; var nextStep: Int; var finishedBlock: Int }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if let payload = try container.decodeIfPresent(WorkingPayload.self, forKey: .working) {
            self = .working(step: payload.step); return
        }
        if let state = try container.decodeIfPresent(RestState.self, forKey: .resting) {
            self = .resting(state); return
        }
        if container.contains(.transition) {
            let inner = try container.nestedContainer(keyedBy: ZeroKey.self, forKey: .transition)
            let legacy = try inner.decode(LegacyTransition.self, forKey: ._0)
            self = .working(step: legacy.nextStep); return
        }
        self = .completed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case let .working(step): try container.encode(WorkingPayload(step: step), forKey: .working)
        case let .resting(state): try container.encode(state, forKey: .resting)
        case .completed: try container.encode(EmptyPayload(), forKey: .completed)
        }
    }

    /// Reconstructs a v1.1 `BlockDone` from a v1 `.transition` phase payload, if present.
    static func legacyBlockDone(from decoder: Decoder) throws -> BlockDone? {
        let container = try decoder.container(keyedBy: Key.self)
        guard container.contains(.transition) else { return nil }
        let inner = try container.nestedContainer(keyedBy: ZeroKey.self, forKey: .transition)
        let legacy = try inner.decode(LegacyTransition.self, forKey: ._0)
        return BlockDone(finishedBlock: legacy.finishedBlock, startedAt: legacy.startedAt)
    }
}
private struct EmptyPayload: Codable, Equatable {}
enum TimerBeep: String, Codable, Hashable { case warning, end, minimum }
struct Settings: Codable, Equatable {
    var units: WeightUnit = .kg
    var defaultRestSeconds = 90
    var sound = true
    var vibration = true
    var keepAwake = true
    var weightStepKg = 2.5
    var weightStepLb = 5.0
    func weightStep(for units: WeightUnit) -> Double { units == .kg ? weightStepKg : weightStepLb }
    static func defaults(locale: Locale = .current) -> Settings {
        Settings(units: locale.region?.identifier == "US" ? .lb : .kg)
    }
}
func normalized(_ name: String) -> String { name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() }
func wholeSeconds(_ value: TimeInterval) -> Int {
    guard value.isFinite, value > 0 else { return 0 }
    return Int(min(value.rounded(.down), Double(Int.max / 2)))
}
extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
