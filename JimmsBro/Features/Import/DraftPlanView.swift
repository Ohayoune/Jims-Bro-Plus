import SwiftUI

/// SPEC §4.4 / §6.28 (D52, v1.5): **Build it day by day**. The outline first, then one paste
/// per day into its slot, then the ordinary review and Save plan. Nothing here decides
/// anything: the draft is the model's, the reading is `PlanDrafting`'s.
struct DraftPlanView: View {
    @Environment(AppModel.self) private var model
    /// Runs once the plan is saved, so the Add plan sheet above can close.
    let saved: () -> Void

    @State private var issues: [Issue] = []
    /// Which slot the issues are about, or nil for the outline.
    @State private var issuesFor: Int?
    @State private var copied: Int?
    @State private var reviewing: Plan?
    @State private var pending: Plan?
    @State private var conflicting: Plan?
    @State private var makeActive = true
    @State private var confirmDiscard = false

    private var errors: [Issue] { issues.filter { $0.severity == .error } }

    var body: some View {
        List {
            if let draft = model.draft {
                outlineSection(draft)
                daysSection(draft)
            } else {
                startSection
            }
            if !errors.isEmpty { errorSection }
        }
        .navigationTitle("Day by day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.draft != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Discard draft", role: .destructive) { confirmDiscard = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .bottomAction {
            if let draft = model.draft, draft.isComplete {
                PrimaryButton(title: "Review plan") { review() }
            }
        }
        .confirmationDialog("Discard this draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { Task { await model.discardDraft() }; issues = [] }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The outline and every day you pasted go. Nothing you saved changes.")
        }
        .sheet(item: $reviewing, onDismiss: resolvePending) { plan in
            PlanReviewSheet(plan: plan, makeActive: $makeActive) {
                pending = plan
                reviewing = nil
            }
        }
        .alert("A plan named \"\(conflicting?.name ?? "")\" already exists",
               isPresented: Binding(get: { conflicting != nil }, set: { if !$0 { conflicting = nil } })) {
            Button("Replace") { resolve(.replace) }
            Button("Keep both") { resolve(.keepBoth) }
            Button("Cancel", role: .cancel) { conflicting = nil }
        }
    }

    // MARK: - The outline

    private var startSection: some View {
        Section {
            step(1, "Copy the outline prompt. The chatbot answers with the plan's name, its days and its repeat block — no exercises yet.") {
                copyButton(index: -1) { model.outlinePrompt() }
            }
            step(2, "Paste it into ChatGPT, Claude or another chatbot, and describe your training.")
            HStack {
                Label("Paste outline", systemImage: "doc.on.clipboard")
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    guard let first = strings.first else { return }
                    Task {
                        issuesFor = nil
                        issues = await model.startDraft(first)
                    }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
            }
        } header: {
            Text("The outline")
        } footer: {
            Text("For long plans, or a chatbot that cuts replies short. " + PromptText.mechanism)
        }
    }

    private func outlineSection(_ draft: PlanDraft) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(draft.outline.name).font(.headline)
                Text("\(draft.outline.units.rawValue) · \(draft.outline.schedule.rawValue) · \(draft.progress)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(RepeatBlock.chips(draft.outline).enumerated()), id: \.offset) { _, name in
                            Text(name)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        } footer: {
            Text("One prompt per day: copy it, paste it into the same chat, and paste the reply into its slot. "
                 + PromptText.mechanism)
        }
    }

    // MARK: - The days

    private func daysSection(_ draft: PlanDraft) -> some View {
        Section("Days") {
            ForEach(Array(draft.outline.days.enumerated()), id: \.offset) { index, day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(day.name)
                        Spacer()
                        Text(status(draft, index))
                            .font(.footnote)
                            .foregroundStyle(draft.dayTexts[index] == nil ? .secondary : Color.done)
                    }
                    HStack(spacing: 10) {
                        copyButton(index: index) { model.dayPrompt(index) ?? "" }
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            guard let first = strings.first else { return }
                            Task {
                                issuesFor = index
                                issues = await model.pasteDraftDay(first, into: index)
                            }
                        }
                        .labelStyle(.titleOnly)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func status(_ draft: PlanDraft, _ index: Int) -> String {
        guard draft.dayTexts[index] != nil else { return "Not yet" }
        // The count is the outline's own when the chatbot wrote the day into it, and the
        // slot's fragment otherwise; either way it is what the review will show.
        if let text = draft.dayTexts[index],
           let count = PlanDrafting.dayObject(text, for: draft.outline.days[index], index: index).object?["exercises"]?.array?.count {
            return "\(count) exercise\(count == 1 ? "" : "s")"
        }
        return "Pasted"
    }

    /// One Copy button per prompt, reading "Copied" for two seconds (N12) — the accent one,
    /// beside its sentence, as everywhere since D50.
    private func copyButton(index: Int, text: @escaping () -> String) -> some View {
        Button(copied == index ? "Copied" : (index < 0 ? "Copy outline prompt" : "Copy day prompt")) {
            Clipboard.write(text())
            copied = index
            Task {
                try? await Task.sleep(for: .seconds(2))
                if copied == index { copied = nil }
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    @ViewBuilder private func step(_ number: Int, _ text: String,
                                   @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Color.secondary.opacity(0.15), in: Circle())
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Errors

    /// D26's shape: the sentence first, the path and the code behind it.
    private var errorSection: some View {
        Section {
            ForEach(Array(errors.enumerated()), id: \.offset) { _, issue in
                VStack(alignment: .leading, spacing: 4) {
                    Text(IssueText.friendly(issue))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !issue.path.isEmpty {
                        Text("\(issue.path) · \(issue.code)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.red.opacity(0.08))
            }
        } header: {
            Text(issuesFor.map { "Day \($0 + 1) can't be added yet" } ?? "The outline can't be read yet")
        }
    }

    // MARK: - Saving

    private func review() {
        let result = model.assembleDraft()
        issuesFor = nil
        issues = result.issues
        reviewing = result.plan
    }

    private func resolvePending() {
        guard let plan = pending else { return }
        pending = nil
        if model.conflict(for: plan) != nil {
            conflicting = plan
        } else {
            Task {
                await model.saveDraftPlan(plan, makeActive: makeActive)
                saved()
            }
        }
    }

    private func resolve(_ choice: ConflictChoice) {
        guard let plan = conflicting else { return }
        conflicting = nil
        Task {
            if await model.saveDraftPlan(plan, conflict: choice, makeActive: makeActive) != nil { saved() }
        }
    }
}
