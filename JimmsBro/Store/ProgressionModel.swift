import Foundation

/// SPEC §6.21 (D44, v1.3): the app side of Progression — the reply in, and the progression
/// attached to its plan; the prompt out is `ProgressionScreen.prompt`'s. Everything it decides
/// is decided in Core.
extension AppModel {
    /// The reply, read against this plan, in the mode chosen on the screen (D53). Nothing is
    /// saved until `setProgression`.
    func runProgressionImport(_ text: String, planId: UUID, now: Date = Date(),
                              mode: ProgressionMode = ProgressionScreen.defaultMode) -> ProgressionImport.Result {
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
