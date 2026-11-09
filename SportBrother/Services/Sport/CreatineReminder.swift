import Foundation
import UserNotifications

/// Rappel quotidien à 22 h 30 pour ne pas oublier la créatine, relancé une heure plus tard tant que
/// « C'est pris » n'a pas été touché sur la notification.
/// iOS ne réveille pas l'app à l'arrivée d'une notification : la relance est donc programmée d'avance,
/// jour par jour sur deux semaines, et retirée quand la prise est validée.
enum CreatineReminder {
    nonisolated static let category = "sport.creatine"
    nonisolated static let takenAction = "sport.creatine.taken"
    static let time = DateComponents(hour: 22, minute: 30)
    static let followUpDelay: TimeInterval = 3600

    private static let prefix = "sport.creatine."
    private static let legacyID = "sport.creatine"
    private static let takenKey = "creatineTakenDays"
    private static let daysAhead = 14

    /// Bouton « C'est pris » sous la notification, géré sans ouvrir l'app.
    static func registerCategory() {
        let taken = UNNotificationAction(identifier: takenAction, title: "C'est pris", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [taken], intentIdentifiers: []),
        ])
    }

    /// Idempotent : remplace tout ce qui était programmé, en sautant les soirs déjà validés.
    static func schedule(now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) || $0 == legacyID }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let taken = takenDays()
        for request in requests(from: now, taken: taken) {
            try? await center.add(request)
        }
    }

    /// Prise validée depuis la notification (l'identifiant porte le jour du rappel) : la relance de ce soir saute.
    static func markTaken(notificationID: String) async {
        guard let day = day(in: notificationID) else { return }
        var days = takenDays().filter { $0 >= dayKey(Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now) }
        days.insert(day)
        UserDefaults.standard.set(Array(days), forKey: takenKey)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id(day, .followUp)])
        center.removeDeliveredNotifications(withIdentifiers: [id(day, .reminder), id(day, .followUp)])
    }

    // MARK: Calendrier

    enum Kind: String { case reminder, followUp = "relance" }

    /// Rappel et relance pour chaque soir à venir non validé, uniquement dans le futur.
    static func requests(from now: Date, taken: Set<String>, calendar: Calendar = .current) -> [UNNotificationRequest] {
        (0..<daysAhead).flatMap { offset -> [UNNotificationRequest] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let reminder = calendar.date(bySettingHour: time.hour ?? 22, minute: time.minute ?? 30, second: 0, of: day)
            else { return [] }
            let key = dayKey(day, calendar: calendar)
            guard !taken.contains(key) else { return [] }
            return [
                (Kind.reminder, reminder, "N'oublie pas ta créatine avant de dormir."),
                (Kind.followUp, reminder.addingTimeInterval(followUpDelay), "Toujours pas prise ? C'est le moment."),
            ]
            .filter { $0.1 > now }
            .map { kind, date, body in
                let content = UNMutableNotificationContent()
                content.title = "Créatine"
                content.body = body
                content.sound = .default
                content.categoryIdentifier = category
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                return UNNotificationRequest(
                    identifier: id(key, kind),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            }
        }
    }

    static func id(_ day: String, _ kind: Kind) -> String { "\(prefix)\(day).\(kind.rawValue)" }

    static func day(in notificationID: String) -> String? {
        guard notificationID.hasPrefix(prefix) else { return nil }
        let parts = notificationID.dropFirst(prefix.count).split(separator: ".")
        return parts.count == 2 ? String(parts[0]) : nil
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func takenDays() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: takenKey) ?? [])
    }
}

/// Reçoit le bouton « C'est pris », y compris app fermée (iOS la lance en arrière-plan le temps de traiter).
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationResponder()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == CreatineReminder.takenAction else { return }
        let id = response.notification.request.identifier
        await CreatineReminder.markTaken(notificationID: id)
    }

    /// App ouverte : on affiche le rappel créatine, les autres notifications restent discrètes comme avant.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == CreatineReminder.category ? [.banner, .list, .sound] : []
    }
}
