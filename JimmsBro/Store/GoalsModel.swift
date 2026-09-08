import Foundation

/// SPEC §6.30 (D54, v1.5): the app side of goals. They live in `goals.json`, are marked
/// reached by the library when a workout completes, and travel in the backup.
extension AppModel {
    var goals: [Goal] { library.goals }

    func addGoal(_ goal: Goal) async {
        library.goals.append(goal)
        await persistGoals()
    }

    func removeGoal(_ id: UUID) async {
        library.goals.removeAll { $0.id == id }
        await persistGoals()
    }

    func persistGoals() async {
        do { try await store.save(goals: library.goals) } catch { saveFailure = .goals }
    }

    func goalProgress(_ goal: Goal) -> GoalProgress { Goals.progress(goal, sessions: sessions) }

    /// The goals a finished workout was the first to meet, for the Summary.
    func goalsReached(by session: Session) -> [Goal] {
        library.goals.filter { $0.reachedSessionId == session.id }
    }

    /// Names to offer when setting a goal: history's, newest first, then the plans'.
    var exerciseNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for name in ExerciseText.search("", sessions: sessions) + plans.flatMap({ $0.days.flatMap { $0.exercises.map(\.name) } })
        where seen.insert(normalized(name)).inserted {
            names.append(name)
        }
        return names
    }
}
