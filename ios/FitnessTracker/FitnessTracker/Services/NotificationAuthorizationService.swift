import UserNotifications

/// Asks for notification access only after the user enables a feature that
/// needs it. Opening the app never triggers the system permission prompt.
@MainActor
enum NotificationAuthorizationService {
    static func requestIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
