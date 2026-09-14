import SwiftUI

/// SPEC §4.2 (D78, v1.9, §6.51): the list speaks in squares. A row is a chevron at its left, the
/// plan's cycle as the ···'s symbol, its name with how often beneath, and a circle at its right.
/// **The circle marks; the button confirms** (the owner's 15): a marked plan that is not the
/// active one puts **Use Upper Lower** in the bottom slot, and that button is the one way to
/// change plan — it makes the plan active and goes back to Today, which now runs it. The mark is
/// this screen's and never stored, so leaving without confirming changes nothing. The rest of
/// the row opens the plan's page. **Add plan** (D26) is at the top right, as the mock drew it,
/// since the bottom slot is the confirmation's; swipe to delete confirms (D25, v1.1).
/// D62 (v1.7): no longer a tab. Today's ··· → Change plan pushes it onto Today's stack, and a
/// row pushes the plan's page onto the same one.
struct PlansView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Today's stack: a row pushes the plan's page onto it, and Use empties it.
    @Binding var path: NavigationPath
    @Binding var addPlan: AddPlanRequest?
    @Binding var showWorkout: Bool
    /// D25 (v1.1): swipe-to-delete confirms, matching every other delete path.
    @State private var confirmDeleteId: UUID?
    /// The circle tapped; nil is the active plan's own.
    @State private var marked: UUID?

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
                    ForEach(model.plans) { plan in row(plan) }
                        .onDelete { offsets in
                            confirmDeleteId = offsets.first.map { model.plans[$0].id }
                        }
                }
                .navigationDestination(for: UUID.self) { PlanDetailView(planId: $0, showWorkout: $showWorkout) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add plan") { addPlan = .plan }
                    }
                }
                .bottomAction(if: pending != nil) {
                    if let pending {
                        PrimaryButton(title: PlanText.useTitle(pending)) { use(pending) }
                    }
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

    /// The plan the bottom button would use; nil while the active plan's own circle is marked.
    private var pending: Plan? {
        PlanText.toUse(marked: marked, activePlanId: model.activePlanId, plans: model.plans)
    }

    /// D48 (v1.4): back to Today at once; its card runs the plan as soon as the model has it.
    private func use(_ plan: Plan) {
        Task { await model.setActivePlan(plan.id) }
        path = NavigationPath()
    }

    private func row(_ plan: Plan) -> some View {
        let isMarked = plan.id == (marked ?? model.activePlanId)
        return HStack(spacing: 4) {
            Button { path.append(plan.id) } label: { label(plan) }
                .buttonStyle(PressableRow())
            // Its own target, so a tap on it marks and never opens the page.
            Button { marked = plan.id } label: {
                Image(systemName: isMarked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isMarked ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Choose \(plan.name)")
            .accessibilityAddTraits(isMarked ? .isSelected : [])
        }
    }

    /// The row but its circle: the accent chevron every row that opens a screen carries, at its
    /// left (the owner's 14), then the cycle beside the name — above it at the accessibility
    /// sizes, where a fourteen-square symbol would leave the name no room.
    private func label(_ plan: Plan) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
        return HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            layout {
                CycleSymbol(cycle: DayColour.cycle(of: plan))
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let often = PlanText.howOften(plan) {
                        Text(often)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the plan")
    }
}
