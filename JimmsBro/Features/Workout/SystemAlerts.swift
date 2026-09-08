import Foundation
import UserNotifications
import AVFoundation
import UIKit

/// The real notification centre. Kept out of Core so the engine and AppModel stay testable.
final class SystemNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationState() async -> NotificationState {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        default: return .allowed
        }
    }

    func schedule(_ request: NotificationRequest) async {
        // A date in the past can't fire, and UNTimeIntervalTrigger rejects intervals <= 0.
        let interval = request.date.timeIntervalSinceNow
        guard interval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = request.sound == .warning
            ? UNNotificationSound(named: UNNotificationSoundName("warning.caf"))
            : .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: request.id.rawValue, content: content, trigger: trigger))
    }

    func cancel(ids: [AlertIdentifier]) async {
        let names = ids.map(\.rawValue)
        center.removePendingNotificationRequests(withIdentifiers: names)
        center.removeDeliveredNotifications(withIdentifiers: names)
    }
}

/// SPEC §6.4: the audio session is activated only for the duration of the beep, with
/// `.mixWithOthers` and `.duckOthers`, so music keeps playing and the beep is audible on silent.
/// With the sound setting off, the audio session is never touched at all.
final class SystemAlertPlayer: AlertPlaying, @unchecked Sendable {
    private var players: [TimerBeep: AVAudioPlayer] = [:]
    private let lock = NSLock()

    func play(_ beep: TimerBeep, sound: Bool, vibration: Bool) {
        if vibration { Task { @MainActor in Self.haptic(beep) } }
        guard sound else { return }
        Task { self.playSound(beep) }
    }

    /// A logged set gets `.success` and nothing audible: it confirms a tap, it is not a clock.
    func play(feedback: Feedback, vibration: Bool) {
        guard vibration else { return }
        Task { @MainActor in UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    @MainActor private static func haptic(_ beep: TimerBeep) {
        switch beep {
        case .end:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning, .minimum:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func playSound(_ beep: TimerBeep) {
        guard let player = player(for: beep) else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
        player.currentTime = 0
        player.play()
        // Release the session once the clip is done, so ducking is momentary.
        let duration = player.duration + 0.2
        Task {
            try? await Task.sleep(for: .seconds(duration))
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func player(for beep: TimerBeep) -> AVAudioPlayer? {
        lock.withLock {
            if let existing = players[beep] { return existing }
            let name = beep == .end ? "beep" : "warning"
            let url = Bundle.main.url(forResource: name, withExtension: name == "beep" ? "wav" : "caf")
                ?? Bundle.main.url(forResource: "beep", withExtension: "wav")
            guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            player.volume = beep == .end ? 1.0 : 0.6
            player.prepareToPlay()
            players[beep] = player
            return player
        }
    }
}
