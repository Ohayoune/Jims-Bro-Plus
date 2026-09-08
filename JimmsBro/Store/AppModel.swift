import Foundation
import Observation

/// D24 (v1.1): what write failed, kept as data (never silently swallowed) so the app can say so
/// and offer Retry. The failing value itself is carried along, so nothing is lost by trying.
enum SaveFailure: Equatable {
    case session(Session)
    case activeSessionWrite
    case activeSessionClear
    case plans
    case settings(Settings)
    case deleteSession(UUID)

    var message: String {
        switch self {
        case .session: return "Couldn't save the workout. It's still here — try again."
        case .activeSessionWrite: return "Couldn't save your progress. The workout keeps running; try again."
        case .activeSessionClear, .plans: return "Couldn't finish saving. Nothing was lost; try again."
        case .settings: return "Couldn't save that setting. Try again."
        case .deleteSession: return "Couldn't delete that workout. Try again."
        }
    }
}

/// The one object views read from and call into. It owns the in-memory `PlanLibrary`, mirrors
/// every change to the `Store`, and holds no view code, so all of it is unit-testable.
@MainActor @Observable final class AppModel {
    var library = PlanLibrary()
    /// Files that could not be read at launch (SPEC §8.3). The alert shows these once.
    private(set) var corruptFiles: [String] = []
    var showCorruptAlert = false
    private(set) var loaded = false

    let store: Store
    let scheduler: NotificationScheduling
    let alerts: AlertPlaying
    private let sampleJSON: () -> String?
    private let practiceJSON: () -> String?
    /// Sessions already written to disk, so completing twice doesn't rewrite them.
    var persistedSessionIds: Set<UUID> = []
    var askedForNotifications = false
    var notificationsAllowed = false
    /// What Settings shows for the notifications row.
    var notificationState: NotificationState = .notAsked
    /// Shown once if a workout starts without notification permission (SPEC §5.3).
    var showNotificationBanner = false
    /// The session that just finished. The engine is cleared the moment a workout completes,
    /// so the Summary (SPEC §4.9) needs its own hold on it until the user taps Done.
    var justCompleted: Session?
    /// D23 (v1.1): what the undone set held, handed back so the inputs come back filled with
    /// the values that were just taken away rather than with a fresh prefill (O52).
    var restoredInputs: SetResult?
    /// D24 (v1.1): the write that failed, so the app can say so and offer Retry instead of
    /// silently discarding the error and implying success.
    var saveFailure: SaveFailure?

    var settings: Settings { library.settings }
    var plans: [Plan] { library.plans }
    var sessions: [Session] { library.sessions }
    var activePlan: Plan? { library.activePlan }
    var activePlanId: UUID? { library.activePlanId }
    /// History and stats show the active plan's units, else the setting.
    var displayUnits: WeightUnit { activePlan?.units ?? settings.units }

    /// `scheduler` and `alerts` default to `SilentAlerts`, which does nothing;
    /// `JimmsBroApp` injects the system implementations, which live in Features because they
    /// need UserNotifications, AVFoundation and UIKit.
    init(store: Store,
         scheduler: NotificationScheduling = SilentAlerts(),
         alerts: AlertPlaying = SilentAlerts(),
         sampleJSON: @escaping () -> String? = AppModel.bundledSampleJSON,
         practiceJSON: @escaping () -> String? = AppModel.bundledPracticeJSON) {
        self.store = store
        self.scheduler = scheduler
        self.alerts = alerts
        self.sampleJSON = sampleJSON
        self.practiceJSON = practiceJSON
    }

    nonisolated static func bundledSampleJSON() -> String? { bundledJSON("SamplePlan") }

    /// SPEC §5.1 (D26, v1.1): the short practice workout offered next to the full sample —
    /// three straight-set exercises, one of them bodyweight, 60 s rest. It goes through the
    /// normal import pipeline like any other plan; `examples/` is untouched by it.
    nonisolated static func bundledPracticeJSON() -> String? { bundledJSON("PracticePlan") }

    nonisolated static func bundledJSON(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Launch

    func load(locale: Locale = .current, now: Date = Date()) async {
        let snapshot = await store.load(defaultSettings: .defaults(locale: locale))
        library.settings = snapshot.settings
        library.plans = snapshot.plans
        library.activePlanId = snapshot.activePlanId
        library.sessions = snapshot.sessions
        persistedSessionIds = Set(snapshot.sessions.map(\.id))
        corruptFiles = snapshot.corruptFiles
        showCorruptAlert = !snapshot.corruptFiles.isEmpty

        if let active = snapshot.active, active.phase == .completed {
            // D24 (v1.1): the session finished but the write that should have moved it into
            // `sessions/` and cleared `active-session.json` didn't finish last time. Recover it
            // as a normal session rather than resuming a "completed" workout or losing it.
            if !library.sessions.contains(where: { $0.id == active.session.id }) {
                library.sessions.append(active.session)
            }
            await trySaveSession(active.session)
            await tryClearActiveSession()
        } else {
            library.engine = snapshot.active.map {
                SessionEngine(active: $0, settings: snapshot.settings, history: snapshot.sessions)
            }
        }
        // First launch: the defaults we just chose become the file (N10).
        if !snapshot.hasSettingsFile {
            do { try await store.save(settings: library.settings) } catch { saveFailure = .settings(library.settings) }
        }
        loaded = true
    }

    var startCard: StartCard { StartCard.current(library: library) }
    func startCard(now: Date, calendar: Calendar = .current) -> StartCard {
        StartCard.current(library: library, now: now, calendar: calendar)
    }

    // MARK: - Import

    func runImport(_ text: String, now: Date = Date()) -> ImportResult {
        PlanImport.run(text, settings: settings, now: now)
    }

    /// Returns nil when a name conflict was cancelled; otherwise the saved plan's id.
    @discardableResult
    func save(_ plan: Plan, conflict: ConflictChoice = .cancel, makeActive: Bool = false) async -> UUID? {
        let id = library.save(plan, conflict: conflict, makeActive: makeActive)
        if id != nil { await persistPlans() }
        return id
    }

    func conflict(for plan: Plan) -> Plan? { library.conflict(for: plan) }

    /// D29 (v1.1): applies one edit to a plan, through the import pipeline. Returns the errors
    /// that stopped it, or an empty array when it went through; the plan keeps its id and its
    /// active status, so nothing else in the app has to notice that it changed.
    @discardableResult
    func editPlan(_ id: UUID, _ operation: PlanEdit.Operation, now: Date = Date()) async -> [Issue] {
        guard let index = library.plans.firstIndex(where: { $0.id == id }) else {
            return [Issue(severity: .error, code: "E_EDIT_INVALID", path: "",
                          message: "That plan no longer exists.")]
        }
        let result = PlanEdit.apply(operation, to: library.plans[index], settings: settings, now: now)
        guard let edited = result.plan else { return result.issues.filter { $0.severity == .error } }
        library.plans[index] = edited
        await persistPlans()
        return []
    }

    /// Plan detail's Replace action (D25 v1.1): replaces the plan at `id` outright, keeping its
    /// id and, if it was active, keeping it active. Returns nil if `id` no longer exists.
    @discardableResult
    func replacePlan(_ id: UUID, with plan: Plan) async -> UUID? {
        let result = library.replace(id, with: plan)
        if result != nil { await persistPlans() }
        return result
    }

    /// Home's "Try the sample plan" (O1): import the bundled plan and make it active.
    @discardableResult
    func importSamplePlan(now: Date = Date()) async -> ImportResult {
        await importBundled(sampleJSON(), what: "sample plan", now: now)
    }

    /// Home's "Try a short practice workout" (D26, v1.1): the same path, a smaller plan.
    @discardableResult
    func importPracticePlan(now: Date = Date()) async -> ImportResult {
        await importBundled(practiceJSON(), what: "practice plan", now: now)
    }

    private func importBundled(_ text: String?, what: String, now: Date) async -> ImportResult {
        guard let text else {
            return ImportResult(plan: nil, issues: [Issue(
                severity: .error, code: "E_NO_SAMPLE", path: "",
                message: "The \(what) is missing from the app bundle.")])
        }
        let result = runImport(text, now: now)
        if let plan = result.plan { await save(plan, conflict: .keepBoth, makeActive: true) }
        return result
    }

    // MARK: - Plans

    func setActivePlan(_ id: UUID) async {
        guard plans.contains(where: { $0.id == id }) else { return }
        library.activePlanId = id
        await persistPlans()
    }

    func renamePlan(_ id: UUID, to name: String) async {
        guard let index = library.plans.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return }
        library.plans[index].name = trimmed
        await persistPlans()
    }

    func deletePlan(_ id: UUID) async {
        library.deletePlan(id)
        await persistPlans()
    }

    func persistPlans() async {
        do { try await store.save(plans: library.plans, activePlanId: library.activePlanId) }
        catch { saveFailure = .plans }
    }

    // MARK: - History

    /// Editing a past session recomputes its advice and rewrites just that file (O15).
    func editHistorySession(_ id: UUID, step: Int, result: SetResult, now: Date = Date()) async {
        library.editSession(id, step: step, result: result, now: now)
        guard let edited = library.sessions.first(where: { $0.id == id }) else { return }
        await trySaveSession(edited)
    }

    /// SPEC §4.5 (v1.1): Rename exercise moved out of the workout menu into Session detail.
    func renameHistoryExercise(_ id: UUID, exerciseIndex: Int, name: String) async {
        library.renameExercise(id, exerciseIndex: exerciseIndex, name: name)
        guard let edited = library.sessions.first(where: { $0.id == id }) else { return }
        await trySaveSession(edited)
    }

    func deleteHistorySession(_ id: UUID) async {
        library.deleteSession(id)
        persistedSessionIds.remove(id)
        do { try await store.deleteSession(id: id) } catch { saveFailure = .deleteSession(id) }
    }

    var historyMonths: [HistoryMonth] { HistoryGrouping.months(sessions) }

    func history(for name: String, units: WeightUnit) -> [ExercisePoint] {
        ExerciseHistory(sessions: sessions).series(name: name, units: units)
    }

    // MARK: - Settings

    /// Changing units never rewrites existing plans; it only affects the prompt and future
    /// imports that don't state their own units (N9).
    func setUnits(_ units: WeightUnit) async { await update { $0.units = units } }
    func setDefaultRest(_ seconds: Int) async {
        await update { $0.defaultRestSeconds = max(0, min(3600, seconds)) }
    }
    /// D32 (v1.2): 0 turns the warm-up off; 30 min is the ceiling, past which it is not a
    /// warm-up but a workout of its own.
    func setWarmUp(_ seconds: Int) async { await update { $0.warmUpSeconds = max(0, min(1800, seconds)) } }
    /// D33 (v1.2): 0 restores v1.1's "move straight on".
    func setTransitionRest(_ seconds: Int) async {
        await update { $0.transitionRestSeconds = max(0, min(600, seconds)) }
    }
    func setSound(_ on: Bool) async { await update { $0.sound = on } }
    func setVibration(_ on: Bool) async { await update { $0.vibration = on } }
    func setKeepAwake(_ on: Bool) async { await update { $0.keepAwake = on } }
    /// The step is per unit, so switching units doesn't silently change the other one.
    func setWeightStep(_ step: Double, for units: WeightUnit) async {
        let clamped = min(100, max(0.1, (step * 10).rounded() / 10))
        await update { units == .kg ? ($0.weightStepKg = clamped) : ($0.weightStepLb = clamped) }
    }

    /// D35 (v1.2): the smallest weight change the equipment allows, per unit.
    func setWeightIncrement(_ step: Double, for units: WeightUnit) async {
        let clamped = min(50, max(0.1, (step * 10).rounded() / 10))
        await update { units == .kg ? ($0.weightIncrementKg = clamped) : ($0.weightIncrementLb = clamped) }
    }

    private func update(_ change: (inout Settings) -> Void) async {
        var settings = library.settings
        change(&settings)
        guard settings != library.settings else { return }
        library.settings = settings
        library.engine?.settings = settings
        do { try await store.save(settings: settings) } catch { saveFailure = .settings(settings) }
    }

    func dismissCorruptAlert() { showCorruptAlert = false }

    // MARK: - Save failure (D24, v1.1)

    /// Saves a session and only marks it "already persisted" once the write actually succeeds.
    @discardableResult
    func trySaveSession(_ session: Session) async -> Bool {
        do { try await store.save(session: session) } catch { saveFailure = .session(session); return false }
        persistedSessionIds.insert(session.id)
        return true
    }

    /// Clears `active-session.json` — only call this once every completed session it referred
    /// to is confirmed on disk.
    func tryClearActiveSession() async {
        do { try await store.clearActiveSession() } catch { saveFailure = .activeSessionClear }
    }

    /// Retries a failed write. The data itself was never discarded, so this is always safe to
    /// call again, including automatically on the next successful write.
    ///
    /// `failure` is passed in by the alert's Retry button, which captures it synchronously:
    /// dismissing the alert clears `saveFailure` first, so a Retry that read the property
    /// inside its own `Task` would always find nil and do nothing (D24, v1.2).
    func retrySaveFailure(_ failure: SaveFailure? = nil) async {
        guard let failure = failure ?? saveFailure else { return }
        saveFailure = nil
        switch failure {
        case let .session(session):
            guard await trySaveSession(session) else { return }
            // Mirrors persistCompletedSessions' tail: only once everything is confirmed on disk.
            if library.sessions.allSatisfy({ persistedSessionIds.contains($0.id) }) {
                await tryClearActiveSession()
                await persistPlans()
            }
        case .activeSessionWrite:
            do { try await persistActiveSession() } catch { saveFailure = .activeSessionWrite }
        case .activeSessionClear:
            await tryClearActiveSession()
        case .plans:
            await persistPlans()
        case let .settings(settings):
            do { try await store.save(settings: settings) } catch { saveFailure = .settings(settings) }
        case let .deleteSession(id):
            do { try await store.deleteSession(id: id) } catch { saveFailure = .deleteSession(id) }
        }
    }

    // MARK: - Data

    /// SPEC §4.11: everything goes, and the app carries on with defaults rather than relaunching.
    func deleteAllData(locale: Locale = .current) async {
        await cancelAllAlerts()
        try? await store.deleteAll()
        library = PlanLibrary()
        library.settings = .defaults(locale: locale)
        persistedSessionIds = []
        justCompleted = nil
        corruptFiles = []
        showCorruptAlert = false
        try? await store.save(settings: library.settings)
    }

    // MARK: - Restore (D31, v1.1)

    /// The backup being considered, and what it holds. Nothing is applied until the user picks
    /// Replace all or Merge.
    struct PendingRestore: Equatable {
        var document: ExportDocument
        var summary: BackupSummary
    }

    /// What `readBackup` found: a backup to decide about, or why it isn't one.
    enum BackupRead: Equatable {
        case read(PendingRestore)
        case failed(String)
    }

    /// Reads a backup file and returns what is in it, changing nothing. A file that isn't a
    /// backup comes back as a message rather than as a throw the caller has to catch — the
    /// user picked a file, they did not make a programming error.
    func readBackup(at url: URL) async -> BackupRead {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            return .failed("That file couldn't be read.")
        }
        do {
            let (document, summary) = try await store.readBackup(data)
            return .read(PendingRestore(document: document, summary: summary))
        } catch let error as StoreError {
            return .failed(error.message)
        } catch {
            return .failed("That file isn't a Jimm's Bro+ backup.")
        }
    }

    /// Applies a backup and reloads from disk, so the app shows exactly what was written.
    func restore(_ pending: PendingRestore, mode: RestoreMode, locale: Locale = .current) async -> String? {
        // A running workout would be describing a session the store is about to replace.
        if hasActiveSession { await discardSession() }
        do {
            try await store.restore(pending.document, mode: mode)
        } catch {
            // Replace all empties the store before it writes, so a failure part-way through
            // has already changed things. Saying otherwise would be a comforting lie about
            // the one mode where it matters.
            let message = RestoreText.failure(mode)
            loaded = false
            justCompleted = nil
            await load(locale: locale)
            return message
        }
        loaded = false
        justCompleted = nil
        await load(locale: locale)
        return nil
    }

    /// SPEC §8.5: the backup written to a temp file for ShareLink.
    func exportBackup(now: Date = Date()) async -> URL? {
        try? await store.exportFile(appVersion: AppModel.appVersion, now: now)
    }

    nonisolated static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = info?["CFBundleVersion"] as? String, build != version else { return version }
        return "\(version) (\(build))"
    }

    func refreshNotificationState() async { notificationState = await scheduler.authorizationState() }

    /// Waits for the launch read to finish, for the DEBUG screenshot hooks that need a loaded
    /// model before they navigate. Bounded and cancellation-aware: an unbounded `while !loaded`
    /// spins the main actor for ever if its task is cancelled before the load lands.
    func waitUntilLoaded(timeout: Duration = .seconds(10)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !loaded, ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }
}
