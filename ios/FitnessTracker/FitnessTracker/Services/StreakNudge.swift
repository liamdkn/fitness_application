import Foundation
import UserNotifications

/// The streak-at-risk reminder: at 21:30, when there's a streak to keep and today doesn't look on
/// plan yet. A plain function so the timing and wording can be checked without a notification
/// centre. (This replaces the coach's "log incomplete" nudge - never both.)
nonisolated enum StreakNudgePlan {
    static let minutes = 21 * 60 + 30

    struct Reminder: Equatable {
        let fireDate: Date
        let title: String
        let body: String
    }

    /// Nothing when there's no streak to keep, today already looks on plan, today is a sick day,
    /// or 21:30 has passed.
    static func reminder(streak: Int, provisionalToday: Bool, sickToday: Bool, now: Date, calendar: Calendar = .current) -> Reminder? {
        guard streak > 0, !provisionalToday, !sickToday else { return nil }
        let fireDate = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(minutes * 60))
        guard fireDate > now.addingTimeInterval(60) else { return nil }
        return Reminder(
            fireDate: fireDate,
            title: "Streak",
            body: "\u{1F525} \(streak)-day streak. Log the rest of today to keep it."
        )
    }
}

/// Keeps today's streak reminder in step with today's real log. A local notification can't
/// re-check anything when it fires, so each `refresh` replaces the pending one: when the app
/// opens, comes back to the foreground, or the Dashboard reloads.
@MainActor
final class StreakNudgeService {
    static let shared = StreakNudgeService()
    static let enabledKey = "streak-nudge-enabled"
    private let identifier = "streak-at-risk"

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func refresh(streak: Int, provisionalToday: Bool, sickToday: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled,
              let reminder = StreakNudgePlan.reminder(streak: streak, provisionalToday: provisionalToday, sickToday: sickToday, now: Date())
        else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
