import Foundation

/// SPEC §6.60 (D87, v1.11): **show the result, not the format.** Every point where the app hands
/// text to a chatbot and takes its reply back — Add plan, Progression, Say what should change —
/// is one screen in three states with one control each, the same three everywhere, and a fourth
/// for a reply the pipeline refused. Each point has its own screen type in its own file
/// (`ImportTrip`, `ProgressionScreen`, `ChangeRequest`); this is what they share.
///
/// This file is compiled into the widget extension too, because `DaySquare.swift` draws the
/// strip (`TripStripView`) and the extension builds that file; it depends on nothing but
/// Foundation and `MarkState`.
enum TripStage: Equatable, Sendable {
    /// The prompt is ready: Send the prompt, Copy the prompt.
    case ask
    /// The prompt went out: the system Paste button, alone.
    case paste
    /// What the app drew from the reply, and one button that names the effect.
    case review
    /// The reply was refused: the sentence in a red band, and a way to send the trouble back.
    case refused
}

/// SPEC §6.62 (D89): the trip strip — Prompt, Chat, Paste — as three marks in the Workout
/// screen's states (D79): the squares behind are done, the one you are at is now, the ones
/// ahead are not yet. On these screens *done* is ink, since there is no day to colour it.
struct TripStrip: Equatable, Sendable {
    static let names = ["Prompt", "Chat", "Paste"]
    /// Always three, one per name.
    var marks: [MarkState]

    /// Ask lights Prompt; Paste lights Paste with the two behind it done; Review has all three
    /// done; Refused lights where the fix is — `fixAt` 1, Chat, when the reply must be asked for
    /// again, 2, Paste, when what was pasted was the prompt itself or nothing.
    static func of(_ stage: TripStage, fixAt: Int = 1) -> TripStrip {
        switch stage {
        case .ask: return TripStrip(marks: [.now, .todo, .todo])
        case .paste: return TripStrip(marks: [.done, .done, .now])
        case .review: return TripStrip(marks: [.done, .done, .done])
        case .refused:
            let at = min(max(fixAt, 0), names.count - 1)
            return TripStrip(marks: names.indices.map { $0 < at ? .done : $0 == at ? .now : .todo })
        }
    }

    /// What VoiceOver reads for the strip: "Prompt, done. Chat, now. Paste, not yet."
    var spoken: String {
        zip(Self.names, marks).map { name, mark in
            "\(name), " + (mark == .done ? "done" : mark == .now ? "now" : "not yet") + "."
        }.joined(separator: " ")
    }
}

/// SPEC §6.60–§6.61 (D87, D88): the bottom slot of a trip screen. Views draw it; they never
/// compose it.
struct TripButtons: Equatable, Sendable {
    var primary: String
    /// The quieter button beneath the primary one, when there is one.
    var secondary: String?

    /// Ask's two buttons: **Send the prompt** through the share sheet, **Copy the prompt**
    /// beneath it (J1). `prompt` names which prompt when a screen has more than one — *the
    /// outline prompt*, *the prompt for Pull* (D91).
    static func ask(_ prompt: String = "the prompt") -> TripButtons {
        TripButtons(primary: "Send \(prompt)", secondary: "Copy \(prompt)")
    }

    /// Paste's one button, the system's.
    static let paste = TripButtons(primary: "Paste", secondary: nil)

    /// Review's one button, named for what it does — **Use Push Pull Legs**, **Start step 1**,
    /// **Use for Wednesday**, **Apply 2 changes** — never a bare Save.
    static func effect(_ title: String) -> TripButtons { TripButtons(primary: title, secondary: nil) }
}
