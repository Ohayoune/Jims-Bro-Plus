import SwiftUI
import UIKit

/// SPEC §6.61 (D88, v1.11): the Ask state's bottom slot, on every chatbot screen. **Send the
/// prompt**, the accent button, opens iOS's share sheet with the prompt as text — the ChatGPT
/// app and the Claude app take shared text into a new message, and Copy is a row of the sheet
/// for a chatbot in a browser — and **Copy the prompt** beneath it, quieter, copies (J1). Either
/// calls `sent`, which is what moves the caller to Paste.
///
/// The titles are Core's (`TripButtons.ask`), so a screen with more than one prompt names which
/// — *Send the outline prompt*, *Send the prompt for Pull* (D91).
struct PromptButtons: View {
    let text: String
    /// The share sheet's subject, for the apps that take one (Mail, Notes).
    let subject: String
    var buttons: TripButtons = .ask()
    let sent: () -> Void

    @State private var sharing = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                sharing = true
            } label: {
                Label(buttons.primary, systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let secondary = buttons.secondary {
                Button {
                    Clipboard.write(text)
                    sent()
                } label: {
                    Label(secondary, systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .background(SharePresenter(isPresented: $sharing, text: text, subject: subject, closed: sent))
    }
}

/// Presents the system share sheet over the screen and reports when it closes. A sheet that was
/// presented counts as sent, shared or cancelled alike (the plan's reading of D88): the owner who
/// cancels finds Paste with nothing to paste, and the ··· has Send the prompt again. It is
/// reported when the sheet *closes* rather than when it opens, because the caller answers `sent`
/// by drawing Paste in place of these buttons, and a share sheet tied to a view that has gone —
/// as a `ShareLink`'s is — would close under the thumb.
private struct SharePresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let text: String
    let subject: String
    let closed: () -> Void

    final class Coordinator { var presenting = false }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        // One sheet per tap: SwiftUI may update the host again before the sheet is up.
        guard isPresented, !context.coordinator.presenting else { return }
        context.coordinator.presenting = true
        let sheet = UIActivityViewController(activityItems: [PromptItem(text: text, subject: subject)],
                                             applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = host.view
        sheet.completionWithItemsHandler = { [coordinator = context.coordinator] _, _, _, _ in
            coordinator.presenting = false
            isPresented = false
            closed()
        }
        DispatchQueue.main.async { host.present(sheet, animated: true) }
    }
}

/// The prompt as plain text, with a subject for the apps that ask for one.
private final class PromptItem: NSObject, UIActivityItemSource {
    let text: String
    let subject: String

    init(text: String, subject: String) {
        self.text = text
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { text }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { text }

    func activityViewController(_ controller: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String { subject }
}
