import SwiftUI

/// SPEC §6.48 (D74, v1.9): the question a taken day carries, on its card where the rows would
/// be. The heading says it in words — "Wednesday's Legs is done. Make Wednesday:" — then the
/// options are large squares with their word beneath, the chosen one checked, and on a rotation
/// Slide's row: an arrow, three small squares for the date and the two after it as Slide would
/// make them, an ellipsis and the word. One tap chooses; the card's button, which already
/// follows the choice, says it in words as well. Core wrote every word and colour; this view
/// draws them and decides nothing.
struct SwapQuestionView: View {
    let question: SwapQuestion
    let choose: (DaySwap.Slot) -> Void
    /// Large enough to be the thing on the card; capped, so the squares wrap rather than leave
    /// the screen at the largest text sizes.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(question.heading)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            WrapLayout(spacing: 18, lineSpacing: 14) {
                ForEach(Array(question.squares.enumerated()), id: \.offset) { _, option in
                    Button { choose(option.slot) } label: { square(option) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(option.isChosen ? .isSelected : [])
                }
            }
            if let slide = question.slide, let option = question.slideOption {
                Button { choose(option.slot) } label: { slideRow(slide, option: option) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(slide.spoken)
                    .accessibilityAddTraits(option.isChosen ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// An option: its square in the day's colour (grey for rest), checked when chosen, and its
    /// word beneath.
    private func square(_ option: SwapQuestion.Option) -> some View {
        let side = min(self.side, 88)
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                .fill(option.colour?.color ?? Color.secondary.opacity(0.4))
                .frame(width: side, height: side)
                .overlay {
                    if option.isChosen {
                        Image(systemName: "checkmark")
                            .font(.title2.weight(.bold))
                            // Ink on rest's grey, white on a day's colour.
                            .foregroundStyle(option.colour == nil ? Color.primary : Color.white)
                    }
                }
            Text(option.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(minWidth: side)
        .contentShape(Rectangle())
    }

    /// Slide: → ■ ■ ■ … Slide — the three days as the slide would make them.
    private func slideRow(_ slide: SwapQuestion.SlidePreview, option: SwapQuestion.Option) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            ForEach(Array(slide.colours.enumerated()), id: \.offset) { _, colour in
                DaySquare(colour: colour, size: 12, relativeTo: .subheadline)
            }
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
            Text(option.title)
            if option.isChosen {
                Image(systemName: "checkmark")
                    .fontWeight(.bold)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
