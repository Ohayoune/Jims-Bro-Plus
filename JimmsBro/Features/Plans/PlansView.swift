import SwiftUI

/// SPEC §4.2: the list, the active one marked, **Add plan** as the primary action (D26,
/// v1.1 — the JSON editor is no longer the front door), swipe to delete with a confirmation.
/// D62 (v1.7): no longer a tab. Today's ··· → Change plan pushes it, so it has no stack of its
/// own; its rows push a plan's detail onto Today's.
struct PlansView: View {
    @Environment(AppModel.self) private var model
    @Binding var addPlan: AddPlanRequest?
    @Binding var showWorkout: Bool
    /// D25 (v1.1): swipe-to-delete confirms, matching every other delete path.
    @State private var confirmDeleteId: UUID?

    var body: some View {
        Group {
            if model.plans.isEmpty {
                ContentUnavailableView {
                    Label("No plans yet", systemImage: "list.bullet")
                } description: {
                    Text("Get one from a chatbot in three steps, paste one you already have, or open a file.")
                } actions: {
                    Button("Add plan") { addPlan = .plan }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                List {
                    ForEach(model.plans) { plan in
                        NavigationLink(value: plan.id) { row(plan) }
                    }
                    .onDelete { offsets in
                        confirmDeleteId = offsets.first.map { model.plans[$0].id }
                    }
                }
                .navigationDestination(for: UUID.self) { PlanDetailView(planId: $0, showWorkout: $showWorkout) }
                .bottomAction {
                    PrimaryButton(title: "Add plan") { addPlan = .plan }
                }
            }
        }
        .navigationTitle("Plans")
        // Pushed from Today's inline bar it would inherit an inline title; it is a place, not a
        // detail page, so it keeps the large title it had as a tab (D62).
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(deletePrompt, isPresented: Binding(
            get: { confirmDeleteId != nil }, set: { if !$0 { confirmDeleteId = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteId { Task { await model.deletePlan(id) } }
                confirmDeleteId = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteId = nil }
        }
    }

    private var deletePrompt: String {
        guard let id = confirmDeleteId, let plan = model.plans.first(where: { $0.id == id }) else {
            return "Delete this plan?"
        }
        return "Delete \(plan.name)?"
    }

    private func row(_ plan: Plan) -> some View {
        HStack(spacing: 10) {
            // D59 (v1.6): the plan in use is marked, not described by a grey word.
            if plan.id == model.activePlanId {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("In use")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                Text(subtitle(plan))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(_ plan: Plan) -> String {
        var parts = ["\(plan.days.count) day\(plan.days.count == 1 ? "" : "s")", plan.units.rawValue]
        if plan.id == model.activePlanId { parts.insert("In use", at: 0) }
        return parts.joined(separator: " · ")
    }
}
