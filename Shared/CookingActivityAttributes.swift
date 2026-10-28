import ActivityKit
import Foundation

nonisolated struct CookingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Début du chrono décalé du temps de pause : `Text(elapsedAnchor, style: .timer)` affiche le temps actif.
        var elapsedAnchor: Date
        var isPaused: Bool
        var pausedElapsed: TimeInterval
        var stepLabel: String
        var stepTimerEnd: Date?
    }

    var recipeTitle: String
}
