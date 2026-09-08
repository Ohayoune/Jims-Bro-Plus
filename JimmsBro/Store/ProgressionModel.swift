import Foundation

/// SPEC §6.21 (D44, v1.3): the app side of Progression — the prompt out, the reply in, and
/// the progression attached to its plan. Everything it decides is decided in Core.
extension AppModel {
    /// Whether any completed session includes an exercise of this plan — what "Use my history"
    /// is offered on.
    func hasHistory(for planId: UUID) -> Bool {
        guard let plan = plans.first(where: { $0.id == planId }) else { return false }
        let names = Set(plan.days.flatMap { $0.exercises.map { normalized($0.name) } })
        return sessions.contains { session in
            session.endedAt != nil && session.exercises.contains { names.contains(normalized($0.name)) }
        }
    }

    /// The prompt for this plan over `weeks`, with history when asked and there is any.
    func progressionPrompt(for planId: UUID, weeks: Int, includeHistory: Bool, now: Date = Date()) -> String? {
        guard let plan = plans.first(where: { $0.id == planId }) else { return nil }
        return Prompts.progression(plan: plan, history: sessions, weeks: weeks, includeHistory: includeHistory,
                                   settings: settings, now: now)
    }

    /// The reply, read against this plan. Nothing is saved until `setProgression`.
    func runProgressionImport(_ text: String, planId: UUID, now: Date = Date()) -> ProgressionImport.Result {
        guard let plan = plans.first(where: { $0.id == planId }) else {
            return ProgressionImport.Result(progression: nil, issues: [Issue(
                severity: .error, code: "E_EDIT_INVALID", path: "", message: "That plan no longer exists.")])
        }
        return ProgressionImport.run(text, plan: plan, settings: settings, now: now)
    }

    /// Attaches (or, with nil, removes) the plan's progression and writes the plans file.
    func setProgression(_ progression: Progression?, for planId: UUID) async {
        guard let index = library.plans.firstIndex(where: { $0.id == planId }) else { return }
        library.plans[index].progression = progression
        await persistPlans()
    }
}
