import Foundation

/// SPEC §6.21 (D44, v1.3): the app side of Progression — the prompt out, the reply in, and
/// the progression attached to its plan. Everything it decides is decided in Core.
extension AppModel {
    /// The prompt for this plan over `weeks`, with its history whenever there is any (v1.11, J5).
    func progressionPrompt(for planId: UUID, weeks: Int, now: Date = Date(),
                           mode: ProgressionMode = .performance) -> String? {
        guard let plan = plans.first(where: { $0.id == planId }) else { return nil }
        return Prompts.progression(plan: plan, history: sessions, weeks: weeks,
                                   settings: settings, now: now, mode: mode)
    }

    /// The reply, read against this plan, in the mode chosen on the screen (D53). Nothing is
    /// saved until `setProgression`.
    func runProgressionImport(_ text: String, planId: UUID, now: Date = Date(),
                              mode: ProgressionMode = .performance) -> ProgressionImport.Result {
        guard let plan = plans.first(where: { $0.id == planId }) else {
            return ProgressionImport.Result(progression: nil, issues: [Issue(
                severity: .error, code: "E_EDIT_INVALID", path: "", message: "That plan no longer exists.")])
        }
        return ProgressionImport.run(text, plan: plan, settings: settings, now: now, mode: mode)
    }

    /// Attaches (or, with nil, removes) the plan's progression and writes the plans file.
    func setProgression(_ progression: Progression?, for planId: UUID) async {
        guard let index = library.plans.firstIndex(where: { $0.id == planId }) else { return }
        library.plans[index].progression = progression
        await persistPlans()
    }
}
