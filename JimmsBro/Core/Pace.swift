import Foundation

/// SPEC §6.57 (D84, v1.10): a bar that learns your pace. A block's stretch of the bar is as long
/// as it usually takes you — the median of its past times, the walk after it included — from the
/// third time; before that it is the day's time per set × its sets, and a day with no pace at all
/// is by set count, as P1 drew it. Held between ½× and 2× the day's typical stretch. Nothing new
/// is stored: every time is read from `SessionStep.startedAt` and `loggedAt`, written since v1.2.
enum Pace {
    /// How many past times make a pace — *"only once a history is established"*.
    static let establishedAt = 3
    /// The clamp, as multiples of the day's typical stretch.
    static let shortest = 0.5, longest = 2.0

    /// One weight per block of `day`, in the bar's order (`SessionBlocks.indices`). `history` is
    /// every session on the phone; only finished ones from before `day` count.
    static func weights(day: Session, history: [Session]) -> [Double] {
        var times: [Set<String>: [Double]] = [:]
        for session in history where session.id != day.id && session.endedAt != nil && session.startedAt < day.startedAt {
            for block in SessionBlocks.indices(session) {
                guard let time = time(of: block, in: session) else { continue }
                times[names(of: block, in: session), default: []].append(time)
            }
        }
        let blocks = SessionBlocks.indices(day)
        return weights(sets: blocks.map(\.count), medians: blocks.map { block in
            let past = times[names(of: block, in: day)] ?? []
            return past.count >= establishedAt ? median(past) : nil
        })
    }

    /// The rule apart from the clock: `medians[i]` is block i's median time, nil until it has one.
    static func weights(sets: [Int], medians: [Double?]) -> [Double] {
        let paced = zip(sets, medians).compactMap { sets, time in time.map { (sets: sets, time: $0) } }
        let pacedSets = paced.reduce(0) { $0 + $1.sets }
        guard pacedSets > 0 else { return sets.map(Double.init) }
        let perSet = paced.reduce(0) { $0 + $1.time } / Double(pacedSets)
        let stretches = zip(sets, medians).map { sets, time in time ?? perSet * Double(sets) }
        // The median, not the mean: a mean moves with the one long block it is meant to hold.
        guard let typical = median(stretches), typical > 0 else { return sets.map(Double.init) }
        return stretches.map { min(max($0, typical * shortest), typical * longest) }
    }

    /// What a block is known by: its exercises' names as they now are — a substitute's, not the
    /// original's it replaced (D42) — so a renamed exercise finds the history of its new name.
    static func names(of block: [Int], in session: Session) -> Set<String> {
        let replaced = Set(session.exercises.compactMap(\.replaces))
        return Set(block.compactMap { index -> String? in
            guard let exercise = session.steps[safe: index]?.exerciseIndex, !replaced.contains(exercise) else { return nil }
            return session.exercises[safe: exercise].map { normalized($0.name) }
        })
    }

    /// One past time of a block, in seconds: from its first start to whatever the session did
    /// next — the next block's first start, so the walk after it is counted in — or to its last
    /// log when nothing followed. A block with no logged step was not done, and has no time; a
    /// skip's timestamp never ends one, because the end of a workout skips what is left.
    static func time(of block: [Int], in session: Session) -> Double? {
        let steps = block.compactMap { session.steps[safe: $0] }
        guard let last = steps.filter({ $0.status == .logged }).compactMap(\.loggedAt).max(),
              let start = steps.flatMap({ [$0.startedAt, $0.status == .logged ? $0.loggedAt : nil] })
                .compactMap({ $0 }).min() else { return nil }
        let inBlock = Set(block)
        let next = session.steps.indices.filter { !inBlock.contains($0) }
            .flatMap { [session.steps[$0].startedAt, session.steps[$0].status == .logged ? session.steps[$0].loggedAt : nil] }
            .compactMap { $0 }
            .filter { $0 >= last }
            .min()
        let seconds = (next ?? last).timeIntervalSince(start)
        return seconds > 0 ? seconds : nil
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
