// Gzowo Concierge for macOS - native notification when the morning brief is ready; clicking it opens the brief conversation.
import Foundation
import UserNotifications

@MainActor
final class BriefNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (String) -> Void = { _ in }
    private let seenKey = "briefSeenTs"

    func start() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(ts: Double, text: String, thread: String) {
        guard ts > 0 else { return }
        let d = UserDefaults.standard
        guard d.object(forKey: seenKey) != nil else { d.set(ts, forKey: seenKey); return }
        guard ts > d.double(forKey: seenKey) else { return }
        d.set(ts, forKey: seenKey)
        let content = UNMutableNotificationContent()
        content.title = "Poranny brief"
        content.body = Self.summary(text)
        content.sound = .default
        content.userInfo = ["thread": thread]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "brief-\(Int(ts))", content: content, trigger: nil))
    }

    private static func summary(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return plain.count <= 170 ? plain : String(plain.prefix(167)) + "…"
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let thread = response.notification.request.content.userInfo["thread"] as? String ?? "poranny-brief"
        await MainActor.run { onOpen(thread) }
    }
}
