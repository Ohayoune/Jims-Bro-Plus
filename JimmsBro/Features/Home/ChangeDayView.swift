import SwiftUI

/// SPEC §6.50 (D76, v1.9): **Change *day*'s exercises**, pushed from Today's ··· for the date the
/// card shows and for that date alone. Core lists the choices (`DayChoices`): this plan's days
/// under its name, every other plan's under theirs — outlined, as the strip will draw them — and
/// last a day written just for the date. A tap writes the date's swap and goes back to Today,
/// whose card already shows it; the last row opens the JSON sheet, whose Save says where the
/// text lands.
struct ChangeDayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var writing = false
    /// The sheet's Save made the text the date's day: back to Today once the sheet is down.
    @State private var used = false

    var body: some View {
        if let choices = model.dayChoices(for: date) {
            list(choices)
        } else {
            // The plan went while the picker was open; there is nothing to change.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func list(_ choices: DayChoices) -> some View {
        List {
            Text(choices.line)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            ForEach(Array(choices.sections.enumerated()), id: \.offset) { _, section in
                Section(section.title) {
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        Button { choose(row.slot) } label: {
                            label(row.name, colour: row.colour, outlined: row.outlined, chosen: row.isChosen)
                        }
                    }
                }
            }
            Section {
                Button { writing = true } label: {
                    label(choices.ownTitle, colour: nil, outlined: true, chosen: choices.own != nil)
                }
            }
        }
        .navigationTitle(choices.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $writing, onDismiss: { if used { dismiss() } }) {
            JSONFragmentSheet(title: choices.ownTitle,
                              initialText: choices.own.map(PlanJSON.render(day:))
                                  ?? FragmentTarget.dayTemplate(name: ""),
                              footer: choices.ownFooter, saveTitle: choices.saveTitle) { text in
                let refused = await model.useOwnDay(text, for: date)
                if refused.isEmpty { used = true }
                return refused
            }
        }
    }

    /// A square and a name, as the strip will draw the day, and a check on what the date is now.
    private func label(_ name: String, colour: DayColour?, outlined: Bool, chosen: Bool) -> some View {
        HStack(spacing: 12) {
            DaySquare(colour: colour, size: 14, outlined: outlined)
            Text(name)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if chosen {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// D48: the choice lands before the write behind it — back to Today at once, where the card
    /// already shows it.
    private func choose(_ slot: DaySwap.Slot) {
        Task { await model.chooseDay(slot, for: date) }
        dismiss()
    }
}
