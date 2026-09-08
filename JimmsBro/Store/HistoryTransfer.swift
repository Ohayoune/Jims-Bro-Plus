import Foundation

/// SPEC §6.20 (D45, v1.3): history out as a CSV another app can read, and a CSV from another
/// app read in — described before anything is written, exactly as a backup is (D31).
extension AppModel {
    /// The file being considered, and what it holds. Nothing is applied until Import is tapped.
    struct PendingHistoryImport: Equatable {
        var sessions: [Session]
        var summary: HistoryCSV.Summary
    }

    enum HistoryRead: Equatable {
        case read(PendingHistoryImport)
        case failed(String)
    }

    /// Reads a CSV and says what is in it, changing nothing. A file that cannot be read comes
    /// back as a sentence rather than a throw — the user picked a file, they did not make a
    /// programming error.
    func readHistoryCSV(at url: URL) async -> HistoryRead {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            return .failed("The file couldn't be opened.")
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return .failed("The file isn't text.")
        }
        return read(csv: text)
    }

    /// The same, from text already in hand — what the tests call, and what a paste would.
    func read(csv text: String) -> HistoryRead {
        let parsed = HistoryCSV.parse(text, defaultUnits: settings.units)
        if let error = parsed.errors.first { return .failed(error.message) }
        return .read(PendingHistoryImport(sessions: parsed.sessions,
                                          summary: HistoryCSV.Summary.of(parsed, existing: sessions)))
    }

    /// Adds the workouts the app does not already have, one file each, and surfaces a failed
    /// write the way any other save does (D24). The sessions are already in memory before
    /// the first write, so nothing read is lost if a write fails partway.
    func importHistory(_ pending: PendingHistoryImport) async {
        let fresh = HistoryCSV.new(pending.sessions, against: library.sessions)
        for session in fresh {
            library.sessions.append(session)
            guard await trySaveSession(session) else { return }
        }
    }

    /// Every logged set, as a file to hand to a spreadsheet or another app.
    func exportHistoryCSV() async -> URL? {
        let text = HistoryCSV.render(sessions)
        return try? await store.exportHistoryFile(text)
    }
}

extension Store {
    /// Writes the CSV to a temp file for the share sheet and returns it.
    func exportHistoryFile(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JimmsBro-history.csv")
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}
