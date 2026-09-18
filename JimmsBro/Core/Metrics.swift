import Foundation

/// SPEC §4.10 / §6.16 (D39, v1.2): what a workout *was*, and what a run of them adds up to.
///
/// The owner's note: "should be able to select a past workout and see … metrics for the past —
/// I don't know exactly what metrics would be, but they should be included." v1.1 could open a
/// past session and read its sets back, and that was all: the numbers a person actually asks
/// about — how long it took, how much of that was resting, how much was lifted, whether
/// anything was a record — were either not computed or scattered across three screens.
///
/// Everything here is a `Metric`: a label, a value already formatted, and a one-line note when
/// the number needs one. Views render the list; they compute nothing.
struct Metric: Equatable, Identifiable {
    var label: String
    var value: String
    var note: String?
    var id: String { label }
}

enum SessionMetrics {
    /// The metrics of one finished workout, in the order they answer the obvious questions.
    static func of(_ session: Session, history: [Session] = []) -> [Metric] {
        let logged = session.steps.filter { $0.status == .logged }
        let skipped = session.steps.filter { $0.status == .skipped }
        var metrics: [Metric] = []

        let total = wholeSeconds(SessionStats.duration(session))
        metrics.append(Metric(label: "Duration", value: HomeActivity.duration(Double(total))))

        // Working time is the sum of the sets themselves; the rest of the session was rest,
        // walking, or standing about — which is most of a workout, and worth seeing.
        let working = logged.compactMap(\.setSeconds).reduce(0, +)
        if working > 0 {
            metrics.append(Metric(label: "Working", value: HomeActivity.duration(Double(working)),
                                  note: percentage(working, of: total).map { "\($0) of the session" }))
            let resting = max(0, total - working)
            metrics.append(Metric(label: "Resting", value: HomeActivity.duration(Double(resting)),
                                  note: percentage(resting, of: total).map { "\($0) of the session" }))
        }

        let done = logged.count, planned = session.steps.count
        metrics.append(Metric(label: "Sets", value: "\(done) of \(planned)",
                              note: skipped.isEmpty ? nil
                                  : "\(skipped.count) skipped"))

        let volume = SessionStats.volume(session.steps)
        if volume > 0 {
            metrics.append(Metric(label: "Volume",
                                  value: "\(TargetText.grouped(volume)) \(session.units.rawValue)",
                                  note: "weight × reps, across every set"))
        }

        let reps = logged.compactMap { $0.result?.reps }.reduce(0, +)
        if reps > 0 { metrics.append(Metric(label: "Reps", value: "\(reps)")) }

        let held = logged.compactMap { $0.result?.seconds }.reduce(0, +)
        if held > 0 {
            metrics.append(Metric(label: "Time under tension",
                                  value: HomeActivity.duration(Double(held))))
        }

        if let best = SessionStats.best(logged), let text = ExerciseText.bestSet(best, units: session.units) {
            metrics.append(Metric(label: "Heaviest set", value: text))
        }

        let records = SessionStats.personalRecords(session: session, history: history)
        if !records.isEmpty {
            let names = records.compactMap { index -> String? in
                guard let step = session.steps[safe: index] else { return nil }
                return session.exercises[safe: step.exerciseIndex]?.name
            }
            var seen = Set<String>()
            let unique = names.filter { seen.insert(normalized($0)).inserted }
            metrics.append(Metric(label: "Personal records", value: "\(records.count)",
                                  note: unique.joined(separator: ", ")))
        }

        if let average = SessionStats.averageSetSeconds(session) {
            metrics.append(Metric(label: "Average set",
                                  value: TargetText.time(Int(average.rounded()))))
        }
        return metrics
    }

    private static func percentage(_ part: Int, of whole: Int) -> String? {
        guard whole > 0, part >= 0 else { return nil }
        return "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }
}

/// D39 (v1.2): what a run of workouts adds up to. Over a window, so "this is what you have been
/// doing lately" is answerable, and all-time, so the totals are there too.
enum TrendMetrics {
    /// The completed sessions of the last `days` days, newest first.
    static func recent(_ sessions: [Session], days: Int, now: Date = Date(),
                       calendar: Calendar = .current) -> [Session] {
        guard let start = calendar.date(byAdding: .day, value: -days,
                                        to: calendar.startOfDay(for: now)) else { return [] }
        return sessions.filter { $0.endedAt != nil && $0.startedAt >= start }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func summary(_ sessions: [Session], days: Int = 30, now: Date = Date(),
                        calendar: Calendar = .current) -> [Metric] {
        let window = recent(sessions, days: days, now: now, calendar: calendar)
        let all = sessions.filter { $0.endedAt != nil }
        guard !all.isEmpty else { return [] }
        var metrics: [Metric] = []

        let weeks = max(1.0, Double(days) / 7)
        let perWeek = Double(window.count) / weeks
        metrics.append(Metric(label: "Workouts", value: "\(window.count)",
                              note: "\(TargetText.number(perWeek)) a week over \(days) days"))

        let time = window.reduce(0.0) { $0 + SessionStats.duration($1) }
        if time > 0 {
            metrics.append(Metric(label: "Time trained", value: HomeActivity.duration(time),
                                  note: window.isEmpty ? nil
                                      : "about \(HomeActivity.duration(time / Double(window.count))) a workout"))
        }

        // Volume only adds up within one unit; the app never converts (D10).
        let units = window.first?.units ?? all.first?.units ?? .kg
        let volume = window.filter { $0.units == units }
            .reduce(0.0) { $0 + SessionStats.volume($1.steps) }
        if volume > 0 {
            metrics.append(Metric(label: "Volume",
                                  value: "\(TargetText.grouped(volume)) \(units.rawValue)",
                                  note: "over \(days) days"))
        }

        let sets = window.reduce(0) { $0 + SessionStats.loggedCount($1) }
        if sets > 0 { metrics.append(Metric(label: "Sets logged", value: "\(sets)")) }

        let streak = streakWeeks(all, now: now, calendar: calendar)
        if streak > 0 {
            metrics.append(Metric(label: "Weeks in a row", value: "\(streak)",
                                  note: "at least one workout each week"))
        }

        if let favourite = mostTrained(window) {
            metrics.append(Metric(label: "Most trained", value: favourite.name,
                                  note: "\(favourite.count) session\(favourite.count == 1 ? "" : "s")"))
        }

        metrics.append(Metric(label: "All time", value: "\(all.count) workouts",
                              note: all.map(\.startedAt).min().map {
                                  "since " + $0.formatted(.dateTime.month(.abbreviated).year())
                              }))
        return metrics
    }

    /// Consecutive calendar weeks, counting back from the week containing `now`, in which at
    /// least one workout was finished. The current week counts only once it has one.
    static func streakWeeks(_ sessions: [Session], now: Date = Date(),
                            calendar: Calendar = .current) -> Int {
        let weeks = Set(sessions.filter { $0.endedAt != nil }.compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start
        })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return streak
    }

    /// The exercise done in the most sessions, by §6.9's name matching.
    static func mostTrained(_ sessions: [Session]) -> (name: String, count: Int)? {
        var counts: [String: (name: String, count: Int)] = [:]
        for session in sessions {
            var seen = Set<String>()
            for exercise in session.exercises {
                let key = normalized(exercise.name)
                guard seen.insert(key).inserted else { continue }
                counts[key] = (counts[key]?.name ?? exercise.name, (counts[key]?.count ?? 0) + 1)
            }
        }
        return counts.values.max { ($0.count, $1.name) < ($1.count, $0.name) }
    }
}
