import Foundation

/// SPEC §6.65 (D92, v1.11): Progression's planning screen as Core data — the two choices as rows
/// of pre-marked tiles, the trip's stage (§6.60) and the words of its bottom slot. The view holds
/// one of these and draws it; it never composes a title or decides a stage.
///
/// **Ask** marks the steps (4 · 6 · 8 · 12, six marked) and the mode (*When I hit it* marked,
/// *Every week* beside it); a tap marks and Send confirms (D85's rule). **Paste** dims the tiles
/// and holds them — the ···'s *Send the prompt again* returns to Ask. A paste becomes **Review** or
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
    /// What stopped the paste, while the screen is on Refused. A progression has no fix-it prompt
    /// of its own, so the trouble goes back as the prompt.
    private(set) var refusal: TripRefusal?
    /// The reply's warnings, while it is reviewed.
    private(set) var warnings: [Issue] = []
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

    var strip: TripStrip { TripStrip.of(stage, fix: refusal?.fix ?? .chat) }

    /// The bottom slot: Send and Copy on Ask, and again on Refused, the system's Paste on Paste,
    /// and **Start step 1** on Review.
    var buttons: TripButtons {
        switch stage {
        case .ask: return .ask()
        case .refused: return refusal?.buttons() ?? .ask()
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

    /// The prompt for the marked tiles, with the plan's last sessions whenever there are any (J5).
    func prompt(plan: Plan, history: [Session], settings: Settings, now: Date = Date()) -> String {
        Prompts.progression(plan: plan, history: history, weeks: steps, settings: settings, now: now, mode: mode)
    }

    /// The share sheet's subject.
    static func subject(_ plan: Plan) -> String { "Progression for \(plan.name)" }

    /// The ··· (D95, §6.68): on the planning screen, **Send the prompt again** once the prompt has
    /// gone and **Keep the current one** when there is one; **Remove progression** whenever there
    /// is one; and **Edit the text** last while planning. It appears with the screen and is never
    /// earned (§6.40).
    func menu(hasProgression: Bool, planning: Bool) -> [TripMenuItem] {
        let onPlanning = planning || !hasProgression
        var items: [TripMenuItem] = []
        if onPlanning, stage == .paste || stage == .refused { items.append(.sendAgain) }
        if onPlanning, hasProgression { items.append(.keepCurrent) }
        if hasProgression { items.append(.removeProgression) }
        if onPlanning { items.append(.editText) }
        return items
    }

    /// Send or Copy (D88): Ask — or Refused, sending the prompt again — becomes Paste.
    mutating func sent() {
        guard stage == .ask || stage == .refused, !started else { return }
        stage = .paste
        refusal = nil
    }

    /// The ···'s **Send the prompt again** (`TripText.sendAgain`): back to Ask with the tiles as
    /// they were marked, where Send and Copy are one tap — the same item, doing the same thing, as
    /// Add plan's and Say what should change's (the owner's reading, N6). The tiles being on Ask,
    /// it is also how the steps are changed.
    mutating func restart() {
        guard stage == .paste || stage == .refused, !started else { return }
        stage = .ask
        refusal = nil
        warnings = []
        progression = nil
    }

    /// What the pipeline made of a paste — or of the text behind the ··· — read in the marked
    /// mode: Review with its warnings, or Refused with what stopped it.
    mutating func read(_ result: ProgressionImport.Result) {
        guard !started else { return }
        if let drawn = result.progression, result.errors.isEmpty {
            progression = drawn
            refusal = nil
            warnings = result.issues.filter { $0.severity == .warning }
            stage = .review
        } else {
            progression = nil
            refusal = TripRefusal.of(result.issues, way: .prompt)
            warnings = []
            stage = .refused
        }
    }

    /// The review closed without starting: back to Paste, the reply still on the clipboard.
    mutating func cancelReview() {
        guard stage == .review, !started else { return }
        stage = .paste
        warnings = []
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
        return "\(TargetText.counted(count, "step")) · " + (progression.mode == .performance ? "when you hit it" : "every week")
    }
}
