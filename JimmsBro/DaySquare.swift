import SwiftUI

/// SPEC §6.41 (D65, v1.7): a day's colour, drawn. Core names the colour (`DayColour`); this is
/// the one place a name becomes a `Color` — the system colour of the same name, so it follows
/// dark mode — and T23 reads this file to hold it there. Compiled into the app and the widget
/// extension alike, so Today, the calendar, History, the workout header and the Lock Screen
/// draw the same colour from the same code.
extension DayColour {
    var color: Color {
        switch self {
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .teal: return .teal
        case .indigo: return .indigo
        }
    }
}

/// SPEC §6.52 (D79, v1.10): a mark's state, drawn — on the Workout screen and the Lock Screen
/// activity, and nowhere else. Done is the day's colour, grey when the day has none, as History
/// draws it; now is the accent, which on that screen says *now* and nothing else; not yet is the
/// system's secondary fill. The ring's traffic light (P3) and the yellow past a range (P2) are
/// not states, and TP2 holds this mapping apart from them.
extension MarkState {
    func color(day: DayColour?) -> Color {
        switch self {
        case .done: return day?.color ?? DaySquare.noColour
        case .now: return .accentColor
        case .todo: return Color(.secondarySystemFill)
        }
    }
}

/// The small filled square that says which day. It says *which day*, never *tap here* — that is
/// the accent's (§4.0) — and the name beside it says the same, so VoiceOver skips it. With no
/// colour (a workout whose plan is gone, or whose day was renamed) it is grey, so a column of
/// History rows stays a column.
struct DaySquare: View {
    let colour: DayColour?
    /// The side at the default text size; it grows with Dynamic Type.
    var size: CGFloat = 10
    /// D76 (v1.9, §6.50): outlined rather than filled — a day of another plan in that plan's
    /// colour, a day written just for one date in ink. The outline says *not from this plan*;
    /// the colour still says *which day*.
    var outlined = false
    @ScaledMetric private var scale: CGFloat = 1

    /// The grey of a day with no colour — a square, a cycle's rest, a done mark (D79).
    static let noColour = Color.secondary.opacity(0.4)

    /// D69 (v1.8): Today's square is as tall as the large title's capitals, so it grows on the
    /// large title's curve rather than body text's.
    init(colour: DayColour?, size: CGFloat = 10, outlined: Bool = false,
         relativeTo textStyle: Font.TextStyle = .body) {
        self.colour = colour
        self.size = size
        self.outlined = outlined
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: textStyle)
    }

    var body: some View {
        let side = size * scale
        let shape = RoundedRectangle(cornerRadius: side / 4, style: .continuous)
        Group {
            if outlined {
                shape.strokeBorder(colour?.color ?? Color.primary, lineWidth: max(1.5, side / 7))
            } else {
                shape.fill(colour?.color ?? DaySquare.noColour)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// D75 (v1.9, §6.49): a plan's cycle as one symbol — its squares all one size, each its day's
/// colour and grey for rest, and past fourteen a trailing mark (`CycleGlyph` says where it
/// cuts). D86 (v1.10, §6.59): seven to a row, the squares touching, drawn by `CycleStrip`. It
/// says *which plan* by its shape, as a day's square says which day; the words beside it name
/// it, so VoiceOver skips it. The ···'s Change plan draws it, and so does each row of the Plans
/// list (D78).
struct CycleSymbol: View {
    let cycle: [DayColour?]
    /// A square's side at the default text size; it grows with Dynamic Type.
    var size: CGFloat = 6
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        let glyph = CycleGlyph(cycle)
        let side = size * scale
        HStack(alignment: .bottom, spacing: side / 3) {
            CycleStrip(count: glyph.squares.count, side: side, spacing: side / 3, lineSpacing: side / 3) { index in
                StripSquare(colour: glyph.squares[index], index: index, count: glyph.squares.count)
            }
            if glyph.continues {
                // The trailing mark, after the last row: three grey dots, *and more*.
                HStack(spacing: side / 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.secondary).frame(width: side / 3, height: side / 3)
                    }
                }
                .frame(height: side)
            }
        }
        .accessibilityHidden(true)
    }
}

/// D86 (v1.10, §6.59): **squares that join.** A cycle's squares seven to a row, the second row
/// under the first, touching — `spacing` apart, 2 pt on the plan's page and in the picker — so a
/// cycle reads as one thing. Every square is the same side: `side` at most, less when seven
/// would not fit the width offered. What stands in each place is the caller's — a
/// `StripSquare`, with a name beneath it or not — and a row is as tall as its tallest place.
/// The Plans list's symbol, the plan's page and the picker's strips (D85) are this drawing at
/// three sizes. Today's week strip is not: its squares are days tapped one at a time (§6.44).
struct CycleStrip<Place: View>: View {
    let count: Int
    var side: CGFloat
    var spacing: CGFloat = 2
    var lineSpacing: CGFloat = 2
    /// D91 (v1.11): the places a plan built day by day has not filled yet. Not drawn here — the
    /// caller's place draws a hollow day (`StripSquare(outlined:)`) — but carried by the strip so
    /// the review and its squares read one set.
    var hollow: Set<Int> = []
    @ViewBuilder let place: (Int) -> Place

    var body: some View {
        SquareRows(side: side, spacing: spacing, lineSpacing: lineSpacing) {
            ForEach(0..<count, id: \.self) { index in place(index) }
        }
    }
}

/// One square of a joined row: rounded at the row's two ends and square where it meets its
/// neighbours (`CycleGlyph.ends`). As wide as it is offered, and as tall.
struct StripSquare: View {
    var colour: DayColour?
    /// A day of another plan in that plan's colour, a day written for one date in ink (D76).
    var outlined = false
    /// D85: Custom, the day not yet written.
    var dashed = false
    /// D86: today's square, outlined in ink as the calendar outlines today.
    var ringed = false
    /// D89 (v1.11): a fill that is not a day's — the trip strip's ink, accent and grey.
    var tint: Color? = nil
    let index: Int
    let count: Int

    var body: some View {
        let ends = CycleGlyph.ends(index, count: count)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    let radius = min(side / 4, 12)
                    let shape = UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: ends.first ? radius : 0, bottomLeading: ends.first ? radius : 0,
                                           bottomTrailing: ends.last ? radius : 0, topTrailing: ends.last ? radius : 0),
                        style: .continuous)
                    let line = max(1.5, min(side / 7, 2.5))
                    ZStack {
                        if dashed {
                            shape.strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: line, dash: [4, 3]))
                        } else if outlined {
                            shape.strokeBorder(colour?.color ?? Color.primary, lineWidth: line)
                        } else {
                            shape.fill(tint ?? colour?.color ?? DaySquare.noColour)
                        }
                        if ringed {
                            shape.inset(by: outlined || dashed ? line : 0)
                                .strokeBorder(Color.primary, lineWidth: line)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

/// D86: the rows `CycleStrip` lays out — `CycleGlyph.width` places to a row, each offered the
/// same width, a row as tall as its tallest place and every place at the top of its row.
struct SquareRows: Layout {
    var side: CGFloat
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var perRow = CycleGlyph.width

    private func columns(_ count: Int) -> Int { max(1, min(count, perRow)) }

    /// The side every place is offered: `side`, or less when the row would not fit `width`.
    private func tile(_ width: CGFloat?, count: Int) -> CGFloat {
        let n = CGFloat(columns(count))
        guard let width, width.isFinite else { return side }
        return max(1, min(side, (width - (n - 1) * spacing) / n))
    }

    private func heights(_ subviews: Subviews, tile: CGFloat) -> [CGFloat] {
        CycleGlyph.rows(Array(subviews.indices), of: perRow).map { row in
            row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: tile, height: nil)).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let tile = tile(proposal.width, count: subviews.count)
        let n = CGFloat(columns(subviews.count))
        let rows = heights(subviews, tile: tile)
        return CGSize(width: n * tile + (n - 1) * spacing,
                      height: rows.reduce(0, +) + CGFloat(rows.count - 1) * lineSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let tile = tile(bounds.width, count: subviews.count)
        var y = bounds.minY
        for (row, height) in zip(CycleGlyph.rows(Array(subviews.indices), of: perRow), heights(subviews, tile: tile)) {
            for (column, index) in row.enumerated() {
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (tile + spacing), y: y),
                                      anchor: .topLeading, proposal: ProposedViewSize(width: tile, height: nil))
            }
            y += height + lineSpacing
        }
    }
}

/// D89 (v1.11, §6.62): **the trip strip** — Prompt, Chat, Paste — three joined squares with a
/// word beneath each, at the top of every chatbot screen's Ask, Paste and Refused states. The
/// squares behind are ink with a check, the one you are at the accent, the ones ahead grey; each
/// carries its glyph until it is done. D86's joined drawing at strip size: large and centred on
/// Add plan, small above the button on Progression and Say what should change.
struct TripStripView: View {
    let strip: TripStrip
    /// A square's side at the default text size.
    var side: CGFloat = 56
    @ScaledMetric private var scale: CGFloat = 1

    /// A document, a speech bubble, a clipboard.
    static let glyphs = ["doc.text", "bubble.left", "doc.on.clipboard"]

    var body: some View {
        let side = self.side * min(scale, 1.5)
        let count = TripStrip.names.count
        CycleStrip(count: count, side: side, spacing: 2) { index in
            let mark = index < strip.marks.count ? strip.marks[index] : .todo
            VStack(spacing: 6) {
                StripSquare(tint: Self.fill(mark), index: index, count: count)
                    .overlay {
                        Image(systemName: mark == .done ? "checkmark" : Self.glyphs[index])
                            .font(.system(size: side * 0.36, weight: .semibold))
                            .foregroundStyle(Self.glyph(mark))
                    }
                Text(TripStrip.names[index])
                    .font(side >= 44 ? .subheadline : .caption)
                    .fontWeight(mark == .now ? .semibold : .regular)
                    .foregroundStyle(mark == .todo ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strip.spoken)
    }

    /// Done is ink, not a day's colour: on these screens there is no day yet.
    static func fill(_ mark: MarkState) -> Color {
        switch mark {
        case .done: return .primary
        case .now: return .accentColor
        case .todo: return Color(.secondarySystemFill)
        }
    }

    static func glyph(_ mark: MarkState) -> Color {
        switch mark {
        case .done: return Color(.systemBackground)
        case .now: return .white
        case .todo: return .secondary
        }
    }
}

/// D87 (v1.11, §6.60): the Refused state's sentence (`IssueText.friendly`, D26) in a red band
/// under the strip, with the mark that says so. The path and the code stay behind Details.
struct RefusedBand: View {
    let sentence: String

    var body: some View {
        Label {
            Text(sentence).foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
