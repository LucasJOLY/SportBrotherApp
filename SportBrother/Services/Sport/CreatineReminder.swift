import Foundation
import UserNotifications

/// Rappel quotidien à 22 h 30 pour ne pas oublier la créatine.
enum CreatineReminder {
    private static let notificationID = "sport.creatine"

    /// Idempotent : même identifiant, la demande remplace la précédente.
    static func schedule() async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Créatine"
        content.body = "N'oublie pas ta créatine avant de dormir."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 22, minute: 30), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }
}
