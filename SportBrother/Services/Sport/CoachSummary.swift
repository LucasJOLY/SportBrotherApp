import Foundation

/// Régularité calculée sur les jours de séance.
nonisolated enum Regularity {
    /// Semaines consécutives avec au moins une séance, en comptant la semaine en cours si elle en a déjà une.
    static func weekStreak(_ days: Set<Date>, now: Date = .now) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let weeks = Set(days.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(week) { week = calendar.date(byAdding: .weekOfYear, value: -1, to: week) ?? week }
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        }
        return streak
    }

    /// Séances par semaine sur les `weeks` dernières semaines.
    static func perWeek(_ days: Set<Date>, weeks: Int = 12, now: Date = .now) -> Double {
        let start = Calendar.current.date(byAdding: .day, value: -7 * weeks, to: now) ?? now
        return Double(days.filter { $0 > start && $0 <= now }.count) / Double(weeks)
    }
}

/// Bilan chiffré du mois écoulé, en quelques lignes : c'est tout ce que l'IA reçoit.
nonisolated enum CoachSummary {
    struct ExerciseTrend {
        let name: String
        let group: MuscleGroup
        let sessions: Int
        let first: Double
        let last: Double
    }

    static func make(
        name: String,
        days: Set<Date>,
        groupSessions: [MuscleGroup: Int],
        trends: [ExerciseTrend],
        neglected: [(group: MuscleGroup, days: Int)],
        bodyWeight: (now: Double, delta: Double)?,
        now: Date = .now
    ) -> String {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let recent = days.filter { $0 > monthAgo }.count
        var lines = [
            "Profil : \(name).",
            "Séances sur 30 jours : \(recent). Moyenne sur 12 semaines : \(Format.number(Regularity.perWeek(days, now: now)))/semaine. "
                + "Semaines d'affilée : \(Regularity.weekStreak(days, now: now)).",
        ]
        if let bodyWeight {
            lines.append("Poids : \(Format.kg(bodyWeight.now)) (\(bodyWeight.delta >= 0 ? "+" : "")\(Format.number(bodyWeight.delta)) kg en 60 jours).")
        }
        let groups = MuscleGroup.allCases.map { "\($0.label) \(groupSessions[$0] ?? 0)" }
        lines.append("Séances par groupe sur 30 jours : \(groups.joined(separator: ", ")).")
        if !trends.isEmpty {
            let items = trends.prefix(10).map { trend in
                let status = abs(trend.last - trend.first) < 1 && trend.sessions >= 3 ? ", plateau" : ""
                return "\(trend.name) \(Int(trend.first))→\(Int(trend.last)) kg (\(trend.sessions) séances\(status))"
            }
            lines.append("1RM estimé sur 60 jours : \(items.joined(separator: " ; ")).")
        }
        if !neglected.isEmpty {
            lines.append("Pas travaillé depuis : \(neglected.map { "\($0.group.label) \($0.days) j" }.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }
}
