import Foundation

/// One month of the History list (SPEC §4.10), newest first.
struct HistoryMonth: Identifiable, Equatable {
    /// The first instant of the month, which also orders the sections.
    var id: Date
    var title: String
    /// Sessions in the month, newest first.
    var sessions: [Session]
}

enum HistoryGrouping {
    /// Completed sessions grouped by the local calendar month of `startedAt`, newest month first
    /// and newest session first inside each. A session still running is not history yet.
    static func months(_ sessions: [Session], calendar: Calendar = .current,
                       locale: Locale = .current) -> [HistoryMonth] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        // The key is the month's first instant in `calendar`, so the formatter must read it
        // back in the same zone or a month boundary lands one month early.
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")

        let finished = sessions.filter { $0.endedAt != nil }
        let grouped = Dictionary(grouping: finished) { session -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: session.startedAt))
                ?? calendar.startOfDay(for: session.startedAt)
        }
        return grouped.map { start, sessions in
            HistoryMonth(id: start, title: formatter.string(from: start),
                         sessions: sessions.sorted { $0.startedAt > $1.startedAt })
        }
        .sorted { $0.id > $1.id }
    }
}

/// Text for the History and exercise-history screens.
enum ExerciseText {
    /// SPEC §6.7: the heaviest logged set, ties broken by reps. Weightless sets fall back to
    /// most reps, and an exercise with only timed sets falls back to its longest hold.
    static func best(steps: [SessionStep], units: WeightUnit) -> String? {
        if let result = SessionStats.best(steps) { return bestSet(result, units: units).map { "Best: \($0)" } }
        let longest = steps.filter { $0.status == .logged }.compactMap { $0.result?.seconds }.max()
        return longest.map { "Best: \(TargetText.time($0))" }
    }

    /// A best set: "60 kg × 10", "10 reps" without a weight, or a hold's time. History's line
    /// and the Summary's metrics both say it this way.
    static func bestSet(_ result: SetResult, units: WeightUnit) -> String? {
        if let seconds = result.seconds { return TargetText.time(seconds) }
        guard let reps = result.reps else { return nil }
        guard let weight = result.weight else { return "\(reps) reps" }
        return "\(TargetText.number(weight)) \(units.rawValue) × \(reps)"
    }

    /// One logged step as the detail screens show it: "10 × 60 · 0:34". D58 (v1.6): the same
    /// sentence the workout's own rows use, so the two cannot drift apart in either grammar.
    static func result(_ step: SessionStep, wording: Wording = .plain) -> String {
        switch step.status {
        case .pending: return "—"
        case .skipped: return "skipped"
        case .logged:
            guard let result = step.result else { return "" }
            return StepCard.resultText(result, setSeconds: step.setSeconds, wording: wording)
        }
    }

    /// The one-line subtitle of a History row.
    /// "28 min · 16 sets · 13,920 kg lifted" (D59, v1.6: "28:08 · 16 sets · 13,920 kg" read as a
    /// clock time and an unlabelled weight — Metrics labels its numbers, and so does the row).
    static func summary(_ session: Session) -> String {
        var parts = [HomeActivity.duration(SessionStats.duration(session))]
        let sets = SessionStats.loggedCount(session)
        parts.append("\(sets) set\(sets == 1 ? "" : "s")")
        let volume = SessionStats.volume(session.steps)
        if volume > 0 { parts.append("\(TargetText.grouped(volume)) \(session.units.rawValue) lifted") }
        // D44 (v1.3): which week of the progression it was, when it was one.
        if let week = ProgressionText.weekLine(session) { parts.append(week) }
        return parts.joined(separator: " · ")
    }

    /// D30 (v1.1): every exercise in history, de-duplicated by normalized name and ordered by
    /// how recently it was done, filtered by a search query. History's search box uses it, so
    /// finding one exercise no longer means remembering which day you did it on.
    static func search(_ query: String, sessions: [Session]) -> [String] {
        let needle = normalized(query)
        var seen = Set<String>()
        var found: [String] = []
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            for name in session.exercises.map(\.name) {
                let key = normalized(name)
                guard needle.isEmpty || key.contains(needle), seen.insert(key).inserted else { continue }
                found.append(name)
            }
        }
        return found
    }

    /// The names an exercise-history screen can be opened for, in session order, de-duplicated.
    static func exerciseNames(_ session: Session) -> [String] {
        var seen = Set<String>()
        return session.exercises.map(\.name).filter { seen.insert(normalized($0)).inserted }
    }
}

/// SPEC §4.8 and §4.10 (v1.2): a session's steps grouped into the blocks the screens draw.
///
/// The Overview and Session detail had each written this out — with different name matching —
/// and a superset is exactly where those two disagreed. One definition, two callers, and the
/// grouping rule becomes a unit test rather than a coincidence.
enum SessionBlocks {
    /// The step indices of each block, ordered by where a block's steps now sit rather than by
    /// `blockIndex`: "Do later" (D28) moves a block's steps without renumbering it, so sorting
    /// on the index would still draw the deferred exercise in its old place.
    static func indices(_ session: Session) -> [[Int]] {
        Dictionary(grouping: session.steps.indices, by: { session.steps[$0].blockIndex })
            .map { $0.value.sorted() }
            .sorted { ($0.first ?? 0) < ($1.first ?? 0) }
    }

    /// D42 (v1.3): the exercise an index counts as. A substitute appended mid-workout
    /// (`replaces`) is the same position in the day as the exercise it stood in for, so
    /// "Exercise 2 of 5" stays 2 of 5 after a change. Follows a chain of substitutions.
    static func canonical(_ session: Session, _ index: Int) -> Int {
        var current = index
        var hops = 0
        while let next = session.exercises[safe: current]?.replaces, hops < session.exercises.count {
            current = next; hops += 1
        }
        return current
    }

    /// The day's exercises in the order it now runs them — after "Do later" (D28) has moved a
    /// block and a substitute (D42) has joined one — each position counted once.
    static func exerciseOrder(_ session: Session) -> [Int] {
        var seen = Set<Int>()
        return indices(session)
            .flatMap { block in block.map { canonical(session, session.steps[$0].exerciseIndex) } }
            .filter { seen.insert($0).inserted }
    }

    /// The exercises in a block, in order, de-duplicated the way exercise history matches
    /// names (§6.9) — so "Bench press" and "Bench Press" are one exercise here too.
    static func names(_ session: Session, _ indices: [Int]) -> [String] {
        var seen = Set<String>()
        return indices
            .compactMap { session.exercises[safe: session.steps[$0].exerciseIndex]?.name }
            .filter { seen.insert(normalized($0)).inserted }
    }

    /// "Lateral Raise + Tricep Pushdown · 4:12" — the block's exercises and how long it took,
    /// the duration only once the block is finished.
    static func title(_ session: Session, _ indices: [Int]) -> String {
        var text = names(session, indices).joined(separator: " + ")
        if let block = indices.first.map({ session.steps[$0].blockIndex }),
           let seconds = SessionStats.blockDuration(block, session: session) {
            text += " · \(TargetText.time(seconds))"
        }
        return text
    }

    /// Whether the rows must name their exercise: in a superset every row would otherwise read
    /// "A · Set 1 of 3" and two rows of a round would be indistinguishable.
    static func namesRows(_ session: Session, _ indices: [Int]) -> Bool {
        Set(indices.map { session.steps[$0].exerciseIndex }).count > 1
    }
}
