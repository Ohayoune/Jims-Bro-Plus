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
    /// D45 (v1.3): history as CSV, out and in.
    @State private var historyFile: URL?
    @State private var exportingHistory = false
    @State private var choosingHistory = false
    /// D47 (v1.4): the introduction, reopened from About.
    @State private var showIntro = false

    var body: some View {
        // D62 (v1.7): no longer a tab. The gear on Today and on History pushes it
        // (`settingsGear`), so it has no stack of its own.
        Form {
            unitsSection
            restSection
            alertsSection
            screenSection
            wordingSection
            homeSection
            dataSection
            aboutSection
        }
        .navigationTitle("Settings")
        // Pushed from Today's inline bar it would inherit an inline title; it is a place, not a
        // detail page, so it keeps the large title it had as a tab.
        .navigationBarTitleDisplayMode(.large)
        .task { await model.refreshNotificationState() }
        .sheet(isPresented: $showIntro) {
            IntroductionView(purpose: .reference, dismiss: { showIntro = false })
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
            Text("New plans use this unit unless they say otherwise. The plans you already have keep theirs.")
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
            // D59 (v1.6): the usual values in one tap; the stepper stays for the rest.
            PresetRow(values: [60, 90, 120, 180], current: model.settings.defaultRestSeconds,
                      label: { "\($0) s" }) { seconds in Task { await model.setDefaultRest(seconds) } }
            // D32 (v1.2): the warm-up before the first set.
            Stepper(value: Binding(
                get: { model.settings.warmUpSeconds },
                set: { seconds in Task { await model.setWarmUp(seconds) } }),
                    in: 0...1800, step: 60) {
                row("Warm-up", duration(model.settings.warmUpSeconds))
            }
            PresetRow(values: [0, 60, 120, 180, 300], current: model.settings.warmUpSeconds,
                      label: duration) { seconds in Task { await model.setWarmUp(seconds) } }
            // D33 (v1.2): the walk to the next machine.
            Stepper(value: Binding(
                get: { model.settings.transitionRestSeconds },
                set: { seconds in Task { await model.setTransitionRest(seconds) } }),
                    in: 0...600, step: 30) {
                row("Between exercises", duration(model.settings.transitionRestSeconds))
            }
            PresetRow(values: [0, 60, 120, 180], current: model.settings.transitionRestSeconds,
                      label: duration) { seconds in Task { await model.setTransitionRest(seconds) } }
        } footer: {
            Text("Default rest is used when a plan doesn't give a rest time. "
                 + "The warm-up runs before the first set, and \"between exercises\" is the "
                 + "walk to the next one. Set either to Off to go straight in.")
        }
    }

    /// "Off", "90 s", "5 min", "1 min 30 s" — a setting the owner reads in minutes.
    private func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Off" }
        guard seconds >= 60 else { return "\(seconds) s" }
        let minutes = seconds / 60, remainder = seconds % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) s"
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

    /// D58 (v1.6): the app writes its targets in words. This puts the notation back for
    /// someone who reads it faster than the sentence.
    private var wordingSection: some View {
        Section {
            Toggle("Compact notation", isOn: Binding(
                get: { model.settings.compactNotation },
                set: { on in Task { await model.setCompactNotation(on) } }))
        } footer: {
            Text(model.settings.compactNotation
                 ? "Targets read \"5 (4–6) · 100 kg\" and past sets read \"10 @ 100\"."
                 : "Targets read \"Aim 4–6 reps · 100 kg\" and past sets read \"10 × 100 kg\". "
                 + "Turn this on for the shorter notation.")
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
            // D35 (v1.2): the smallest change the equipment can make. Every suggestion is
            // rounded to a multiple of it, so the app never offers a weight you cannot load.
            Stepper(value: Binding(
                get: { model.settings.weightIncrement(for: model.settings.units) },
                set: { step in Task { await model.setWeightIncrement(step, for: model.settings.units) } }),
                    in: 0.5...25, step: model.settings.units == .kg ? 0.5 : 1) {
                row("Smallest change",
                    "\(TargetText.number(model.settings.weightIncrement(for: model.settings.units))) \(model.settings.units.rawValue)")
            }
        } footer: {
            Text("The − and + buttons move the weight by one step. "
                 + "Suggestions are rounded to the smallest change your equipment can make, so "
                 + "the app never suggests a weight you can't load.")
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
                    Text("Export backup")
                    Spacer()
                    if exporting { ProgressView() }
                }
            }
            .disabled(exporting)

            Button("Import backup") { choosingBackup = true }
                .disabled(restoring)

            // D45 (v1.3): the file another app can read, and the one from another app.
            Button {
                exportingHistory = true
                Task {
                    historyFile = await model.exportHistoryCSV()
                    exportingHistory = false
                }
            } label: {
                HStack {
                    Text("Export history (CSV)")
                    Spacer()
                    if exportingHistory { ProgressView() }
                }
            }
            .disabled(exportingHistory || model.sessions.isEmpty)

            Button("Import history (CSV)") { choosingHistory = true }

            Button("Delete all data", role: .destructive) { confirmDelete = true }
        } header: {
            Text("Data")
        } footer: {
            // D59 (v1.6): no Xcode in a sentence a stranger reads.
            Text("A backup is everything, for this app. History as CSV is every set, for a spreadsheet "
                 + "or another app; a CSV from Strong or Hevy imports here the same way. "
                 + "Deleting the app deletes everything, so export a backup first.")
        }
        .sheet(item: Binding(get: { backup.map(BackupFile.init(url:)) },
                             set: { backup = $0?.url })) { file in
            ShareSheet(url: file.url)
        }
        .sheet(item: Binding(get: { historyFile.map(BackupFile.init(url:)) },
                             set: { historyFile = $0?.url })) { file in
            ShareSheet(url: file.url)
        }
        .historyImportFlow(choosing: $choosingHistory)
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
            // D47 (v1.4): the introduction, for the day a friend asks.
            Button("How the app works") { showIntro = true }
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

/// D59 (v1.6): the usual values of a duration setting as small buttons, the current one tinted.
/// Five minutes of warm-up was twenty taps of a 15-second stepper.
private struct PresetRow: View {
    let values: [Int]
    let current: Int
    let label: (Int) -> String
    let choose: (Int) -> Void

    var body: some View {
        WrapLayout(spacing: 8, lineSpacing: 6) {
            ForEach(values, id: \.self) { value in
                Button(label(value)) { choose(value) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(value == current ? Color.accentColor : Color.secondary)
                    .accessibilityAddTraits(value == current ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 2)
    }
}
