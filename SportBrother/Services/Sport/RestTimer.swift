import ActivityKit
import Foundation
import UserNotifications

/// Repos lancé à chaque série validée : compte à rebours, notification de fin, Live Activity.
@Observable
final class RestTimer {
    private(set) var endsAt: Date?
    private(set) var exercise = ""
    /// Incrémenté à la fin du repos, pour le retour haptique dans l'app.
    private(set) var finishedCount = 0
    private var activity: Activity<RestActivityAttributes>?
    private var endTask: Task<Void, Never>?

    private static let notificationID = "sport.rest"

    var isRunning: Bool { (endsAt ?? .distantPast) > .now }

    func start(seconds: Int, exercise: String, detail: String) {
        guard seconds > 0 else { return }
        self.exercise = exercise
        schedule(end: .now.addingTimeInterval(TimeInterval(seconds)), detail: detail)
    }

    func add(_ seconds: Int) {
        guard let endsAt else { return }
        schedule(end: max(.now, endsAt).addingTimeInterval(TimeInterval(seconds)), detail: nil)
    }

    func skip() {
        endTask?.cancel()
        endsAt = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        let activity = activity
        self.activity = nil
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
    }

    private var detail = ""

    private func schedule(end: Date, detail: String?) {
        if let detail { self.detail = detail }
        endsAt = end
        notify(at: end)
        updateActivity(end: end)
        endTask?.cancel()
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled, let self else { return }
            self.finishedCount += 1
            self.skip()
        }
    }

    private func notify(at end: Date) {
        let center = UNUserNotificationCenter.current()
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
            let content = UNMutableNotificationContent()
            content.title = "Repos terminé"
            content.body = "Série suivante : \(exercise)"
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
        }
    }

    private func updateActivity(end: Date) {
        let state = RestActivityAttributes.ContentState(endsAt: end, exercise: exercise, detail: detail)
        let content = ActivityContent(state: state, staleDate: end.addingTimeInterval(60))
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: RestActivityAttributes(startedAt: .now), content: content)
        }
    }
}
