import SwiftUI

/// D46 (v1.4): the four routines the app ships, offered next to writing your own. One screen:
/// a row per routine, the sentence about building your own beneath them, and the ordinary
/// **Review plan** sheet — the same one a pasted plan gets — with the routine's paragraph on top.
struct BuiltInPlansView: View {
    @Environment(AppModel.self) private var model
    /// Runs once a plan is saved, so the sheet this was pushed in can close.
    let saved: () -> Void

    @State private var reviewing: Review?
    @State private var pending: Plan?
    @State private var makeActive = true
    @State private var minutes: [String: Int] = [:]
    @State private var problem: String?

    private struct Review: Identifiable {
        let entry: BuiltInPlan
        let plan: Plan
        var id: String { entry.id }
    }

    var body: some View {
        List {
            Section {
                ForEach(BuiltInPlans.all) { entry in
                    Button { open(entry) } label: { row(entry) }
                        .buttonStyle(PressableRow())
                }
            } header: {
                Text("Four ways most people train")
            } footer: {
                Text(BuiltInPlans.buildYourOwn)
            }
        }
        .navigationTitle("Built-in plans")
        .navigationBarTitleDisplayMode(.inline)
        .task { estimate() }
        .sheet(item: $reviewing, onDismiss: resolvePending) { review in
            PlanReviewSheet(plan: review.plan, about: review.entry.about, makeActive: $makeActive) {
                pending = review.plan
                reviewing = nil
            }
        }
        .alert("That plan couldn't be opened", isPresented: Binding(
            get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    private func row(_ entry: BuiltInPlan) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.name).foregroundStyle(.primary)
            Text(entry.tagline)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(BuiltInPlans.summary(entry, minutes: minutes[entry.id]))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.forWhom)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The minutes on each row come from the plan itself, with the user's own warm-up and walk.
    private func estimate() {
        for entry in BuiltInPlans.all {
            guard let plan = model.loadBuiltInPlan(entry.id).plan else { continue }
            minutes[entry.id] = BuiltInPlans.estimatedMinutes(plan, settings: model.settings)
        }
    }

    private func open(_ entry: BuiltInPlan) {
        let result = model.loadBuiltInPlan(entry.id)
        guard let plan = result.plan else {
            problem = result.errors.first.map(IssueText.friendly) ?? "The plan is missing from the app."
            return
        }
        reviewing = Review(entry: entry, plan: plan)
    }

    /// Runs once the review sheet is fully dismissed, like Add plan's own resolve.
    private func resolvePending() {
        guard let plan = pending else { return }
        pending = nil
        Task {
            // A built-in plan saved twice is kept both, suffixed, like any plan (§6.8).
            await model.save(plan, conflict: .keepBoth, makeActive: makeActive)
            saved()
        }
    }
}
