import Foundation

/// SPEC §6.28 (D52, v1.5): the app side of a plan built in several pastes. The draft lives in
/// `draft.json` between launches and goes when the plan is saved or the draft discarded.
/// Everything it decides is decided in Core (`PlanDrafting`).
extension AppModel {
    /// The outline pasted: a draft with one slot per day, or the reasons it was refused.
    @discardableResult
    func startDraft(_ text: String, now: Date = Date()) async -> [Issue] {
        let read = PlanDrafting.outline(text, settings: settings, now: now)
        guard let draft = read.draft else { return read.issues }
        self.draft = draft
        await persistDraft()
        return read.issues
    }

    /// A day pasted into its slot: the draft moves on, or the errors say which slot and why.
    @discardableResult
    func pasteDraftDay(_ text: String, into index: Int, now: Date = Date()) async -> [Issue] {
        guard let draft else {
            return [Issue(severity: .error, code: "E_EDIT_INVALID", path: "", message: "There is no draft to add a day to.")]
        }
        let read = PlanDrafting.day(text, into: draft, index: index, settings: settings, now: now)
        guard let updated = read.draft else { return read.issues }
        self.draft = updated
        await persistDraft()
        return read.issues
    }

    /// The whole plan, once every slot is filled — not yet saved, so the review can show it.
    func assembleDraft(now: Date = Date()) -> ImportResult {
        guard let draft else {
            return ImportResult(plan: nil, issues: [Issue(severity: .error, code: "E_EDIT_INVALID", path: "",
                                                           message: "There is no draft to assemble.")])
        }
        return PlanDrafting.assemble(draft, settings: settings, now: now)
    }

    /// Saves the assembled plan like any other and lets the draft go. Nil when a name conflict
    /// was cancelled, in which case the draft stays.
    @discardableResult
    func saveDraftPlan(_ plan: Plan, conflict: ConflictChoice = .cancel, makeActive: Bool) async -> UUID? {
        guard let id = await save(plan, conflict: conflict, makeActive: makeActive) else { return nil }
        draft = nil
        await persistDraft()
        return id
    }

    func discardDraft() async {
        draft = nil
        await persistDraft()
    }

    /// Writes the draft, or removes the file when there is none (D24 on failure).
    func persistDraft() async {
        do {
            if let draft { try await store.save(draft: draft) } else { try await store.clearDraft() }
        } catch {
            saveFailure = .draft
        }
    }
}
