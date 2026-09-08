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
                        ForEach(Array(blocks(session).enumerated()), id: \.offset) { _, indices in
                            Section {
                                let mixed = Set(indices.map { session.steps[$0].exerciseIndex }).count > 1
                                ForEach(indices, id: \.self) { index in
                                    Button { tapped(index) } label: {
                                        row(session: session, index: index, nameRows: mixed)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                header(session: session, block: indices)
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
            .confirmationDialog("Recover this set", isPresented: Binding(
                get: { recovering != nil }, set: { if !$0 { recovering = nil } }), titleVisibility: .visible) {
                if let index = recovering {
                    Button("Do this set") { Task { await model.apply(.jumpTo(step: index)) }; dismiss() }
                    Button("Add result") { editing = index }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// D28 (v1.1): ordered by where a block's steps now sit, not by `blockIndex`. "Do later"
    /// moves a block's steps without renumbering it, so sorting by the index would still show
    /// the deferred exercise in its old place.
    private func blocks(_ session: Session) -> [[Int]] {
        Dictionary(grouping: session.steps.indices, by: { session.steps[$0].blockIndex })
            .map { $0.value.sorted() }
            .sorted { ($0.first ?? 0) < ($1.first ?? 0) }
    }

    private func header(session: Session, block indices: [Int]) -> some View {
        let names = indices.compactMap { session.exercises[safe: session.steps[$0].exerciseIndex]?.name }
        var text = Array(NSOrderedSet(array: names)).compactMap { $0 as? String }.joined(separator: " + ")
        if let block = indices.first.map({ session.steps[$0].blockIndex }),
           let seconds = SessionStats.blockDuration(block, session: session) {
            text += " · \(TargetText.time(seconds))"
        }
        return Text(text)
    }

    /// In a superset every row would otherwise read "A · Set 1 of 3", so when a block holds
    /// more than one exercise the rows name it instead of showing the shared group tag.
    private func row(session: Session, index: Int, nameRows: Bool) -> some View {
        let step = session.steps[index]
        let label = StepCard.rowLabel(session: session, step: index, naming: nameRows)
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
            return StepCard.targetLine(session: session, step: index)
        case .skipped:
            return "skipped"
        case .logged:
            guard let result = step.result else { return "" }
            var text = result.reps.map(String.init) ?? result.seconds.map(TargetText.time) ?? ""
            if let weight = result.weight { text += " @ \(TargetText.number(weight))" }
            if let seconds = step.setSeconds { text += " · \(TargetText.time(seconds))" }
            return text
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
