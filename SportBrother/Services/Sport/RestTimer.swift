import ActivityKit
import Foundation
import UserNotifications

/// Repos lancé à chaque série validée : un compte à rebours par personne, pour qu'à plusieurs
/// le repos de l'un n'écrase pas celui de l'autre. Chacun a sa notification de fin et sa Live Activity.
@Observable
final class RestTimer {
    struct Rest: Identifiable, Equatable {
        /// Profil qui se repose.
        let id: UUID
        var endsAt: Date
        var exercise: String
        var detail: String
    }

    /// Dans l'ordre de lancement : une ligne ne saute pas de place quand on ajuste son temps.
    private(set) var timers: [Rest] = []
    /// Incrémenté à la fin d'un repos, pour le retour haptique dans l'app.
    private(set) var finishedCount = 0
    private var activities: [UUID: Activity<RestActivityAttributes>] = [:]
    private var endTasks: [UUID: Task<Void, Never>] = [:]

    private static let notificationPrefix = "sport.rest"

    var isRunning: Bool { !timers.isEmpty }

    /// Relance le repos de cette personne ; ceux des autres continuent.
    func start(seconds: Int, profile: UUID, exercise: String, detail: String) {
        guard seconds > 0 else { return }
        let rest = Rest(id: profile, endsAt: .now.addingTimeInterval(TimeInterval(seconds)), exercise: exercise, detail: detail)
        if let index = timers.firstIndex(where: { $0.id == profile }) {
            timers[index] = rest
        } else {
            timers.append(rest)
        }
        schedule(rest)
    }

    func add(_ seconds: Int, to profile: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == profile }) else { return }
        timers[index].endsAt = max(.now, timers[index].endsAt).addingTimeInterval(TimeInterval(seconds))
        schedule(timers[index])
    }

    func skip(_ profile: UUID) {
        endTasks.removeValue(forKey: profile)?.cancel()
        timers.removeAll { $0.id == profile }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID(profile)])
        let activity = activities.removeValue(forKey: profile)
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
    }

    /// Fin de séance : plus aucun repos.
    func skipAll() {
        for rest in timers { skip(rest.id) }
    }

    private static func notificationID(_ profile: UUID) -> String { "\(notificationPrefix).\(profile.uuidString)" }

    private func schedule(_ rest: Rest) {
        notify(rest)
        updateActivity(rest)
        endTasks[rest.id]?.cancel()
        endTasks[rest.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(rest.endsAt.timeIntervalSinceNow))
            guard !Task.isCancelled, let self else { return }
            self.finishedCount += 1
            self.skip(rest.id)
        }
    }

    private func notify(_ rest: Rest) {
        let center = UNUserNotificationCenter.current()
        let id = Self.notificationID(rest.id)
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            center.removePendingNotificationRequests(withIdentifiers: [id])
            let content = UNMutableNotificationContent()
            content.title = "Repos terminé"
            content.body = "Série suivante : \(rest.exercise)"
            // À plusieurs, le détail commence par le prénom : on sait à qui c'est.
            if rest.detail.contains(" · ") { content.subtitle = rest.detail }
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = Self.notificationPrefix
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, rest.endsAt.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private func updateActivity(_ rest: Rest) {
        let state = RestActivityAttributes.ContentState(endsAt: rest.endsAt, exercise: rest.exercise, detail: rest.detail)
        let content = ActivityContent(state: state, staleDate: rest.endsAt.addingTimeInterval(60))
        if let activity = activities[rest.id] {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activities[rest.id] = try? Activity.request(attributes: RestActivityAttributes(startedAt: .now), content: content)
        }
    }
}
