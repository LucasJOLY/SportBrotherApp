import ActivityKit
import Foundation
import SwiftData
import UIKit
import UserNotifications

/// État d'une session de cuisson : chrono global avec pause, minuteurs d'étape, Live Activity.
@Observable
final class CookingController {
    let recipe: Recipe
    let slot: MealSlot?
    /// Nombre de personnes choisi au lancement (la recette est écrite pour 2).
    let servings: Int
    private(set) var session: CookingSession
    private(set) var pausedAt: Date?
    var currentStep = 0 { didSet { updateActivity() } }
    var completedSteps: Set<UUID> = []
    /// Fin prévue de chaque minuteur d'étape lancé.
    private(set) var stepTimers: [UUID: Date] = [:]
    private var activity: Activity<CookingActivityAttributes>?

    init(recipe: Recipe, slot: MealSlot?, servings: Int = QuantityScaler.baseServings, context: ModelContext) {
        self.recipe = recipe
        self.slot = slot
        self.servings = servings
        let session = CookingSession(recipe: recipe, slotID: slot?.id)
        context.insert(session)
        self.session = session
        UIApplication.shared.isIdleTimerDisabled = true
        startActivity()
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at date: Date) -> TimeInterval {
        let reference = pausedAt ?? date
        return max(0, reference.timeIntervalSince(session.startedAt) - session.pausedSeconds)
    }

    func togglePause() {
        if let pausedAt {
            let pause = Date.now.timeIntervalSince(pausedAt)
            session.pausedSeconds += pause
            stepTimers = stepTimers.mapValues { $0.addingTimeInterval(pause) }
            self.pausedAt = nil
            rescheduleNotifications()
        } else {
            pausedAt = .now
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        updateActivity()
    }

    // MARK: Minuteurs d'étape

    func startTimer(for step: RecipeStep) {
        guard step.durationMinutes > 0 else { return }
        stepTimers[step.id] = .now.addingTimeInterval(TimeInterval(step.durationMinutes * 60))
        Task { await requestNotificationPermission() }
        rescheduleNotifications()
        updateActivity()
    }

    func cancelTimer(for step: RecipeStep) {
        stepTimers[step.id] = nil
        rescheduleNotifications()
        updateActivity()
    }

    /// Minuteurs en cours ou terminés non arrêtés, du plus proche au plus lointain.
    var activeTimers: [(index: Int, step: RecipeStep, end: Date)] {
        recipe.steps.enumerated()
            .compactMap { index, step in stepTimers[step.id].map { (index, step, $0) } }
            .sorted { $0.end < $1.end }
    }

    func remaining(for step: RecipeStep, at date: Date) -> TimeInterval? {
        guard let end = stepTimers[step.id] else { return nil }
        return max(0, end.timeIntervalSince(isPaused ? pausedAt ?? date : date))
    }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func rescheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard !isPaused else { return }
        for step in recipe.steps {
            guard let end = stepTimers[step.id], end > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = recipe.title
            content.body = "Minuteur terminé : \(step.text)"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
            center.add(UNNotificationRequest(identifier: step.id.uuidString, content: content, trigger: trigger))
        }
    }

    // MARK: Fin

    /// Termine la session, coche le créneau et enregistre la note.
    func finish(rating: Int?, context: ModelContext) {
        if isPaused { togglePause() }
        session.endedAt = .now
        if let rating { recipe.rating = rating }
        recipe.lastCookedAt = .now
        if let slot { WeekPlanner(context: context).setStatus(.done, for: slot) }
        close()
    }

    /// Abandon sans enregistrer de statistique.
    func cancel(context: ModelContext) {
        context.delete(session)
        close()
    }

    private func close() {
        UIApplication.shared.isIdleTimerDisabled = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let activity = activity
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: Live Activity

    private var activityState: CookingActivityAttributes.ContentState {
        let steps = recipe.steps
        let step = steps.indices.contains(currentStep) ? steps[currentStep] : nil
        let nextTimer = stepTimers.values.filter { $0 > .now }.min()
        return .init(
            elapsedAnchor: session.startedAt.addingTimeInterval(session.pausedSeconds),
            isPaused: isPaused,
            pausedElapsed: elapsed(at: .now),
            stepLabel: step == nil ? "" : "Étape \(currentStep + 1)/\(steps.count)",
            stepTimerEnd: isPaused ? nil : nextTimer
        )
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: CookingActivityAttributes(recipeTitle: recipe.title),
            content: .init(state: activityState, staleDate: nil)
        )
    }

    private func updateActivity() {
        guard let activity else { return }
        let state = activityState
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }
}
