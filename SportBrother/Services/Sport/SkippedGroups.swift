import Foundation

/// Grands groupes musculaires délaissés : au démarrage d'une séance, l'app râle pour chaque groupe
/// pas travaillé depuis une semaine ou plus.
enum SkippedGroups {
    static let threshold = 7

    struct Skip: Hashable {
        let group: MuscleGroup
        /// Jours depuis la dernière série faite sur ce groupe (ou depuis la première séance s'il n'a jamais été fait).
        let days: Int
        let never: Bool
    }

    /// Groupes pas faits depuis `threshold` jours, du plus délaissé au moins délaissé.
    /// Un profil sans aucune séance n'a rien à se reprocher.
    static func skipped(
        profile: UUID,
        history: SportHistory,
        groups: [String: MuscleGroup],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [Skip] {
        guard let first = history.days[profile]?.min() else { return [] }
        let lastByGroup = history.lastTrained(profile: profile, groups: groups)
        let start = calendar.startOfDay(for: today)
        func days(since date: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: start).day ?? 0
        }
        return MuscleGroup.allCases.compactMap { group -> Skip? in
            let last = lastByGroup[group]
            let elapsed = days(since: last ?? first)
            return elapsed >= threshold ? Skip(group: group, days: elapsed, never: last == nil) : nil
        }
        .sorted { ($0.days, $1.group.rawValue) > ($1.days, $0.group.rawValue) }
    }

    /// Le savon, adapté au groupe.
    static func message(_ skip: Skip) -> String {
        let of = switch skip.group {
        case .jambes: "de jambes"
        case .dos: "de dos"
        case .pecs: "de pecs"
        case .epaules: "d'épaules"
        case .biceps: "de biceps"
        case .triceps: "de triceps"
        case .abdos: "d'abdos"
        }
        let rant = switch skip.group {
        case .jambes: "T'as skip les jambes, c'est inadmissible. Tu veux finir en poulet ?"
        case .dos: "T'as skip le dos, c'est inadmissible. Ça se tire, un dos."
        case .pecs: "T'as skip les pecs, c'est inadmissible. Le banc t'attend."
        case .epaules: "T'as skip les épaules, c'est inadmissible. Fini les excuses."
        case .biceps: "T'as skip les biceps, c'est inadmissible. Même eux, t'as oublié ?"
        case .triceps: "T'as skip les triceps, c'est inadmissible. C'est les deux tiers du bras."
        case .abdos: "T'as skip les abdos, c'est inadmissible. Gaine-toi."
        }
        let since = skip.never ? "Aucune série \(of) en \(skip.days) jours." : "\(skip.days) jours sans série \(of)."
        return "\(since) \(rant)"
    }
}
