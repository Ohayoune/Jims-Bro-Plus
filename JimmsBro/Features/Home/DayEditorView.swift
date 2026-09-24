import SwiftUI

/// SPEC §6.66 (D93, v1.11): **the day's editor** — a date's exercises edited where they stand,
/// pushed from the Change *day* picker's card. Titled *Change Push* with the day's square, the
/// date over the card, the exercises as Today draws them — the name, its sets as blocks, a handle
/// — and a dashed **Add exercise** row; **Use for Wednesday** in the bottom slot. A row opens the
/// exercise sheet's value form; the handle reorders and a swipe deletes, as Plan detail's edit
/// mode does. Every change is a `DayEdit` on the day the screen holds, never stored: leave and
/// nothing has changed. Use reads the day back through the importer (`DayChoices.Exercises.used`)
/// and writes it as the date's own day; the ··· goes back to the day as written, or opens the text.
struct DayEditorView: View {
    @Environment(AppModel.self) private var model
    let date: Date
    let exercises: DayChoices.Exercises
    /// The date's day written or removed: back to Today, past the picker.
    let finished: () -> Void

    /// The day as edited so far — the screen's, and nothing else's until Use.
    @State private var day: Day
    /// The exercise whose sheet is open.
    @State private var editing: Exercise?
    @State private var adding = false
    /// Edit the text's sheet, on the day as it was when the item was tapped.
    @State private var text: JSONPoint?
    /// What refused Use, in the importer's sentence, until the next change.
    @State private var refusal: String?
    /// Add exercise's search as it opens: empty but for a debug run's `-uiEditor add <query>`.
    @State private var debugQuery = ""
    /// F2 (2026-09-24): Back to the day as written, asked before it discards the date's own day.
    @State private var confirmBack = false
    /// F3 (2026-09-24): Back with the card changed, asking before the change goes.
    @State private var discarding = false
    @Environment(\.dismiss) private var dismiss

    init(date: Date, exercises: DayChoices.Exercises, finished: @escaping () -> Void) {
        self.date = date
        self.exercises = exercises
        self.finished = finished
        _day = State(initialValue: exercises.day)
    }

    var body: some View {
        let rows = DayChoices.rows(day)
        List {
            Section {
                ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, exercise in
                    Button { editing = exercise } label: {
                        row(rows[index])
                    }
                    .buttonStyle(PressableRow())
                }
                .onMove { offsets, destination in
                    guard let from = offsets.first else { return }
                    // SwiftUI's destination is the gap; an index is what we move to.
                    apply(.move(from: from, to: destination > from ? destination - 1 : destination))
                }
                .onDelete { offsets in
                    guard let index = offsets.first else { return }
                    apply(.remove(index))
                }
            } header: {
                Text(exercises.date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
            Section {
                Button { adding = true } label: {
                    Label(ChangeDayText.addExercise, systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        .contentShape(Rectangle())
                }
                // The dashes are the row: no card behind it, drawn edge to edge of the section, and
                // rounded at least as much as the section, which clips its row to its own corners.
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(exercises.title)
        .navigationBarTitleDisplayMode(.inline)
        // F3 (2026-09-24): with the card changed, the way back asks before it drops the change —
        // the system's button is hidden, which stops the edge swipe too, and this one stands in.
        .navigationBarBackButtonHidden(dirty)
        .toolbar {
            if dirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { discarding = true } label: { Image(systemName: "chevron.backward") }
                        .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    DaySquare(colour: exercises.face.colour, size: 12, outlined: exercises.face.outlined)
                    Text(exercises.title).font(.headline)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let back = exercises.back {
                        Button(back.title) { confirmBack = true }
                    }
                    // D95: the text is the ···'s last item.
                    Button(ChangeDayText.editText) { text = exercises.textPoint(day) }
                } label: {
                    QuietGlyph(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
            .quietBackground()
        }
        .bottomAction {
            VStack(spacing: 10) {
                if let refusal {
                    RefusedBand(sentence: refusal)
                }
                Button(action: use) {
                    Text(exercises.use).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!exercises.isEdited(day))
            }
        }
        #if DEBUG
        .task {
            // Debug-only, after `-uiScreen changeDay -uiEditor`: `add <query>` opens Add exercise
            // searching for the query; `empty` removes every exercise and presses Use.
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-uiEditor"), let mode = arguments[safe: index + 1] else { return }
            if mode == "add" {
                debugQuery = arguments[safe: index + 2] ?? ""
                adding = true
            } else if mode == "empty" {
                for position in day.exercises.indices.reversed() { apply(.remove(position)) }
                use()
            }
        }
        #endif
        // F2 (2026-09-24): Back discards what was written for the date, so it asks first — an
        // alert with two named buttons, as every confirmation from a ··· is (§4.0, D56).
        .alert(exercises.back?.question ?? "", isPresented: $confirmBack) {
            Button("Discard", role: .destructive) {
                guard let back = exercises.back else { return }
                // D48: back to Today at once; the write follows.
                Task { await model.chooseDay(back.slot, for: date) }
                finished()
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text(exercises.back?.message ?? "")
        }
        .discardGuard(dirty, asking: $discarding) { dismiss() }
        .sheet(item: $editing) { exercise in
            ExerciseEditSheet(exercise: exercise, units: exercises.units) { edited in
                replace(exercise, with: edited)
            }
        }
        .sheet(isPresented: $adding) {
            AddExerciseSheet(query: debugQuery) { name in
                apply(.add(DayEdit.exercise(named: name, in: day, settings: model.settings)))
            }
        }
        .sheet(isPresented: Binding(get: { text != nil }, set: { if !$0 { text = nil } })) {
            if let text {
                JSONFragmentSheet(point: text) { written in
                    // D95: Save puts the text's day in the editor; Use still writes it.
                    let read = exercises.checked(written, settings: model.settings, now: Date())
                    guard let textDay = read.day else { return read.issues }
                    day = textDay
                    refusal = nil
                    return []
                }
            }
        }
    }

    /// A row as Today draws it: the name, its sets as blocks, and the handle.
    private func row(_ row: HomeStart.PreviewRow) -> some View {
        HStack(spacing: 10) {
            Text(row.name)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            SetBlocks(sets: row.sets, logged: 0, colour: exercises.face.colour)
            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue("\(row.sets) set\(row.sets == 1 ? "" : "s")")
    }

    /// A change clears the refusal: the day it named is gone.
    private func apply(_ edit: DayEdit) {
        day = edit.applied(to: day)
        refusal = nil
    }

    /// The value form's Save: the day with the exercise replaced must still be a day the importer
    /// takes, or the sheet stays open with the sentence.
    private func replace(_ exercise: Exercise, with edited: Exercise) -> [Issue] {
        guard let index = day.exercises.firstIndex(where: { $0.id == exercise.id }) else { return [] }
        let next = DayEdit.replace(index, edited).applied(to: day)
        let read = exercises.checked(next, settings: model.settings, now: Date())
        guard read.day != nil else { return read.issues }
        day = next
        refusal = nil
        return []
    }

    /// F3 (2026-09-24): the card changed from the day it opened on.
    private var dirty: Bool { day != exercises.day }

    /// Use for Wednesday: checked first, so a refusal stays on the screen; then, as D48 has it,
    /// back to Today at once and the write behind it.
    private func use() {
        let used = exercises.used(day, settings: model.settings, now: Date())
        guard let slot = used.slot else {
            refusal = used.issues.first.map(IssueText.friendly)
            return
        }
        Task { await model.chooseDay(slot, for: date) }
        finished()
    }
}

/// D93: Add exercise — a search field that reads **Find an exercise** over the names the app
/// knows (`ExerciseNames`), each with where it was found, and a name that matches nothing added
/// as typed. A tap adds the exercise and closes the sheet; the row is the next tap.
private struct AddExerciseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let add: (String) -> Void
    @State private var query: String

    init(query: String = "", add: @escaping (String) -> Void) {
        self.add = add
        _query = State(initialValue: query)
    }

    var body: some View {
        let names = model.library.exerciseNames(matching: query)
        NavigationStack {
            List {
                if let typed = ExerciseNames.typed(query, known: names) {
                    Button { choose(typed) } label: {
                        Label(ChangeDayText.addTyped(typed), systemImage: "plus")
                    }
                }
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Button { choose(name.name) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.name).foregroundStyle(.primary)
                            Text(name.source).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    // A name is ink, not a link; only the row that adds a typed name is the accent.
                    .tint(.primary)
                    .accessibilityElement(children: .combine)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: ExerciseNames.prompt)
            .navigationTitle(ChangeDayText.addExercise)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func choose(_ name: String) {
        add(name)
        dismiss()
    }
}
