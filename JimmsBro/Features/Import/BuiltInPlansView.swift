import SwiftUI

/// SPEC §6.63 (D90, v1.11): **the built-in plans as a row of squares**, under a hairline on Add
/// plan's Ask and Paste states. Four tiles in D46's order, each drawn by its own cycle as a tiny
/// joined strip (D86) with its name beneath; a tap hands the plan, read through the ordinary
/// import pipeline, to Add plan's review. *(v1.4–v1.10: a pushed picker of four rows.)*
struct BuiltInPlansView: View {
    @Environment(AppModel.self) private var model
    /// A tile was tapped: the plan as the pipeline read it, and its entry for the paragraph.
    let open: (BuiltInPlan, Plan) -> Void

    @State private var cycles: [String: [DayColour?]] = [:]
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 14) {
            Divider()
            HStack(alignment: .top, spacing: 8) {
                ForEach(BuiltInPlans.all) { entry in
                    Button { tapped(entry) } label: { tile(entry) }
                        .buttonStyle(PressableRow())
                        .accessibilityLabel(entry.name)
                        .accessibilityHint(entry.tagline)
                }
            }
        }
        .task { readCycles() }
        .alert("That plan couldn't be opened", isPresented: Binding(
            get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    private func tile(_ entry: BuiltInPlan) -> some View {
        let cycle = cycles[entry.id] ?? []
        // D57 (v1.6): one recommendation, for the stranger who has no history yet — the tile
        // ringed in the accent, and the words beneath its name.
        let recommended = entry.id == BuiltInPlans.recommendedId && model.sessions.isEmpty
        return VStack(spacing: 8) {
            CycleStrip(count: cycle.count, side: 9, spacing: 1, lineSpacing: 1) { index in
                StripSquare(colour: cycle[index], index: index, count: cycle.count)
            }
            .frame(minHeight: 9)
            Text(entry.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if recommended {
                Text("Start here")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .top)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if recommended {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Each tile's cycle, from the plan itself: the bundled text through the ordinary pipeline.
    private func readCycles() {
        for entry in BuiltInPlans.all where cycles[entry.id] == nil {
            guard let plan = model.loadBuiltInPlan(entry.id).plan else { continue }
            cycles[entry.id] = DayColour.cycle(of: plan)
        }
    }

    private func tapped(_ entry: BuiltInPlan) {
        let result = model.loadBuiltInPlan(entry.id)
        guard let plan = result.plan else {
            problem = result.errors.first.map(IssueText.friendly) ?? "The plan is missing from the app."
            return
        }
        open(entry, plan)
    }
}
