import ActivityKit
import Foundation

/// Repos entre deux séries, affiché sur l'écran verrouillé et la Dynamic Island.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var endsAt: Date
        var exercise: String
        var detail: String
    }

    var startedAt: Date
}
