import Foundation

extension MarkState {
    /// D79 (v1.10, §6.52): the one rule, written once. A logged step is done; the step the
    /// workout is on — the working step, or the one a rest leads to — is now; every other step
    /// is not yet, a skipped one included, so nothing draws a skip as though it happened. A
    /// skipped step given a result is logged (D27), and so done.
    static func of(step index: Int, session active: ActiveSession) -> MarkState {
        guard let step = active.session.steps[safe: index] else { return .todo }
        switch step.status {
        case .logged: return .done
        case .skipped: return .todo
        case .pending: return index == active.currentStep ? .now : .todo
        }
    }

    /// D81 (v1.10, §6.54): an exercise's own dot — now while one of its steps is, done once every
    /// step is logged, and not yet otherwise, a skipped step included.
    static func of(exercise: Int, session active: ActiveSession) -> MarkState {
        let steps = active.session.steps.indices.filter { active.session.steps[$0].exerciseIndex == exercise }
        if steps.contains(where: { of(step: $0, session: active) == .now }) { return .now }
        if !steps.isEmpty, steps.allSatisfy({ active.session.steps[$0].status == .logged }) { return .done }
        return .todo
    }
}

extension ActiveSession {
    /// The step the workout is on: the working step, or the step a rest leads to. Nil once the
    /// session is complete.
    var currentStep: Int? {
        switch phase {
        case let .working(step): return step
        case let .resting(rest): return rest.nextStep
        case .completed: return nil
        }
    }
}

/// SPEC §6.53 (D80, v1.10): the header is the bar. One segment per block, in the order the day
/// runs them, a mark per set inside each, and a caret under the segment being looked at. The
/// view draws it in one `Canvas`; this is everything it needs to know.
struct WorkoutBar: Equatable {
    struct Segment: Equatable {
        /// The steps' own `blockIndex`, which "Do later" (D28) keeps while it moves the block.
        var blockIndex: Int
        /// How much of the bar the segment takes, relative to the others: the block's pace
        /// (D84, `Pace.weights`) when the screen passes one, and its set count otherwise.
        var weight: Double
        /// One state per step, in order — a drop and a superset member's set are steps too.
        var sets: [MarkState]
        /// Whether the caret sits under this segment.
        var caret: Bool
    }

    var segments: [Segment]

    /// `showing` is the block being looked at, by `blockIndex` — the page on screen (D83); nil is
    /// the current step's block. Only the caret follows it: the marks are the record. `weights`
    /// is one per block in the bar's order (`Pace.weights`); nil, or the wrong count, is by set
    /// count, as P1 drew it.
    static func of(session active: ActiveSession, showing: Int? = nil, weights: [Double]? = nil) -> WorkoutBar {
        let session = active.session
        let looked = showing ?? active.currentStep.flatMap { session.steps[safe: $0]?.blockIndex }
        let blocks = SessionBlocks.indices(session)
        let paced = weights.flatMap { $0.count == blocks.count ? $0 : nil }
        return WorkoutBar(segments: blocks.enumerated().compactMap { position, block in
            guard let first = block.first.flatMap({ session.steps[safe: $0] }) else { return nil }
            return Segment(blockIndex: first.blockIndex,
                           weight: paced?[position] ?? Double(block.count),
                           sets: block.map { MarkState.of(step: $0, session: active) },
                           caret: first.blockIndex == looked)
        })
    }
}
