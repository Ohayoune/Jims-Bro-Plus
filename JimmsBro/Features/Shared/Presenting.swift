import SwiftUI
import UIKit

/// D96 (v1.12 L6): what a screen presents, written once — an optional as a presentation's flag,
/// the alert that only says why, the system share sheet, and the question a start asks while a
/// workout is open. Each was typed out by every screen that needed it.

extension Binding where Value == Bool {
    /// Whether `source` holds a value, for an alert or a sheet: dismissing it clears the value.
    init<Wrapped>(isPresent source: Binding<Wrapped?>) {
        self.init(get: { source.wrappedValue != nil },
                  set: { if !$0 { source.wrappedValue = nil } })
    }
}

extension View {
    /// D29: a refusal said in words, with OK — up while `message` holds one, cleared by OK.
    func problemAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(isPresent: message)) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// The system share sheet, over this view, with `items`; `closed` runs when it closes,
    /// shared or cancelled alike. The prompt's Send (D88) and Settings' backup and CSV use it.
    func shareSheet(isPresented: Binding<Bool>, items: [Any], closed: @escaping () -> Void = {}) -> some View {
        background(SharePresenter(isPresented: isPresented, items: items, closed: closed))
    }

    /// D17: starting a workout while one is open asks, with the same three answers everywhere —
    /// Keep going, Finish and start, Discard and start. Up while `pending` holds the start that
    /// was refused; `start` runs it again with the answer.
    func switchWorkoutAlert<Pending>(_ pending: Binding<Pending?>, open: Session?,
                                     start: @escaping (Pending, SessionSwitch) -> Void) -> some View {
        func take(_ choice: SessionSwitch) {
            guard let refused = pending.wrappedValue else { return }
            pending.wrappedValue = nil
            start(refused, choice)
        }
        return alert(SessionSwitch.prompt(open), isPresented: Binding(isPresent: pending)) {
            Button("Keep going", role: .cancel) { pending.wrappedValue = nil }
            Button("Finish and start") { take(.finish) }
            Button("Discard and start", role: .destructive) { take(.discard) }
        }
    }
}

/// D17, D48: a start run, and a refusal because a workout is open held in `pending`, which raises
/// `switchWorkoutAlert`. The refusal is thrown before anything changes; any other failure clears
/// the question rather than leaving it up.
@MainActor
func beginWorkout<Pending>(_ refused: Pending, asking pending: Binding<Pending?>,
                           _ start: @escaping () async throws -> Void) {
    Task {
        do {
            try await start()
        } catch LibraryError.sessionInProgress {
            pending.wrappedValue = refused
        } catch {
            pending.wrappedValue = nil
        }
    }
}

/// Presents the system share sheet over the screen and reports when it closes. It is reported
/// when the sheet *closes* rather than when it opens, because the prompt's caller answers by
/// drawing Paste in place of its buttons, and a share sheet tied to a view that has gone — as a
/// `ShareLink`'s is — would close under the thumb (D88). Settings' backup and CSV, which exist
/// only after an await, are shared the same way; until v1.12 they had a second sheet of their own.
private struct SharePresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]
    let closed: () -> Void

    final class Coordinator { var presenting = false }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        // One sheet per tap: SwiftUI may update the host again before the sheet is up.
        guard isPresented, !items.isEmpty, !context.coordinator.presenting else { return }
        context.coordinator.presenting = true
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = host.view
        sheet.completionWithItemsHandler = { [coordinator = context.coordinator] _, _, _, _ in
            coordinator.presenting = false
            isPresented = false
            closed()
        }
        DispatchQueue.main.async { host.present(sheet, animated: true) }
    }
}
