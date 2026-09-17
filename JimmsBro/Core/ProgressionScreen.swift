import Foundation

/// SPEC §6.65 (D92, v1.11): Progression's planning screen as Core data — the two choices as rows
/// of pre-marked tiles, the trip's stage (§6.60) and the words of its bottom slot. The view holds
/// one of these and draws it; it never composes a title or decides a stage.
///
/// **Ask** marks the steps (4 · 6 · 8 · 12, six marked) and the mode (*When I hit it* marked,
/// *Every week* beside it); a tap marks and Send confirms (D85's rule). **Paste** dims the tiles
/// and holds them — the ···'s *Change the steps* returns to Ask. A paste becomes **Review** or
/// **Refused**, and Review's one button, **Start step 1**, hands back the progression to attach.
struct ProgressionScreen: Equatable {
    /// One tile of a joined row: its words, and whether it is the marked one.
    struct Tile: Equatable {
        var title: String
        var marked: Bool
    }

    /// J5: six steps, earned — what a progression is planned with until a tile says otherwise.
    static let defaultSteps = 6
    static let defaultMode = ProgressionMode.performance
    /// The mode tiles in order, the default first.
    static let modes: [ProgressionMode] = [.performance, .calendar]

    private(set) var steps = defaultSteps
    private(set) var mode = defaultMode
    private(set) var stage = TripStage.ask
    /// Refused: what stopped the paste. Review: the reply's warnings.
    private(set) var issues: [Issue] = []
    /// The progression drawn from the reply, while it is reviewed.
    private(set) var progression: Progression?
    /// **Start step 1** was tapped: the progression is the plan's.
    private(set) var started = false

    // MARK: - The tiles

    static func tiles(_ steps: Int) -> [Tile] {
        Progression.periods.map { Tile(title: String($0), marked: $0 == steps) }
    }

    static func tiles(_ mode: ProgressionMode) -> [Tile] {
        modes.map { Tile(title: title($0), marked: $0 == mode) }
    }

    /// The mode in the tile's words: *When I hit it* (D53's steps you earn) or *Every week*.
    static func title(_ mode: ProgressionMode) -> String {
        mode == .performance ? "When I hit it" : "Every week"
    }

    var stepTiles: [Tile] { Self.tiles(steps) }
    var modeTiles: [Tile] { Self.tiles(mode) }

    /// The tiles change on Ask only; from Paste on they dim and hold, because the prompt that
    /// went out said these numbers.
    var editable: Bool { stage == .ask && !started }

    mutating func mark(steps: Int) {
        guard editable, Progression.periods.contains(steps) else { return }
        self.steps = steps
    }

    mutating func mark(mode: ProgressionMode) {
        guard editable else { return }
        self.mode = mode
    }

    // MARK: - The trip

    /// Where the fix is on a refusal: at Paste when what was pasted was the prompt itself or
    /// nothing, at Chat for a reply the chatbot must write again.
    var fixAt: Int { Self.fixAt(issues) }

    static func fixAt(_ issues: [Issue]) -> Int {
        issues.contains { $0.code == "E_PROMPT_PASTED" || $0.code == "E_EMPTY" } ? 2 : 1
    }

    var strip: TripStrip { TripStrip.of(stage, fixAt: fixAt) }

    /// The bottom slot: Send and Copy on Ask, and again on Refused — a progression has no fix-it
    /// prompt of its own, so the trouble goes back as the prompt — the system's Paste on Paste,
    /// and **Start step 1** on Review.
    var buttons: TripButtons {
        switch stage {
        case .ask, .refused: return .ask()
        case .paste: return .paste
        case .review: return .effect(startTitle)
        }
    }

    /// **Start step 1** — *Start week 1* for a calendar progression, whose Progression row then
    /// reads *Week 1 of 6* (D53's words).
    var startTitle: String { Self.startTitle(progression?.mode ?? mode) }

    static func startTitle(_ mode: ProgressionMode) -> String {
        "Start \(ProgressionText.word(mode).lowercased()) 1"
    }

    /// Refused's sentence, for the red band (D26's friendly words; the path behind Details).
    var refusal: String? {
        guard stage == .refused else { return nil }
        return issues.first { $0.severity == .error }.map(IssueText.friendly)
    }

    /// The prompt for the marked tiles, with the plan's last sessions whenever there are any (J5).
    func prompt(plan: Plan, history: [Session], settings: Settings, now: Date = Date()) -> String {
        Prompts.progression(plan: plan, history: history, weeks: steps, settings: settings, now: now, mode: mode)
    }

    /// Send or Copy (D88): Ask — or Refused, sending the prompt again — becomes Paste.
    mutating func sent() {
        guard stage == .ask || stage == .refused, !started else { return }
        stage = .paste
        issues = []
    }

    /// The ···'s **Change the steps**: back to Ask with the tiles as they were marked.
    mutating func changeSteps() {
        guard stage == .paste || stage == .refused, !started else { return }
        stage = .ask
        issues = []
        progression = nil
    }

    /// What the pipeline made of a paste — or of the text behind the ··· — read in the marked
    /// mode: Review with its warnings, or Refused with what stopped it.
    mutating func read(_ result: ProgressionImport.Result) {
        guard !started else { return }
        if let drawn = result.progression, result.errors.isEmpty {
            progression = drawn
            issues = result.issues.filter { $0.severity == .warning }
            stage = .review
        } else {
            progression = nil
            issues = result.errors
            stage = .refused
        }
    }

    /// The review closed without starting: back to Paste, the reply still on the clipboard.
    mutating func cancelReview() {
        guard stage == .review, !started else { return }
        stage = .paste
        issues = []
        progression = nil
    }

    /// **Start step 1**: the progression to attach (`setProgression`), once.
    mutating func start() -> Progression? {
        guard stage == .review, !started, let progression else { return nil }
        started = true
        return progression
    }

    // MARK: - The review's words

    /// The review's header, the one place the mode is said: *6 steps · when you hit it*.
    static func header(_ progression: Progression) -> String {
        let count = progression.weeks
        return "\(count) step\(count == 1 ? "" : "s") · " + (progression.mode == .performance ? "when you hit it" : "every week")
    }

    // MARK: - The text behind the ··· (D95, §6.68)

    /// **Edit the text**'s sheet: named, pre-filled with the last text read or else a reply that
    /// reads as it stands — every exercise of the plan, each step `{}` — and a Save that says its
    /// effect. `JSONPoint` has no progression kind (the trunk's; a line for N6), so this rides
    /// `.ownDay`'s reading — one object whose paths start at its root, which is how a
    /// progression's paths are written, so a refusal still marks its line.
    static func textPoint(plan: Plan, steps: Int, text: String) -> JSONPoint {
        JSONPoint(kind: .ownDay, title: "The progression",
                  place: "Steps for \(plan.name). Nothing changes until you start.",
                  template: text.trimmed.isEmpty ? exampleReply(plan: plan, steps: steps) : text,
                  saveTitle: "Review the steps",
                  footer: "Each step gives a weight, reps or both; {} keeps the plan's own.")
    }

    /// A reply for `plan` that holds every exercise where it is for `steps` steps, so a change is
    /// one number written into a `{}`.
    static func exampleReply(plan: Plan, steps: Int) -> String {
        let empty = Array(repeating: "{}", count: max(1, steps)).joined(separator: ", ")
        let lines = plan.days.flatMap { day in
            day.exercises.map { exercise in
                "    { \"day\": \(quoted(day.name)), \"name\": \(quoted(exercise.name)), \"steps\": [\(empty)] }"
            }
        }
        return "{\n  \"steps\": \(max(1, steps)),\n  \"exercises\": [\n" + lines.joined(separator: ",\n") + "\n  ]\n}\n"
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
