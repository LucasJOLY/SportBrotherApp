import Foundation

/// Calculs des statistiques de cuisine, indépendants de SwiftData pour rester testables.
nonisolated enum CookingStats {
    struct WeekScore: Hashable, Sendable {
        let weekStart: Date
        let done: Int
        let planned: Int
        var ratio: Double { planned == 0 ? 0 : Double(done) / Double(planned) }
    }

    /// Une semaine est « respectée » quand au moins 80 % des repas prévus sont faits.
    static let threshold = 0.8

    /// Semaines respectées d'affilée, en remontant depuis la plus récente.
    /// La semaine en cours ne casse pas la série tant qu'elle n'est pas finie.
    static func streak(_ weeks: [WeekScore], currentWeekStart: Date) -> Int {
        var count = 0
        var expected: Date?
        for week in weeks.sorted(by: { $0.weekStart > $1.weekStart }) where week.planned > 0 {
            if week.weekStart == currentWeekStart && week.ratio < threshold { continue }
            if let expected, abs(week.weekStart.timeIntervalSince(expected)) > 2 * 86_400 { break }
            guard week.ratio >= threshold else { break }
            count += 1
            expected = WeekCalendar.calendar.date(byAdding: .day, value: -7, to: week.weekStart)
        }
        return count
    }

    /// Premier et dernier temps réel d'une recette chronométrée au moins deux fois.
    static func progression(_ durations: [(date: Date, seconds: TimeInterval)]) -> (first: TimeInterval, last: TimeInterval)? {
        let sorted = durations.sorted { $0.date < $1.date }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return nil }
        return (first.seconds, last.seconds)
    }
}
