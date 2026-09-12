import AppKit
import UserNotifications
import TibometerCore

@MainActor
final class LocalNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var authorization: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    var statusText: String {
        switch authorization {
        case .authorized, .provisional: return L10n.text("notification.authorized")
        case .denied: return L10n.text("notification.denied")
        default: return L10n.text("notification.undetermined")
        }
    }

    func refreshPermission() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshPermission()
    }

    func send(_ event: ResetEvent, sound: Bool, isTest: Bool = false) async throws -> LocalizedMessage {
        await refreshPermission()
        guard authorization == .authorized || authorization == .provisional else {
            return "notification.unauthorized"
        }
        let content = UNMutableNotificationContent()
        content.title = isTest ? L10n.text("notification.test_title") : event.notificationTitle
        content.subtitle = isTest ? "" : event.window.title
        content.body = isTest ? L10n.text("notification.test_body") : event.message
        if sound { content.sound = .default }
        content.threadIdentifier = "tibometer.quota-resets"
        try await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
        return "notification.submitted"
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}
