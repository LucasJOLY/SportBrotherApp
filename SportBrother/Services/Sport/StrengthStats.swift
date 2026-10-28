import Foundation

nonisolated struct SetValue: Hashable, Sendable {
    var weight: Double
    var reps: Int
}

/// Ce qu'un profil a fait sur un exo lors d'une séance.
nonisolated struct Performance: Hashable, Sendable {
    let sessionID: UUID
    let day: Date
    let sets: [SetValue]

    var best: SetValue? { sets.max { StrengthStats.oneRepMax($0) < StrengthStats.oneRepMax($1) } }
    var topWeight: Double { sets.map(\.weight).max() ?? 0 }
    var volume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
}

nonisolated enum StrengthStats {
    static let recordReps = [1, 3, 5, 8, 10, 12]

    /// 1RM estimé (Epley). Une seule rep = le poids lui-même.
    static func oneRepMax(_ set: SetValue) -> Double {
        guard set.reps > 0 else { return 0 }
        return set.reps == 1 ? set.weight : set.weight * (1 + Double(set.reps) / 30)
    }

    /// Nombre de reps à partir duquel une charge compte comme « charge de travail » réussie.
    static let workingReps = 6

    /// Plus lourde charge de la séance tenue sur au moins `workingReps` reps (nil si aucune série ne les atteint).
    static func workingMax(_ performance: Performance, minReps: Int = workingReps) -> Double? {
        performance.sets.filter { $0.reps >= minReps && $0.weight > 0 }.map(\.weight).max()
    }

    /// Poids de corps à une date : la dernière pesée avant, sinon la première après.
    static func bodyWeight(on day: Date, weighIns: [(day: Date, kg: Double)]) -> Double? {
        let sorted = weighIns.sorted { $0.day < $1.day }
        return (sorted.last { $0.day <= day } ?? sorted.first)?.kg
    }

    struct Record: Hashable {
        let reps: Int
        let weight: Double
        let day: Date
    }

    /// Meilleur poids réussi pour au moins N reps, pour chaque N du tableau des records.
    static func records(_ performances: [Performance]) -> [Record] {
        recordReps.compactMap { target in
            var best: Record?
            for performance in performances {
                for set in performance.sets where set.reps >= target && set.weight > 0 {
                    if set.weight > (best?.weight ?? 0) { best = Record(reps: target, weight: set.weight, day: performance.day) }
                }
            }
            return best
        }
    }

    /// Record battu par cette série, comparé à tout l'historique précédent du profil sur l'exo.
    /// Avec charge : plus lourd qu'avant à nombre de reps égal ou supérieur. Poids du corps : plus de reps qu'avant.
    static func isRecord(_ set: SetValue, previous: [Performance]) -> Bool {
        guard set.reps > 0, !previous.isEmpty else { return false }
        let history = previous.flatMap(\.sets)
        if set.weight == 0 {
            return set.reps > (history.filter { $0.weight == 0 }.map(\.reps).max() ?? 0)
        }
        let best = history.filter { $0.reps >= set.reps }.map(\.weight).max() ?? 0
        return set.weight > best
    }
}

/// Suggestion discrète pour la séance du jour, jamais imposée.
nonisolated enum Progression: Equatable, Sendable {
    case addWeight(Double)
    case addRep

    var label: String {
        switch self {
        case .addWeight(let kg): "Tente +\(Format.kg(kg))"
        case .addRep: "Tente +1 rep"
        }
    }

    static let step = 2.5

    /// Toutes les séries de la dernière fois ont atteint le haut de la fourchette : on monte.
    static func suggestion(last: Performance?, repRangeHigh: Int, isBodyweight: Bool) -> Progression? {
        guard let last, !last.sets.isEmpty, last.sets.allSatisfy({ $0.reps >= repRangeHigh }) else { return nil }
        return isBodyweight || last.topWeight == 0 ? .addRep : .addWeight(step)
    }

    /// Valeur proposée pour la série `index` : la même série la dernière fois, sinon la série d'avant aujourd'hui.
    static func prefill(index: Int, last: Performance?, today: [SetValue]) -> SetValue {
        if let last, !last.sets.isEmpty { return last.sets[min(index, last.sets.count - 1)] }
        return today.last ?? SetValue(weight: 0, reps: 10)
    }
}

/// Groupes musculaires pas travaillés depuis plus d'une semaine.
nonisolated enum NeglectedGroups {
    static let threshold = 7

    static func compute(lastTrained: [MuscleGroup: Date], now: Date = .now) -> [(group: MuscleGroup, days: Int)] {
        let calendar = Calendar.current
        return lastTrained
            .map { group, day in
                (group, calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)).day ?? 0)
            }
            .filter { $0.1 > threshold }
            .sorted { $0.1 > $1.1 }
    }
}

/// Index en mémoire de l'historique (séances terminées ou en cours, séries validées), construit à partir du cache local.
struct SportHistory {
    struct Key: Hashable {
        let profileID: UUID
        let exerciseRef: String
    }

    private(set) var performances: [Key: [Performance]] = [:]
    /// Jours de séance par profil.
    private(set) var days: [UUID: Set<Date>] = [:]

    init(sessions: [SportSession], entries: [SportEntry], sets: [SportSet]) {
        let calendar = Calendar.current
        let liveSessions = Dictionary(
            sessions.filter { $0.deletedAt == nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let liveEntries = Dictionary(
            entries.filter { $0.deletedAt == nil && liveSessions[$0.sessionID] != nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var grouped: [Key: [UUID: [SportSet]]] = [:]
        for set in sets where set.deletedAt == nil && set.isDone {
            guard let entry = liveEntries[set.entryID] else { continue }
            grouped[Key(profileID: set.profileID, exerciseRef: entry.exerciseRef), default: [:]][entry.sessionID, default: []].append(set)
        }
        for (key, bySession) in grouped {
            for sessionID in bySession.keys {
                if let session = liveSessions[sessionID] {
                    days[key.profileID, default: []].insert(calendar.startOfDay(for: session.day))
                }
            }
            performances[key] = bySession.compactMap { sessionID, sets in
                guard let session = liveSessions[sessionID] else { return nil }
                return Performance(
                    sessionID: sessionID,
                    day: session.day,
                    sets: sets.sorted { $0.index < $1.index }.map { SetValue(weight: $0.weightKg, reps: $0.reps) }
                )
            }
            .sorted { ($0.day, $0.sessionID.uuidString) < ($1.day, $1.sessionID.uuidString) }
        }
    }

    func performances(profile: UUID, exercise: String) -> [Performance] {
        performances[Key(profileID: profile, exerciseRef: exercise)] ?? []
    }

    /// Dernière fois sur cet exo, hors séance en cours.
    func last(profile: UUID, exercise: String, excluding sessionID: UUID?) -> Performance? {
        performances(profile: profile, exercise: exercise).last { $0.sessionID != sessionID }
    }

    /// Historique antérieur à la séance en cours (pour détecter un record).
    func previous(profile: UUID, exercise: String, excluding sessionID: UUID?) -> [Performance] {
        performances(profile: profile, exercise: exercise).filter { $0.sessionID != sessionID }
    }

    func exercises(profile: UUID) -> [String] {
        performances.keys.filter { $0.profileID == profile }.map(\.exerciseRef)
    }

    func lastTrained(profile: UUID, groups: [String: MuscleGroup]) -> [MuscleGroup: Date] {
        var result: [MuscleGroup: Date] = [:]
        for (key, list) in performances where key.profileID == profile {
            guard let group = groups[key.exerciseRef], let day = list.last?.day else { continue }
            if day > (result[group] ?? .distantPast) { result[group] = day }
        }
        return result
    }
}

extension Format {
    /// « 62,5 kg », « 60 kg ».
    nonisolated static func kg(_ value: Double) -> String {
        "\(number(value)) kg"
    }

    nonisolated static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "fr_FR")))
    }
}
