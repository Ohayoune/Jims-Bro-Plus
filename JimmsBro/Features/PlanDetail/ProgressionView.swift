import SwiftUI

/// SPEC §4.3 / §6.21 (D44, v1.3): **Progression**, the chatbot round-trip run the other way.
/// With a progression: what it says and where you are in it, **Plan the next one**, and Remove.
/// Without one, or planning the next (D92, v1.11, §6.65): one screen in the trip's states
/// (§6.60) — the steps and the mode as pre-marked tiles, the strip small beneath them, one
/// control in the bottom slot — and the reply reviewed as ladders before **Start step 1**. The
/// stage, the tiles and every word are `ProgressionScreen`'s; this view draws them.
struct ProgressionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let planId: UUID

    @State private var planning = false
    @State private var screen = ProgressionScreen()
    /// The last text read — pasted, or saved from the text sheet — which Edit the text opens on.
    @State private var lastText = ""
    @State private var editingText = false
    /// A reply the text sheet read cleanly, applied once the sheet has closed, so the review
    /// never opens under a sheet that is still going.
    @State private var pendingRead: ProgressionImport.Result?
    @State private var confirmRemove = false

    private var plan: Plan? { model.plans.first { $0.id == planId } }

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    if let current = plan.progression, !planning {
                        currentSections(plan, current)
                    } else {
                        planningScreen(plan)
                    }
                } else {
                    ContentUnavailableView("Plan deleted", systemImage: "trash")
                }
            }
            .navigationTitle("Progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                if let plan {
                    // The ··· (D95, §6.68): its items Core's, Edit the text last.
                    ToolbarItem(placement: .topBarTrailing) {
                        TripMenu(items: screen.menu(hasProgression: plan.progression != nil, planning: planning),
                                 choose: choose)
                    }
                    .quietBackground()
                }
            }
            // D56 (v1.6): an alert — from a menu, a dialog's Cancel is not drawn on iOS 26.
            .alert("Remove this progression?", isPresented: $confirmRemove) {
                Button("Remove", role: .destructive) {
                    Task { await model.setProgression(nil, for: planId); planning = false }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The plan goes back to its own targets. Nothing you logged changes.")
            }
            .sheet(isPresented: reviewing) {
                if let plan, let progression = screen.progression {
                    ProgressionReviewSheet(progression: progression, plan: plan, warnings: screen.warnings,
                                           startTitle: screen.startTitle) { start() }
                }
            }
            .sheet(isPresented: $editingText, onDismiss: {
                guard let result = pendingRead else { return }
                pendingRead = nil
                screen.read(result)
            }) {
                if let plan {
                    JSONFragmentSheet(point: JSONPoint.progression(plan, steps: screen.steps, text: lastText)) { text in
                        lastText = text
                        let result = model.runProgressionImport(text, planId: planId, mode: screen.mode)
                        guard result.errors.isEmpty, result.progression != nil else { return result.errors }
                        pendingRead = result
                        return []
                    }
                }
            }
        }
    }

    /// The review is up while the screen is on Review; closing it without starting is Cancel.
    private var reviewing: Binding<Bool> {
        Binding(get: { screen.stage == .review && !screen.started && !editingText },
                set: { if !$0 { screen.cancelReview() } })
    }

    private func choose(_ item: TripMenuItem) {
        switch item {
        // D88 (§6.61): the way back to Ask, where Send the prompt and Copy the prompt are one tap
        // each — never a share sheet opened from inside a menu, which would close under the thumb.
        case .sendAgain: screen.restart()
        case .keepCurrent:
            planning = false
            screen = ProgressionScreen()
        case .removeProgression: confirmRemove = true
        case .editText: editingText = true
        case .openFile, .keepWithoutUsing, .discardDraft: break
        }
    }

    // MARK: - With one

    private func currentSections(_ plan: Plan, _ current: Progression) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ProgressionText.status(current, on: Date()))
                        .font(.title3.weight(.semibold))
                    // D53: a calendar progression ends on a date; one you earn ends when every
                    // exercise is past its last step.
                    Text(current.mode == .performance
                         ? "Started \(current.startDate.formatted(date: .abbreviated, time: .omitted)) · "
                           + "\(current.entries.filter { $0.step >= $0.weeks.count }.count) of \(current.entries.count) exercises done"
                         : "Started \(current.startDate.formatted(date: .abbreviated, time: .omitted)) · "
                           + "ends \(current.endDate().formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            ForEach(plan.days) { day in
                let entries = day.exercises.compactMap { exercise -> (Exercise, ProgressionEntry)? in
                    current.entry(day: day.name, exercise: exercise.name).map { (exercise, $0) }
                }
                if !entries.isEmpty {
                    Section(day.name) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, pair in
                            entryRow(pair.0, pair.1, current: current, units: plan.units)
                        }
                    }
                }
            }
        }
        .bottomAction {
            PrimaryButton(title: "Plan the next one") { planning = true }
        }
    }

    private func entryRow(_ exercise: Exercise, _ entry: ProgressionEntry, current: Progression,
                          units: WeightUnit) -> some View {
        let step = current.stepIndex(for: entry, on: Date())
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                Spacer()
                // D53: where this exercise is on its ladder, and how many tries the step took.
                if current.mode == .performance {
                    Text(ProgressionText.entryStatus(entry, of: current.weeks))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let step, let change = entry.weeks[safe: step] {
                Text((current.mode == .performance ? "This step: " : "This week: ")
                     + ProgressionText.change(change, units: units, bodyweight: exercise.bodyweight))
                    .font(.footnote)
            }
            Text(current.mode == .performance
                 ? ProgressionText.ladder(entry, units: units, bodyweight: exercise.bodyweight, current: step)
                 : ProgressionText.weeksLine(entry, units: units, bodyweight: exercise.bodyweight))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Planning one

    private func planningScreen(_ plan: Plan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TileRow(label: "Steps", tiles: screen.stepTiles, enabled: screen.editable) { index in
                    screen.mark(steps: Progression.periods[index])
                }
                TileRow(label: "Next step", tiles: screen.modeTiles, enabled: screen.editable) { index in
                    screen.mark(mode: ProgressionScreen.modes[index])
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .bottomAction { bottomSlot(plan) }
    }

    /// The strip small above the one control, and on Refused the sentence between them.
    private func bottomSlot(_ plan: Plan) -> some View {
        VStack(spacing: 14) {
            TripStripView(strip: screen.strip, side: 30)
                .frame(maxWidth: 200)
            if let refusal = screen.refusal { RefusalDetails(refusal: refusal) }
            switch screen.stage {
            case .ask, .refused:
                PromptButtons(text: screen.prompt(plan: plan, history: model.sessions, settings: model.settings),
                              subject: ProgressionScreen.subject(plan), buttons: screen.buttons) {
                    screen.sent()
                }
            case .paste, .review:
                TripPasteButton { text in
                    lastText = text
                    screen.read(model.runProgressionImport(text, planId: planId, mode: screen.mode))
                }
            }
        }
    }

    /// **Start step 1** (D48): the progression is the plan's before the file is written.
    private func start() {
        guard let progression = screen.start() else { return }
        Task {
            await model.setProgression(progression, for: planId)
            planning = false
            screen = ProgressionScreen()
            lastText = ""
        }
    }
}

/// D92: a row of joined tiles, one marked. A tap marks; nothing is sent until Send (D85's rule).
/// The marked tile takes an ink ring and a check, as Change *day*'s does.
private struct TileRow: View {
    let label: String
    let tiles: [ProgressionScreen.Tile]
    let enabled: Bool
    let mark: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(tiles.indices, id: \.self) { index in
                    let tile = tiles[index]
                    let ends = CycleGlyph.ends(index, count: tiles.count, of: tiles.count)
                    let shape = UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: ends.first ? 12 : 0, bottomLeading: ends.first ? 12 : 0,
                                           bottomTrailing: ends.last ? 12 : 0, topTrailing: ends.last ? 12 : 0),
                        style: .continuous)
                    Button { mark(index) } label: {
                        HStack(spacing: 4) {
                            if tile.marked { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                            Text(tile.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .font(.body.weight(tile.marked ? .semibold : .regular))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(.secondarySystemFill), in: shape)
                        .overlay { if tile.marked { shape.strokeBorder(Color.primary, lineWidth: 2.5) } }
                        .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tile.marked ? .isSelected : [])
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
        }
    }
}

/// D92 (v1.11, §6.65): what the chatbot planned, before it starts — D26's review, for a
/// progression, as ladders. The header says the steps and the mode once; material warnings are
/// shown above the days; tidying goes behind Details. Each day carries its square (D65), each
/// exercise its ladder and step 1's numbers, and the one button names its effect.
struct ProgressionReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let progression: Progression
    let plan: Plan
    let warnings: [Issue]
    var startTitle = ProgressionScreen.startTitle(.performance)
    let start: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(ProgressionScreen.header(progression))
                        .font(.headline)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
                WorthKnowing(warnings: warnings)
                ForEach(Array(ProgressionLadder.of(progression, plan).enumerated()), id: \.offset) { _, day in
                    Section {
                        ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ladder in
                            LadderRow(ladder: ladder)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            DaySquare(colour: day.colour, relativeTo: .footnote)
                            Text(day.dayName)
                        }
                    }
                }
                Tidying(warnings: warnings)
            }
            .navigationTitle("Review progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .bottomAction {
                PrimaryButton(title: startTitle, systemImage: "play.fill") { start() }
            }
        }
    }
}

/// One exercise of the review: the name and step 1's numbers, and its ladder — a bar a step,
/// step 1 in the accent and the rest grey, each as tall as the ladder says.
private struct LadderRow: View {
    let ladder: ProgressionLadder
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 7

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ladder.exerciseName)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ladder.first)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(ladder.bars.enumerated()), id: \.offset) { index, bar in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == ladder.lit ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: width, height: max(3, height * bar))
                }
            }
            .frame(height: height, alignment: .bottom)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ladder.exerciseName), step 1 \(ladder.first), \(ladder.bars.count) steps")
    }
}
