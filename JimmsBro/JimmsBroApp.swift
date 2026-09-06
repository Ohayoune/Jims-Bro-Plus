import SwiftUI

@main
struct JimmsBroApp: App {
    @State private var model = JimmsBroApp.makeModel()

    var body: some Scene {
        WindowGroup { RootView(model: model) }
    }

    @MainActor private static func makeModel() -> AppModel {
        #if DEBUG
        // Screenshot runs use the inert recorder, so no system permission prompt appears.
        if ProcessInfo.processInfo.arguments.contains("-uiNoAlerts") {
            let recorder = RecordingAlerts()
            return AppModel(store: makeStore(), scheduler: recorder, alerts: recorder)
        }
        #endif
        return AppModel(store: makeStore(),
                        scheduler: SystemNotificationScheduler(),
                        alerts: SystemAlertPlayer())
    }

    /// Application Support (SPEC §8.1); a temp directory only if that is somehow unavailable,
    /// so a first launch degrades instead of crashing.
    private static func makeStore() -> Store {
        let root = (try? Store.defaultRoot())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("JimmsBro")
        return Store(root: root)
    }
}
