import SwiftUI
import UIKit

/// SPEC §4.3, §6.19 (D43, v1.3; D77, v1.9): one exercise or one day, as text. One sheet serves
/// every point where a fragment is edited, told what it is by a `JSONPoint`: the title says what
/// the JSON is and the line beneath it where it lands, the text opens pre-filled, a refusal marks
/// the line its path names with the sentence beneath it, and Save says its effect. Every Save
/// goes through the import pipeline, so the errors it shows are the ones a paste would get, with
/// the real path behind Details.
struct JSONFragmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let point: JSONPoint
    /// Runs the edit; returns the errors that stopped it, or nothing when it was saved.
    let commit: (String) async -> [Issue]

    @State private var text = ""
    @State private var errors: [Issue] = []
    /// The text the errors were found in. Its lines stay marked while it is the text; an edit
    /// unmarks them, because a line that moved would be the wrong line (§6.19).
    @State private var refused = ""
    @State private var showDetails = false
    @State private var saving = false
    @State private var loaded = false
    @ScaledMetric(relativeTo: .footnote) private var editorHeight: CGFloat = 300

    var body: some View {
        let found: (marked: [JSONPoint.Mark], unmarked: [String]) = text == refused
            ? point.marks(for: errors, in: text)
            : ([], errors.map(IssueText.friendly))
        NavigationStack {
            List {
                Text(point.place)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                Section {
                    FragmentEditor(text: $text, marks: found.marked)
                        .frame(height: min(editorHeight, 460))
                } footer: {
                    if errors.isEmpty { Text(point.footer) }
                }
                // The sentences no line could honestly be named for stay under the box.
                if !errors.isEmpty { errorSection(found.unmarked) }
                Section {
                    HStack {
                        Label("Replace with the clipboard", systemImage: "doc.on.clipboard")
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            guard let first = strings.first else { return }
                            text = first
                            errors = []
                        }
                        .labelStyle(.titleOnly)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
            .navigationTitle(point.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .bottomAction {
                PrimaryButton(title: point.saveTitle, enabled: !text.trimmed.isEmpty && !saving) { save() }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                text = point.template
            }
        }
    }

    /// D26's rule for errors: the sentence first, the path and the code behind Details. A
    /// sentence whose line is marked sits beneath that line instead (D77).
    private func errorSection(_ sentences: [String]) -> some View {
        Section {
            ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                Text(sentence)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.red.opacity(0.08))
            }
            if showDetails {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: 1) {
                        if !issue.path.isEmpty { Text(issue.path).font(.caption.monospaced()) }
                        Text("\(issue.code) · \(issue.message)")
                            .font(.caption2.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Button(showDetails ? "Hide details" : "Details (\(errors.count))") { showDetails.toggle() }
                .font(.footnote)
        } header: {
            Text(errors.count == 1 ? "This can't be saved yet" : "\(errors.count) things to fix")
        }
    }

    private func save() {
        saving = true
        showDetails = false
        let sent = text
        Task {
            let refusals = await commit(sent)
            saving = false
            if refusals.isEmpty {
                dismiss()
            } else {
                errors = refusals
                refused = sent
            }
        }
    }
}

/// D43: which part of the plan a fragment sheet is for, or which kind of new part — a thin map
/// to the `JSONPoint` that says the rest (D77).
enum FragmentTarget: Identifiable, Equatable {
    case exercise(day: Int, exercise: Int)
    case addExercise(day: Int)
    case day(Int)
    case addDay

    var id: String {
        switch self {
        case let .exercise(day, exercise): return "exercise.\(day).\(exercise)"
        case let .addExercise(day): return "addExercise.\(day)"
        case let .day(day): return "day.\(day)"
        case .addDay: return "addDay"
        }
    }

    func point(_ plan: Plan) -> JSONPoint? {
        switch self {
        case let .exercise(day, exercise): return JSONPoint.exercise(plan, day: day, exercise: exercise)
        case let .addExercise(day): return JSONPoint.addExercises(plan, day: day)
        case let .day(day): return JSONPoint.day(plan, day: day)
        case .addDay: return JSONPoint.addDays(plan)
        }
    }
}

/// D77 (v1.9): the box. A `UITextView` on TextKit 1, because marking a line — a tint across it
/// and its sentence beneath it, the text below moved down to make room rather than covered —
/// needs the layout's own rectangles, which SwiftUI's `TextEditor` does not give on iOS 17.
private struct FragmentEditor: UIViewRepresentable {
    @Binding var text: String
    let marks: [JSONPoint.Mark]

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> MarkedTextView {
        let view = MarkedTextView(usingTextLayoutManager: false)
        view.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        // JSON wants straight quotes: the importer mends curly ones, but the line of a text it
        // had to mend is one the locator will not name.
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.delegate = context.coordinator
        view.text = text
        return view
    }

    func updateUIView(_ view: MarkedTextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text { view.text = text }
        view.marks = marks
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) { text.wrappedValue = textView.text }
    }
}

/// Draws the marks: a tint across each marked line with a bar at its edge — a mark that is not
/// colour alone — and the line's sentences in a gap beneath it that the text flows around (an
/// exclusion path), so nothing written is covered.
private final class MarkedTextView: UITextView {
    var marks: [JSONPoint.Mark] = [] {
        didSet {
            guard marks != oldValue else { return }
            placed = false
            revealed = marks.isEmpty
            setNeedsLayout()
        }
    }

    private var drawn: [UIView] = []
    private var placed = true
    private var revealed = true
    private var placedWidth: CGFloat = 0
    private var watching = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !watching else { return }
        watching = true
        // Larger text makes taller sentences, and the gaps beneath the lines must follow.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: MarkedTextView, _: UITraitCollection) in
            view.placed = false
            view.setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !placed || bounds.width != placedWidth { place() }
    }

    private func place() {
        placed = true
        placedWidth = bounds.width
        drawn.forEach { $0.removeFromSuperview() }
        drawn = []
        textContainer.exclusionPaths = []
        var gaps: [UIBezierPath] = []
        let inset = textContainerInset
        let padding = textContainer.lineFragmentPadding
        let noteWidth = max(bounds.width - inset.left - inset.right - 2 * padding, 40)
        var first: CGRect?
        for mark in marks {
            guard let range = JSONLocator.range(ofLine: mark.line, in: text) else { continue }
            layoutManager.ensureLayout(for: textContainer)
            let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(range, in: text), actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let top = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let bottom = layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)

            let note = UILabel()
            note.numberOfLines = 0
            note.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
            note.textColor = .systemRed
            note.text = mark.sentences.joined(separator: "\n")
            note.isUserInteractionEnabled = false
            let noteHeight = ceil(note.sizeThatFits(CGSize(width: noteWidth, height: .greatestFiniteMagnitude)).height)
            let gap = CGRect(x: 0, y: bottom.maxY, width: textContainer.size.width, height: noteHeight + 12)
            gaps.append(UIBezierPath(rect: gap))
            textContainer.exclusionPaths = gaps

            let band = UIView(frame: CGRect(x: 0, y: inset.top + top.minY, width: bounds.width,
                                            height: bottom.maxY - top.minY + gap.height))
            band.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
            band.isUserInteractionEnabled = false
            let bar = UIView(frame: CGRect(x: 0, y: 0, width: 3, height: band.bounds.height))
            bar.backgroundColor = .systemRed
            band.addSubview(bar)
            insertSubview(band, at: 0)
            note.frame = CGRect(x: inset.left + padding, y: inset.top + bottom.maxY + 5, width: noteWidth, height: noteHeight)
            addSubview(note)
            drawn += [band, note]
            first = first ?? band.frame
        }
        accessibilityHint = marks.isEmpty ? nil
            : marks.map { "Line \($0.line): " + $0.sentences.joined(separator: " ") }.joined(separator: " ")
        if !revealed, let first {
            revealed = true
            scrollRectToVisible(first.insetBy(dx: 0, dy: -16), animated: true)
        }
    }
}
