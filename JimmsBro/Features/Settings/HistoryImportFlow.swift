import SwiftUI
import UniformTypeIdentifiers

/// SPEC §6.20 (D45, v1.3): pick a CSV, hear what is in it, then Import. The same flow from
/// Settings and from an empty History tab, so it is written once.
struct HistoryImportFlow: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var choosing: Bool

    @State private var pending: AppModel.PendingHistoryImport?
    @State private var failure: String?
    @State private var importing = false

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $choosing,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text, .data]) { result in
                guard case let .success(url) = result else { return }
                Task {
                    switch await model.readHistoryCSV(at: url) {
                    case let .read(found): pending = found
                    case let .failed(message): failure = message
                    }
                }
            }
            // The file is only read at this point — nothing is written until Import is tapped.
            .confirmationDialog(prompt, isPresented: Binding(isPresent: $pending), titleVisibility: .visible) {
                if let pending, pending.summary.workouts > 0 {
                    Button("Import \(TargetText.counted(pending.summary.workouts, "workout"))") {
                        run(pending)
                    }
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text(pending?.summary.text() ?? "")
            }
            .problemAlert("That file wasn't imported", message: $failure)
    }

    private var prompt: String {
        guard let summary = pending?.summary else { return "Import history?" }
        return summary.workouts == 0 ? "Nothing new in this file" : "Import history from this file?"
    }

    private func run(_ pending: AppModel.PendingHistoryImport) {
        self.pending = nil
        importing = true
        Task {
            await model.importHistory(pending)
            importing = false
        }
    }
}

extension View {
    /// Attaches the pick → describe → import flow for a history CSV; `choosing` opens the picker.
    func historyImportFlow(choosing: Binding<Bool>) -> some View {
        modifier(HistoryImportFlow(choosing: choosing))
    }
}
