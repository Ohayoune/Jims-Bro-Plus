import SwiftUI

/// SPEC §6.67 (D94, v1.11): Plan detail's ··· → **Say what should change**. One field, the trip
/// strip small beneath it, and the bottom slot of the stage the screen is at (§6.60): Send and Copy
/// the prompt, the system's Paste, **Apply 2 changes** under the review of what changed, or the way
/// back from a refusal. Every word and every stage is `ChangeRequest`'s; the view draws them.
struct ChangePlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let planId: UUID

    /// Nil until the plan is read, on appear.
    @State private var screen: ChangeRequest?
    @State private var editingText = false
    @FocusState private var fieldFocused: Bool

    private var plan: Plan? { model.plans.first { $0.id == planId } }

    var body: some View {
        Group {
            if let screen {
                content(screen)
            } else if plan == nil {
                ContentUnavailableView("Plan deleted", systemImage: "trash")
            } else {
                Color.clear
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard screen == nil, let plan else { return }
            screen = ChangeRequest(plan: plan, wording: model.settings.wording)
            fieldFocused = true
        }
    }

    private func content(_ screen: ChangeRequest) -> some View {
        List {
            Section {
                TextField(ChangeRequest.placeholder, text: Binding(
                    get: { self.screen?.request ?? "" },
                    set: { self.screen?.say($0) }), axis: .vertical)
                    .lineLimit(2...6)
                    .focused($fieldFocused)
            }
            Section {
                TripStripView(strip: screen.strip, side: 40)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if let refusal = screen.refusal {
                    RefusalDetails(refusal: refusal)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } else if let sentence = screen.sentence {
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            if let diff = screen.diff, diff.count > 0 {
                review(diff)
                if let reply = screen.reply { WorthKnowing(warnings: reply.warnings) }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(screen.heading)
        .toolbar { menu(screen) }
        .bottomAction(if: screen.buttons != nil) { bottom(screen) }
        .sheet(isPresented: $editingText) {
            JSONFragmentSheet(point: screen.textPoint()) { text in
                let result = model.runImport(text)
                guard result.plan != nil else { return result.errors }
                self.screen?.pasted(result: result)
                return []
            }
        }
    }

    // MARK: - The bottom slot

    @ViewBuilder private func bottom(_ screen: ChangeRequest) -> some View {
        switch screen.stage {
        case .ask, .refused:
            if let buttons = screen.buttons {
                PromptButtons(text: screen.prompt(settings: model.settings), subject: screen.subject,
                              buttons: buttons) {
                    fieldFocused = false
                    self.screen?.sent()
                }
                .disabled(!screen.canSend)
            }
        case .paste:
            TripPasteButton { text in self.screen?.pasted(result: model.runImport(text)) }
        case .review:
            if let buttons = screen.buttons {
                PrimaryButton(title: buttons.primary) { apply(screen) }
            }
        }
    }

    /// D48: the screen closes on the tap; the write follows.
    private func apply(_ screen: ChangeRequest) {
        guard let reply = screen.reply else { return }
        Task { await model.applyChange(planId: planId, plan: reply) }
        dismiss()
    }

    // MARK: - The ···

    @ToolbarContentBuilder private func menu(_ screen: ChangeRequest) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            TripMenu(items: screen.menu) { item in
                switch item {
                case .sendAgain: self.screen?.restart()
                case .editText: editingText = true
                default: break
                }
            }
        }
        .quietBackground()
    }

    // MARK: - The review

    @ViewBuilder private func review(_ diff: PlanDiff) -> some View {
        ForEach(Array(diff.groups.enumerated()), id: \.offset) { _, group in
            if group.lines.count == 1, let line = group.lines.first, case .dayUnchanged = line {
                // An unchanged day is one grey line.
                Section { dayLine(group, row: diff.row(line)).foregroundStyle(.secondary) }
            } else if group.lines.count == 1, let line = group.lines.first, isDayLine(line) {
                Section { dayLine(group, row: diff.row(line)) }
            } else {
                Section {
                    ForEach(Array(group.lines.enumerated()), id: \.offset) { _, line in
                        rowView(diff.row(line))
                    }
                } header: {
                    if let day = group.day {
                        HStack(spacing: 6) {
                            DaySquare(colour: group.dayIndex.map { DayColour.of(dayIndex: $0) })
                            Text(day)
                        }
                        .foregroundStyle(.primary)
                    } else {
                        Text(screen?.plan.name ?? "")
                    }
                }
            }
        }
    }

    private func isDayLine(_ line: PlanDiff.Line) -> Bool {
        switch line {
        case .dayAdded, .dayRemoved: return true
        default: return false
        }
    }

    /// A day as one line: its square, its name, and what happened to it.
    private func dayLine(_ group: PlanDiff.Group, row: PlanDiff.Row) -> some View {
        HStack(spacing: 8) {
            DaySquare(colour: group.dayIndex.map { DayColour.of(dayIndex: $0) })
            if let struck = row.struck {
                Text(struck).strikethrough()
            } else if let name = row.name {
                Text(name)
            }
            Spacer()
            if let detail = row.detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }

    /// The old name struck above the new in ink, and the targets beneath.
    private func rowView(_ row: PlanDiff.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let struck = row.struck {
                Text(struck)
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
            if let name = row.name {
                Text(name).foregroundStyle(.primary)
            }
            if let detail = row.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }
}
