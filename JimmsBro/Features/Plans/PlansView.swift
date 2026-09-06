import SwiftUI

/// SPEC §4.2: the list, the active one marked, **Add plan** as the primary action (D26,
/// v1.1 — the JSON editor is no longer the front door), swipe to delete with a confirmation.
struct PlansView: View {
    @Environment(AppModel.self) private var model
    @Binding var showImport: Bool
    @Binding var showWorkout: Bool
    @State private var path: [UUID] = []
    /// D25 (v1.1): swipe-to-delete confirms, matching every other delete path.
    @State private var confirmDeleteId: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.plans.isEmpty {
                    ContentUnavailableView {
                        Label("No plans yet", systemImage: "list.bullet")
                    } description: {
                        Text("Get one from a chatbot in three steps, paste one you already have, or open a file.")
                    } actions: {
                        Button("Add plan") { showImport = true }
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
                        PrimaryButton(title: "Add plan") { showImport = true }
                    }
                }
            }
            .navigationTitle("Plans")
            .confirmationDialog(deletePrompt, isPresented: Binding(
                get: { confirmDeleteId != nil }, set: { if !$0 { confirmDeleteId = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = confirmDeleteId { Task { await model.deletePlan(id) } }
                    confirmDeleteId = nil
                }
                Button("Cancel", role: .cancel) { confirmDeleteId = nil }
            }
            .task {
                #if DEBUG
                // Debug-only: open the first plan directly for screenshot runs. The store
                // loads asynchronously, so wait for it rather than reading an empty list.
                guard ProcessInfo.processInfo.arguments.contains("-uiPlanDetail") else { return }
                while !model.loaded { try? await Task.sleep(for: .milliseconds(50)) }
                if path.isEmpty, let first = model.plans.first { path = [first.id] }
                #endif
            }
        }
    }

    private var deletePrompt: String {
        guard let id = confirmDeleteId, let plan = model.plans.first(where: { $0.id == id }) else {
            return "Delete this plan?"
        }
        return "Delete \(plan.name)?"
    }

    private func row(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plan.name)
            Text(subtitle(plan))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ plan: Plan) -> String {
        var parts = ["\(plan.days.count) day\(plan.days.count == 1 ? "" : "s")", plan.units.rawValue]
        if plan.id == model.activePlanId { parts.insert("Active", at: 0) }
        return parts.joined(separator: " · ")
    }
}
