import SwiftUI

@main
struct JimmsBroApp: App {
    @State private var model = JimmsBroApp.makeModel()

    var body: some Scene {
        WindowGroup { RootView(model: model) }
    }

    @MainActor private static func makeModel() -> AppModel {
        #if DEBUG
        // Screenshot runs stay silent, so no system permission prompt appears.
        if ProcessInfo.processInfo.arguments.contains("-uiNoAlerts") {
            let silent = SilentAlerts()
            return AppModel(store: makeStore(), scheduler: silent, alerts: silent,
                            activities: NoActivities())
        }
        #endif
        // D40 (v1.2): the Lock Screen and Dynamic Island activity.
        return AppModel(store: makeStore(),
                        scheduler: SystemNotificationScheduler(),
                        alerts: SystemAlertPlayer(),
                        activities: SystemActivityPresenter())
    }

    /// Application Support (SPEC §8.1); a temp directory only if that is somehow unavailable,
    /// so a first launch degrades instead of crashing.
    private static func makeStore() -> Store {
        let root = (try? Store.defaultRoot())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("JimmsBro")
        return Store(root: root)
    }
}
