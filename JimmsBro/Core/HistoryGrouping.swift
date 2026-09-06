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
        if let result = SessionStats.best(steps) {
            guard let reps = result.reps else { return nil }
            guard let weight = result.weight else { return "Best: \(reps) reps" }
            return "Best: \(TargetText.number(weight)) \(units.rawValue) × \(reps)"
        }
        let longest = steps.filter { $0.status == .logged }.compactMap { $0.result?.seconds }.max()
        return longest.map { "Best: \(TargetText.time($0))" }
    }

    /// One logged step as the detail screens show it: "10 @ 60 · 0:34".
    static func result(_ step: SessionStep) -> String {
        switch step.status {
        case .pending: return "—"
        case .skipped: return "skipped"
        case .logged:
            guard let result = step.result else { return "" }
            var text = result.reps.map(String.init) ?? result.seconds.map(TargetText.time) ?? ""
            if let weight = result.weight { text += " @ \(TargetText.number(weight))" }
            if let seconds = step.setSeconds { text += " · \(TargetText.time(seconds))" }
            return text
        }
    }

    /// The one-line subtitle of a History row.
    static func summary(_ session: Session) -> String {
        var parts = [TargetText.time(wholeSeconds(SessionStats.duration(session)))]
        parts.append("\(SessionStats.loggedCount(session)) sets")
        let volume = SessionStats.volume(session.steps)
        if volume > 0 { parts.append("\(TargetText.grouped(volume)) \(session.units.rawValue)") }
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
