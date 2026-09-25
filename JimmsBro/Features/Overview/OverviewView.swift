import SwiftUI

/// SPEC §4.8: every step grouped by exercise. Tap a logged step to edit it, a pending one to
/// jump to it (which cancels any rest and clears a block-done banner), and — D27 (v1.1) — a
/// skipped one to recover it: **Do this set** (jump to it) or **Add result** (edit in place).
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Int?
    /// D27 (v1.1): a skipped row offers a choice instead of jumping straight in.
    @State private var recovering: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let session = model.session {
                    List {
                        ForEach(Array(SessionBlocks.blocks(session).enumerated()), id: \.offset) { _, block in
                            Section {
                                ForEach(block.steps, id: \.self) { index in
                                    Button { tapped(index) } label: {
                                        row(session: session, index: index, nameRows: block.namesRows)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text(block.title)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No workout running", systemImage: "figure.strengthtraining.traditional")
                }
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
            .sheet(item: Binding(
                get: { model.session.flatMap { s in editing.map { EditTarget(session: s, step: $0) } } },
                set: { editing = $0?.step })) { target in
                // Editing a logged value never changes the phase or starts a timer (SPEC §6.6).
                EditResultSheet(target: target) { result in
                    Task { await model.apply(.editSet(step: target.step, result: result)) }
                }
            }
            .confirmationDialog("Recover this set", isPresented: Binding(isPresent: $recovering), titleVisibility: .visible) {
                if let index = recovering {
                    Button("Do this set") { Task { await model.apply(.jumpTo(step: index)) }; dismiss() }
                    Button("Add result") { editing = index }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// In a superset every row would otherwise read "A · Set 1 of 3", so when a block holds
    /// more than one exercise the rows name it instead of showing the shared group tag.
    private func row(session: Session, index: Int, nameRows: Bool) -> some View {
        let step = session.steps[index]
        let label = StepCard.rowLabel(session: session, step: index, naming: nameRows,
                                      wording: model.settings.wording)
        return HStack {
            Image(systemName: icon(step.status))
                .foregroundStyle(step.status == .logged ? Color.done : .secondary)
                .frame(width: 20)
            Text(label)
                .font(.footnote)
                // A named superset drop row is long; wrapping keeps "drop 1 of 2" readable.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(value(session: session, index: index))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func icon(_ status: StepStatus) -> String {
        switch status {
        case .logged: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .pending: return "circle"
        }
    }

    /// "10 @ 60 · 0:34" for a logged step (O43), the target for a pending one.
    private func value(session: Session, index: Int) -> String {
        let step = session.steps[index]
        switch step.status {
        case .pending:
            // D55 (v1.6): the set's own target. The note belongs to the exercise, said once on
            // the card; printed here it repeated forty words on every row.
            return StepCard.targetLine(session: session, step: index, notes: false,
                                       wording: model.settings.wording)
        case .skipped, .logged:
            // The same sentence Session detail prints, so the two screens cannot drift apart.
            return ExerciseText.result(step, wording: model.settings.wording)
        }
    }

    private func tapped(_ index: Int) {
        guard let session = model.session else { return }
        switch session.steps[index].status {
        case .pending: Task { await model.apply(.jumpTo(step: index)); dismiss() }
        case .skipped: recovering = index
        case .logged: editing = index
        }
    }
}
