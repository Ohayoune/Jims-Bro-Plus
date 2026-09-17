import SwiftUI

/// SPEC §6.50 (D76, v1.9) and §6.58 (D85, v1.10): **Change *day***, pushed from Today's ··· for
/// the date the card shows and for that date alone. Core lists the choices (`DayChoices`): this
/// plan's days as one joined strip under its name, every other plan's as a strip of outlined
/// tiles under theirs, one dashed tile, **Custom**, and the date's exercises as they stand. No
/// section headers and no grouped list: the strips are the sections (D86's `CycleStrip` at tile
/// size). A tap marks a tile; the button at the bottom says what it will do
/// (`ChangeDayText.confirm`) and is the only thing that writes. Custom opens the JSON sheet,
/// whose Save says where the text lands; since D93 (v1.11, §6.66) the exercises card opens the
/// day's editor (`DayEditorView`), where that sheet is the ···'s Edit the text.
struct ChangeDayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let date: Date
    /// The tile tapped — the screen's, never stored: leave without confirming and nothing has
    /// changed.
    @State private var marked: DayChoices.Mark?
    /// Custom's JSON sheet, open.
    @State private var writing: JSONPoint?
    /// D93: the day's editor, pushed on the date's exercises as they were when the card was tapped.
    @State private var editor: DayChoices.Exercises?
    /// The sheet's Save made the text the date's day: back to Today once the sheet is down.
    @State private var used = false

    /// D85: the picker's tiles are 58 pt, less when seven would not fit the width.
    private static let tile: CGFloat = 58

    var body: some View {
        if let choices = model.dayChoices(for: date) {
            page(choices)
        } else {
            // The plan went while the picker was open; there is nothing to change.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func page(_ choices: DayChoices) -> some View {
        let confirm = ChangeDayText.confirm(choices, marked: marked)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(choices.line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(choices.strips.enumerated()), id: \.offset) { _, strip in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(strip.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        CycleStrip(count: strip.tiles.count, side: Self.tile, spacing: 2, lineSpacing: 10) { index in
                            let tile = strip.tiles[index]
                            tileButton(tile.face, chosen: tile.isChosen, when: choices.when,
                                       isMarked: marked == .day(tile.slot), index: index, count: strip.tiles.count) {
                                toggle(.day(tile.slot))
                            }
                        }
                    }
                }
                CycleStrip(count: 1, side: Self.tile) { _ in
                    tileButton(DayChoices.Face(name: DayChoices.customTitle, colour: nil, outlined: false),
                               dashed: true, chosen: choices.own != nil, when: choices.when,
                               isMarked: marked == .custom, index: 0, count: 1) {
                        toggle(.custom)
                    }
                }
                if let exercises = choices.exercises {
                    exercisesCard(exercises)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(choices.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    DaySquare(colour: choices.day.colour, size: 12, outlined: choices.day.outlined)
                    Text(choices.title).font(.headline)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .bottomAction {
            confirmButton(confirm, choices: choices)
        }
        .navigationDestination(isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })) {
            if let editor {
                // The day written or removed: back to Today past the picker, in one pop.
                DayEditorView(date: date, exercises: editor) { dismiss() }
            }
        }
        #if DEBUG
        .task {
            // Debug-only: `-uiScreen changeDay -uiMark Pull` shows a marked tile and its button;
            // `-uiEditor` opens the day's editor.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uiEditor"), editor == nil { editor = choices.exercises }
            guard let index = arguments.firstIndex(of: "-uiMark"), let name = arguments[safe: index + 1] else { return }
            marked = name == DayChoices.customTitle
                ? .custom : choices.strips.flatMap(\.tiles).first { $0.name == name }.map { .day($0.slot) }
        }
        #endif
        .sheet(isPresented: Binding(get: { writing != nil }, set: { if !$0 { writing = nil } }),
               onDismiss: { if used { dismiss() } }) {
            if let point = writing {
                JSONFragmentSheet(point: point) { text in
                    let refused = await model.useOwnDay(text, for: date)
                    if refused.isEmpty { used = true }
                    return refused
                }
            }
        }
    }

    /// A tile and its name beneath; the tile the date is now says *when* under its name, and a
    /// marked tile takes an ink ring and a check.
    private func tileButton(_ face: DayChoices.Face, dashed: Bool = false, chosen: Bool, when: String,
                            isMarked: Bool, index: Int, count: Int,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                StripSquare(colour: face.colour, outlined: face.outlined, dashed: dashed, ringed: isMarked,
                            index: index, count: count)
                    .overlay {
                        if isMarked {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color(.systemBackground), Color.primary)
                                .font(.title3.weight(.semibold))
                        }
                    }
                // Two lines, centred, so names under touching tiles never run into one another.
                Text(face.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if chosen {
                    Text(when)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.name)
        .accessibilityValue(chosen ? when : "")
        .accessibilityAddTraits(isMarked ? [.isButton, .isSelected] : .isButton)
    }

    /// D85: the date's exercises as they stand — its square and name, each exercise with its
    /// sets as blocks, and a chevron — opening the day's editor (D93).
    private func exercisesCard(_ exercises: DayChoices.Exercises) -> some View {
        Button { editor = exercises } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DaySquare(colour: exercises.face.colour, size: 14, outlined: exercises.face.outlined)
                    Text(exercises.face.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                ForEach(Array(exercises.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        Text(row.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        SetBlocks(sets: row.sets, logged: 0, colour: exercises.face.colour)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercises.face.name): " + exercises.rows.map(\.name).joined(separator: ", "))
        .accessibilityHint(exercises.title)
    }

    /// The one button: disabled *Change Push* until a tile is marked, then *Push → Pull* with
    /// both squares, or *Write a day for Wednesday*.
    private func confirmButton(_ confirm: ChangeDayText.Confirm, choices: DayChoices) -> some View {
        Button {
            if confirm.opensSheet {
                writing = choices.point
            } else if let slot = confirm.slot {
                // D48: the choice lands before the write behind it — back to Today at once,
                // where the card already shows it.
                Task { await model.chooseDay(slot, for: date) }
                dismiss()
            }
        } label: {
            Group {
                if let from = confirm.from, let to = confirm.to {
                    HStack(spacing: 8) {
                        buttonSquare(from)
                        Text(from.name)
                        Image(systemName: "arrow.right")
                        buttonSquare(to)
                        Text(to.name)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                } else {
                    Text(confirm.title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!confirm.isEnabled)
        .accessibilityLabel(confirm.title)
    }

    /// A day's square on the button, on a chip of the screen's background, so a rest's grey and
    /// an own day's ink read as they do on the strip rather than taking the button's tint.
    private func buttonSquare(_ face: DayChoices.Face) -> some View {
        DaySquare(colour: face.colour, size: 12, outlined: face.outlined)
            .padding(3)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func toggle(_ mark: DayChoices.Mark) {
        marked = marked == mark ? nil : mark
    }
}
