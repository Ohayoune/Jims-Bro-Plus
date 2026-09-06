import UIKit

/// The one place that touches the pasteboard, so views stay free of UIKit.
enum Clipboard {
    static func write(_ text: String) { UIPasteboard.general.string = text }
}
