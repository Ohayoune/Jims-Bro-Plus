import Foundation

/// SPEC §6.66 (D93, v1.11): Add exercise's search, under a field that reads **Find an
/// exercise** (D66's words). The names the app already knows — the day's plan's first, then the
/// other plans', then History's — each once, each with where it was found, so a name chosen here
/// is the name last time's history is under (§4.3's footer).
enum ExerciseNames {
    struct Name: Equatable {
        var name: String
        /// A plan's name — *Upper Lower* — or *History*.
        var source: String
    }

    static let historySource = "History"
    /// The search field's words (D66).
    static let prompt = "Find an exercise"

    /// Every known name matching `query` by a case-insensitive contains; an empty query matches
    /// all. `plans` in the order given — the day's plan first — then History's, the most recent
    /// workout first. A name is kept where it is first found, compared as the app compares names
    /// everywhere (`normalized`), and written as it was found there.
    static func known(plans: [Plan], history: [Session], query: String) -> [Name] {
        var seen = Set<String>()
        var names: [Name] = []
        func keep(_ name: String, from source: String) {
            guard !name.trimmed.isEmpty, seen.insert(normalized(name)).inserted else { return }
            names.append(Name(name: name, source: source))
        }
        for plan in plans {
            for exercise in plan.days.flatMap(\.exercises) { keep(exercise.name, from: plan.name) }
        }
        for session in history.sorted(by: { $0.startedAt > $1.startedAt }) {
            for exercise in session.exercises { keep(exercise.name, from: historySource) }
        }
        let wanted = query.trimmed
        guard !wanted.isEmpty else { return names }
        return names.filter { $0.name.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// A name typed that matches nothing is added as typed: the query, trimmed, when no known
    /// name is that name; nil for an empty query or one already known.
    static func typed(_ query: String, known: [Name]) -> String? {
        let wanted = query.trimmed
        guard !wanted.isEmpty, !known.contains(where: { normalized($0.name) == normalized(wanted) }) else { return nil }
        return wanted
    }
}

extension PlanLibrary {
    /// Add exercise's names: the active plan's first, then every other plan in the Plans list's
    /// order, then History.
    func exerciseNames(matching query: String) -> [ExerciseNames.Name] {
        let ordered = plans.filter { $0.id == activePlanId } + plans.filter { $0.id != activePlanId }
        return ExerciseNames.known(plans: ordered, history: sessions, query: query)
    }
}
