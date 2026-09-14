import Foundation

/// Everything read off disk at launch, plus the names of any files that could not be decoded.
struct StoreSnapshot: Equatable {
    var settings = Settings()
    var plans: [Plan] = []
    var activePlanId: UUID?
    var sessions: [Session] = []
    var active: ActiveSession?
    /// D52 (v1.5): the plan being built day by day, if one was left mid-way.
    var draft: PlanDraft?
    /// D72 (v1.9): the day swaps; a missing `swaps.json` is none.
    var swaps: [DaySwap] = []
    var corruptFiles: [String] = []
    /// False on a first launch, so the caller knows to write the defaults it just used (N10).
    var hasSettingsFile = false
}

/// The one place that touches the filesystem (SPEC §8.2). Every write is atomic; nothing here
/// ever throws its way into a crash on bad input — unreadable files are set aside, never deleted.
actor Store {
    let root: URL
    private let manager = FileManager.default

    init(root: URL) { self.root = root }

    #if DEBUG
    static let refusesWrites = ProcessInfo.processInfo.arguments.contains("-uiReadOnlyStore")
    #endif

    /// `<Application Support>/JimmsBro/`.
    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("JimmsBro", isDirectory: true)
    }

    var settingsURL: URL { root.appendingPathComponent("settings.json") }
    var plansURL: URL { root.appendingPathComponent("plans.json") }
    /// D72 (v1.9): the day swaps, beside the plans.
    var swapsURL: URL { root.appendingPathComponent("swaps.json") }
    var activeSessionURL: URL { root.appendingPathComponent("active-session.json") }
    /// D52 (v1.5): present only while a plan is being built day by day.
    var draftURL: URL { root.appendingPathComponent("draft.json") }
    // `goals.json` (D54, v1.5–v1.7) is no longer read or written: D68 removed goals. A file left
    // by those versions stays where it is, unread, until Delete all data removes the folder.
    var sessionsDirectory: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    func sessionURL(_ id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Loading

    /// Reads every file. Anything that fails to decode is renamed aside and treated as absent.
    ///
    /// `settingAsideCorruptFiles` is false for the read-only callers (export, backup inspection,
    /// restore): setting a file aside is a change the user is told about through the launch
    /// alert, and doing it as a side effect of exporting would move a file with nothing on
    /// screen to say so.
    func load(defaultSettings: Settings = .defaults(),
              settingAsideCorruptFiles: Bool = true) -> StoreSnapshot {
        var snapshot = StoreSnapshot(settings: defaultSettings)
        setsAsideCorruptFiles = settingAsideCorruptFiles
        defer { setsAsideCorruptFiles = true }
        try? manager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        if let settings: Settings = read(settingsURL, into: &snapshot) {
            snapshot.settings = settings
            snapshot.hasSettingsFile = true
        }
        if let plans: PlansPayload = read(plansURL, into: &snapshot) {
            snapshot.plans = plans.plans
            snapshot.activePlanId = plans.activePlanId
        }
        if let swaps: SwapsPayload = read(swapsURL, into: &snapshot) {
            snapshot.swaps = swaps.swaps
        }
        if let active: ActiveSession = read(activeSessionURL, into: &snapshot) {
            snapshot.active = active
        }
        if let draft: PlanDraft = read(draftURL, into: &snapshot) {
            snapshot.draft = draft
        }
        let files = (try? manager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let session: Session = read(file, into: &snapshot) { snapshot.sessions.append(session) }
        }
        snapshot.sessions.sort { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        snapshot.corruptFiles.sort()
        return snapshot
    }

    /// Whether the current `load` may rename unreadable files. See `load(defaultSettings:_:)`.
    private var setsAsideCorruptFiles = true

    /// Returns nil when the file is absent, and sets it aside when it is present but unreadable.
    private func read<T: Codable>(_ url: URL, into snapshot: inout StoreSnapshot) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try StoreCoder.decode(T.self, from: data)
        } catch {
            guard setsAsideCorruptFiles else {
                snapshot.corruptFiles.append(relativeName(url))
                return nil
            }
            if let name = setAside(url) { snapshot.corruptFiles.append(name) }
            return nil
        }
    }

    /// Renames to `<name>.corrupt-<unixtime>` and returns the path relative to the store root.
    @discardableResult private func setAside(_ url: URL) -> String? {
        let stamp = Int(Date().timeIntervalSince1970)
        let directory = url.deletingLastPathComponent()
        var target = directory.appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        var suffix = 2
        while manager.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)-\(suffix)")
            suffix += 1
        }
        // Read the name first: resolving a path that no longer exists gives a different answer.
        let name = relativeName(url)
        guard (try? manager.moveItem(at: url, to: target)) != nil else { return nil }
        return name
    }

    /// Resolves symlinks on both sides: directory enumeration hands back resolved paths
    /// (`/private/var/...`) even when the root was built from `/var/...`.
    private func relativeName(_ url: URL) -> String {
        let base = root.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(base + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(base.count + 1))
    }

    // MARK: - Writing

    func save(settings: Settings) throws { try write(StoreCoder.encode(settings), to: settingsURL) }

    func save(plans: [Plan], activePlanId: UUID?) throws {
        try write(StoreCoder.encode(PlansPayload(activePlanId: activePlanId, plans: plans)), to: plansURL)
    }

    /// D72 (v1.9): the day swaps, written whenever one is added, answered or deleted.
    func save(swaps: [DaySwap]) throws {
        try write(StoreCoder.encode(SwapsPayload(swaps: swaps)), to: swapsURL)
    }

    func save(activeSession: ActiveSession) throws {
        try write(StoreCoder.encode(activeSession), to: activeSessionURL)
    }

    func clearActiveSession() throws { try remove(activeSessionURL) }

    /// D52 (v1.5): the draft, written after every paste and removed when the plan is saved.
    func save(draft: PlanDraft) throws { try write(StoreCoder.encode(draft), to: draftURL) }
    func clearDraft() throws { try remove(draftURL) }

    func save(session: Session) throws {
        try write(StoreCoder.encode(session), to: sessionURL(session.id))
    }

    /// The completed workout becomes a session file and stops being the active one (SPEC §8.1).
    func complete(session: Session) throws {
        try save(session: session)
        try clearActiveSession()
    }

    func deleteSession(id: UUID) throws { try remove(sessionURL(id)) }

    /// Removes the whole store directory and recreates it empty.
    func deleteAll() throws {
        if manager.fileExists(atPath: root.path) { try manager.removeItem(at: root) }
        try manager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    /// Encode fully into memory first, then swap the file in one step, so a failure anywhere
    /// leaves the previous file untouched and never leaves a partial one behind.
    private func write(_ data: Data, to url: URL) throws {
        #if DEBUG
        // D24, device check H33: `-uiReadOnlyStore` makes every write fail, so the save-failure
        // alert and its Retry can be exercised on a real phone. It refuses rather than damaging
        // the store, so running it against real data cannot lose any; relaunching without the
        // argument makes Retry succeed. Compiled out of release builds entirely.
        if Store.refusesWrites { throw StoreError.writesRefusedForTesting }
        #endif
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp)
            try protect(temp)
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temp)
            } else {
                try manager.moveItem(at: temp, to: url)
            }
            try protect(url)
        } catch {
            try? manager.removeItem(at: temp)
            throw error
        }
    }

    /// Background writes must not fail on a locked phone (SPEC §8.1).
    private func protect(_ url: URL) throws {
        #if os(iOS)
        try manager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
        #endif
    }

    private func remove(_ url: URL) throws {
        guard manager.fileExists(atPath: url.path) else { return }
        try manager.removeItem(at: url)
    }

    // MARK: - Export

    func exportData(appVersion: String, now: Date = Date()) -> Data? {
        let snapshot = load(defaultSettings: Settings(), settingAsideCorruptFiles: false)
        let document = ExportDocument(exportedAt: now, appVersion: appVersion,
                                      settings: snapshot.settings, plans: snapshot.plans,
                                      sessions: snapshot.sessions,
                                      activePlanId: snapshot.activePlanId,
                                      swaps: snapshot.swaps)
        return try? StoreCoder.encoder.encode(document)
    }

    // MARK: - Restore (D31, v1.1)

    /// Decodes a backup and says what is in it, without changing anything. A file that isn't a
    /// backup, or is from a newer app, is refused here rather than half-applied.
    func readBackup(_ data: Data) throws -> (document: ExportDocument, summary: BackupSummary) {
        let document: ExportDocument
        do {
            document = try StoreCoder.decoder.decode(ExportDocument.self, from: data)
        } catch {
            throw StoreError.notABackup
        }
        guard document.fileVersion <= storeFileVersion else {
            throw StoreError.unsupportedFileVersion(document.fileVersion)
        }
        let snapshot = load(defaultSettings: Settings(), settingAsideCorruptFiles: false)
        let knownSessions = Set(snapshot.sessions.map(\.id))
        let knownPlans = Set(snapshot.plans.map(\.id))
        return (document, BackupSummary(
            exportedAt: document.exportedAt,
            appVersion: document.appVersion,
            plans: document.plans.count,
            sessions: document.sessions.count,
            newPlans: document.plans.filter { !knownPlans.contains($0.id) }.count,
            newSessions: document.sessions.filter { !knownSessions.contains($0.id) }.count))
    }

    /// Whether a failure of `mode` can leave the store part-way through the restore.
    /// `replaceAll` deletes before it writes, so it can; `merge` only ever adds.
    static func isDestructive(_ mode: RestoreMode) -> Bool { mode == .replaceAll }

    /// Applies a backup. `replaceAll` empties the store first and takes the backup's settings;
    /// `merge` adds only what isn't already here by id and leaves the current settings alone —
    /// a merge must never quietly overwrite a workout you edited since the backup was made.
    func restore(_ document: ExportDocument, mode: RestoreMode) throws {
        let snapshot = load(defaultSettings: Settings(), settingAsideCorruptFiles: false)
        switch mode {
        case .replaceAll:
            try deleteAll()
            try manager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
            try save(settings: document.settings)
            try save(plans: document.plans, activePlanId: document.activePlanId ?? document.plans.first?.id)
            // D72 (v1.9): a backup from before swaps restores with none.
            try save(swaps: document.swaps ?? [])
            for session in document.sessions { try save(session: session) }
        case .merge:
            let knownPlans = Set(snapshot.plans.map(\.id))
            let knownSessions = Set(snapshot.sessions.map(\.id))
            let knownSwaps = Set(snapshot.swaps.map(\.id))
            let plans = snapshot.plans + document.plans.filter { !knownPlans.contains($0.id) }
            try save(plans: plans, activePlanId: snapshot.activePlanId ?? document.activePlanId)
            let added = (document.swaps ?? []).filter { !knownSwaps.contains($0.id) }
            if !added.isEmpty { try save(swaps: snapshot.swaps + added) }
            for session in document.sessions where !knownSessions.contains(session.id) {
                try save(session: session)
            }
        }
    }

    /// Writes the backup to a temp file for ShareLink and returns it.
    func exportFile(appVersion: String, now: Date = Date()) throws -> URL {
        guard let data = exportData(appVersion: appVersion, now: now) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JimmsBro-backup.json")
        try? manager.removeItem(at: url)
        try data.write(to: url)
        return url
    }
}
