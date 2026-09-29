import SwiftUI

/// SPEC §6.60, §6.68 (D87, D95; D96 v1.12): the parts every chatbot screen draws the same way —
/// Add plan, Progression, Say what should change, and the text sheet — each drawn once here, from
/// what Core says.

/// §6.60: a refusal as D26 put it — the first sentence in the red band, and behind **Details** the
/// rest of the sentences, each over its path and its code with the importer's own words.
struct RefusalDetails: View {
    let refusal: TripRefusal

    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sentence = refusal.sentence { RefusedBand(sentence: sentence) }
            if !refusal.errors.isEmpty {
                Button(showDetails ? "Hide details" : "Details (\(refusal.errors.count))") { showDetails.toggle() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
            if showDetails {
                // The band holds the first sentence; the rest are here, each over its path.
                ForEach(Array(refusal.errors.enumerated()), id: \.offset) { index, issue in
                    IssueDetail(issue: issue, sentence: index > 0 ? IssueText.friendly(issue) : nil)
                }
            }
        }
    }
}

/// D26: an issue's path, and its code with the importer's own message — what is behind Details —
/// under its friendly sentence when nothing else on the screen says it.
struct IssueDetail: View {
    let issue: Issue
    var sentence: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let sentence {
                Text(sentence)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if !issue.path.isEmpty { Text(issue.path).font(.caption.monospaced()) }
                Text("\(issue.code) · \(issue.message)")
                    .font(.caption2.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// D26's review: the warnings that change what the workout will be, above the days, each with
/// where it is. Nothing when there are none.
struct WorthKnowing: View {
    let warnings: [Issue]

    var body: some View {
        let material = IssueText.split(warnings).material
        if !material.isEmpty {
            Section("Worth knowing") {
                ForEach(Array(material.enumerated()), id: \.offset) { _, warning in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.message)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        if let place = IssueText.location(warning.path) {
                            Text(place).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.yellow.opacity(0.15))
                }
            }
        }
    }
}

/// D26's review: the tidying the importer did on its own, behind Details at the foot. Nothing when
/// there was none.
struct Tidying: View {
    let warnings: [Issue]

    @State private var expanded = false

    var body: some View {
        let cleanup = IssueText.split(warnings).cleanup
        if !cleanup.isEmpty {
            Section {
                DisclosureGroup("Details (\(cleanup.count))", isExpanded: $expanded) {
                    Text("Tidying the app did on its own. None of it changes the workout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(cleanup.enumerated()), id: \.offset) { _, warning in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(warning.message).font(.caption)
                            if !warning.path.isEmpty {
                                Text(warning.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.footnote)
            }
        }
    }
}

/// §6.60's Paste: the system's button, alone — no permission alert, and nothing when the clipboard
/// holds no text. `size` follows the strip's (§6.62): large on Add plan, smaller where the strip is
/// small.
struct TripPasteButton: View {
    var size: ControlSize = .large
    let paste: (String) -> Void

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            guard let text = strings.first else { return }
            Task { @MainActor in paste(text) }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .controlSize(size)
        .frame(maxWidth: .infinity)
    }
}

/// §6.68 (D95): a trip screen's ···, its items Core's (`TripMenuItem`), Edit the text last. The two
/// that take something away are drawn destructive; the screen asks before either acts (D56).
struct TripMenu: View {
    let items: [TripMenuItem]
    let choose: (TripMenuItem) -> Void

    var body: some View {
        Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(role: item.isDestructive ? .destructive : nil) { choose(item) } label: {
                    Label(item.title, systemImage: Self.symbol(item))
                }
            }
        } label: {
            QuietGlyph(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private static func symbol(_ item: TripMenuItem) -> String {
        switch item {
        case .sendAgain: return "square.and.arrow.up"
        case .openFile: return "folder"
        case .keepWithoutUsing: return "tray.and.arrow.down"
        case .discardDraft, .removeProgression: return "trash"
        case .keepCurrent: return "arrow.uturn.backward"
        case .editText: return "curlybraces"
        }
    }
}
