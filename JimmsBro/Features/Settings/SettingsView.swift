import SwiftUI
import UniformTypeIdentifiers

/// SPEC §4.11, in full.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var backup: URL?
    @State private var confirmDelete = false
    @State private var exporting = false
    /// D31 (v1.1): restoring a backup — read, say what is in it, then ask what to do with it.
    @State private var choosingBackup = false
    @State private var pending: AppModel.PendingRestore?
    @State private var restoreError: String?
    @State private var restoring = false

    var body: some View {
        NavigationStack {
            Form {
                unitsSection
                restSection
                alertsSection
                screenSection
                homeSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task { await model.refreshNotificationState() }
        }
    }

    // MARK: - Sections

    private var unitsSection: some View {
        Section {
            Picker("Units", selection: Binding(
                get: { model.settings.units },
                set: { units in Task { await model.setUnits(units) } })) {
                ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Only affects the prompt and future imports that don't state their own units.")
        }
    }

    private var restSection: some View {
        Section {
            Stepper(value: Binding(
                get: { model.settings.defaultRestSeconds },
                set: { seconds in Task { await model.setDefaultRest(seconds) } }),
                    in: 0...600, step: 15) {
                row("Default rest", "\(model.settings.defaultRestSeconds) s")
            }
        } footer: {
            Text("Used when a plan doesn't give a rest time.")
        }
    }

    private var alertsSection: some View {
        Section {
            Toggle("Sound", isOn: Binding(get: { model.settings.sound },
                                          set: { on in Task { await model.setSound(on) } }))
            Toggle("Vibration", isOn: Binding(get: { model.settings.vibration },
                                              set: { on in Task { await model.setVibration(on) } }))
            LabeledContent("Notifications", value: model.notificationState.label)
            if model.notificationState == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } footer: {
            if let explanation = model.notificationState.explanation {
                Text(explanation)
            } else {
                Text("Rest and set timers alert you even when the phone is locked.")
            }
        }
    }

    private var screenSection: some View {
        Section {
            Toggle("Keep screen awake", isOn: Binding(
                get: { model.settings.keepAwake },
                set: { on in Task { await model.setKeepAwake(on) } }))
        } footer: {
            Text("During a workout only. The screen locks normally everywhere else.")
        }
    }

    private var homeSection: some View {
        Section {
            Stepper(value: Binding(
                get: { model.settings.weightStep(for: model.settings.units) },
                set: { step in Task { await model.setWeightStep(step, for: model.settings.units) } }),
                    in: 0.5...50, step: model.settings.units == .kg ? 0.5 : 1) {
                row("Weight step",
                    "\(TargetText.number(model.settings.weightStep(for: model.settings.units))) \(model.settings.units.rawValue)")
            }
        } footer: {
            Text("The − and + buttons move the weight by one step.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                exporting = true
                Task {
                    backup = await model.exportBackup()
                    exporting = false
                }
            } label: {
                HStack {
                    Text("Export")
                    Spacer()
                    if exporting { ProgressView() }
                }
            }
            .disabled(exporting)

            Button("Import backup") { choosingBackup = true }
                .disabled(restoring)

            Button("Delete all data", role: .destructive) { confirmDelete = true }
        } header: {
            Text("Data")
        } footer: {
            Text("Re-running from Xcode over the existing install keeps your data. Deleting the app deletes everything.")
        }
        .sheet(item: Binding(get: { backup.map(BackupFile.init(url:)) },
                             set: { backup = $0?.url })) { file in
            ShareSheet(url: file.url)
        }
        .confirmationDialog("Delete every plan, workout and setting?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { Task { await model.deleteAllData() } }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            Task {
                switch await model.readBackup(at: url) {
                case let .read(found): pending = found
                case let .failed(message): restoreError = message
                }
            }
        }
        // The file is only read at this point — nothing is written until one of these is tapped.
        .confirmationDialog(restorePrompt, isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let pending {
                Button("Merge") { restore(pending, .merge) }
                Button("Replace all", role: .destructive) { restore(pending, .replaceAll) }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text(restoreDetail)
        }
        .alert("That backup wasn't restored", isPresented: Binding(
            get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("OK", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }

    private var restorePrompt: String {
        guard let summary = pending?.summary else { return "Restore this backup?" }
        return "Backup from \(summary.exportedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    /// Says what each choice would actually do, in counts, before either is tapped.
    private var restoreDetail: String {
        guard let summary = pending?.summary else { return "" }
        let holds = "It holds \(summary.plans) plan\(summary.plans == 1 ? "" : "s") "
            + "and \(summary.sessions) workout\(summary.sessions == 1 ? "" : "s")."
        let merge = summary.newPlans == 0 && summary.newSessions == 0
            ? "Merge would add nothing — you already have all of it."
            : "Merge adds \(summary.newPlans) plan\(summary.newPlans == 1 ? "" : "s") "
              + "and \(summary.newSessions) workout\(summary.newSessions == 1 ? "" : "s"), "
              + "and changes nothing you already have."
        return "\(holds) \(merge) Replace all deletes everything here first."
    }

    private func restore(_ pending: AppModel.PendingRestore, _ mode: RestoreMode) {
        self.pending = nil
        restoring = true
        Task {
            restoreError = await model.restore(pending, mode: mode)
            restoring = false
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Jimm's Bro+", value: AppModel.appVersion)
            LabeledContent("Plans", value: "\(model.plans.count)")
            LabeledContent("Workouts", value: "\(model.sessions.count)")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

private struct BackupFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// ShareLink can't take a URL that only exists after an await, so the sheet wraps the system one.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
