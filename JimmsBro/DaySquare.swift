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

/// The small filled square that says which day. It says *which day*, never *tap here* — that is
/// the accent's (§4.0) — and the name beside it says the same, so VoiceOver skips it. With no
/// colour (a workout whose plan is gone, or whose day was renamed) it is grey, so a column of
/// History rows stays a column.
struct DaySquare: View {
    let colour: DayColour?
    /// The side at the default text size; it grows with Dynamic Type.
    var size: CGFloat = 10
    @ScaledMetric private var scale: CGFloat = 1

    /// D69 (v1.8): Today's square is as tall as the large title's capitals, so it grows on the
    /// large title's curve rather than body text's.
    init(colour: DayColour?, size: CGFloat = 10, relativeTo textStyle: Font.TextStyle = .body) {
        self.colour = colour
        self.size = size
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: textStyle)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * scale / 4, style: .continuous)
            .fill(colour?.color ?? Color.secondary.opacity(0.4))
            .frame(width: size * scale, height: size * scale)
            .accessibilityHidden(true)
    }
}

/// D75 (v1.9, §6.49): a plan's cycle as one symbol — its squares in one row, all one size, each
/// its day's colour and grey for rest, and past fourteen a trailing mark (`CycleGlyph` says
/// where it cuts). It says *which plan* by its shape, as a day's square says which day; the
/// words beside it name it, so VoiceOver skips it. The ···'s Change plan draws it, and the
/// Plans list will (D78).
struct CycleSymbol: View {
    let cycle: [DayColour?]
    /// A square's side at the default text size; it grows with Dynamic Type.
    var size: CGFloat = 6
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        let glyph = CycleGlyph(cycle)
        let side = size * scale
        HStack(spacing: side / 3) {
            ForEach(Array(glyph.squares.enumerated()), id: \.offset) { _, colour in
                RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                    .fill(colour?.color ?? Color.secondary.opacity(0.4))
                    .frame(width: side, height: side)
            }
            if glyph.continues {
                // The trailing mark: three grey dots, *and more*.
                HStack(spacing: side / 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.secondary).frame(width: side / 3, height: side / 3)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
