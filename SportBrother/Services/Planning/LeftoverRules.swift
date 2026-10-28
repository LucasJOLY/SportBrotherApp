import Foundation

nonisolated struct LeftoverSlot: Hashable, Sendable {
    let order: Int
    let diners: Int
    /// Ce créneau mange déjà le reste d'un autre.
    let isLeftover: Bool
    /// Ce créneau envoie déjà son reste ailleurs.
    let sendsLeftover: Bool
}

/// Quand on est seul, on cuisine pour 2 : le reste nourrit un créneau suivant où l'on est seul.
nonisolated enum LeftoverRules {
    static func producesLeftover(_ slot: LeftoverSlot) -> Bool {
        slot.diners == 1 && !slot.isLeftover
    }

    /// Créneaux suivants pouvant recevoir le reste de `source`, du plus proche au plus lointain.
    static func candidates(for source: LeftoverSlot, in slots: [LeftoverSlot]) -> [Int] {
        guard producesLeftover(source) else { return [] }
        return slots
            .filter { $0.order > source.order && $0.diners == 1 && !$0.isLeftover && !$0.sendsLeftover }
            .map(\.order)
            .sorted()
    }

    /// Proposition par défaut : le prochain créneau seul, sans enchaîner deux restes.
    static func suggestedPairs(in slots: [LeftoverSlot]) -> [(source: Int, target: Int)] {
        var taken: Set<Int> = []
        var pairs: [(Int, Int)] = []
        for slot in slots.sorted(by: { $0.order < $1.order }) where producesLeftover(slot) && !taken.contains(slot.order) {
            let next = candidates(for: slot, in: slots).first { !taken.contains($0) }
            guard let next else { continue }
            pairs.append((slot.order, next))
            taken.insert(slot.order)
            taken.insert(next)
        }
        return pairs
    }
}
