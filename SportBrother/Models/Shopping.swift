import Foundation
import SwiftData

/// État d'une ligne de courses pour une semaine : cochée, et quantité déjà à la maison.
@Model
final class ShoppingMark {
    var key: String
    var weekStart: Date
    var isChecked: Bool
    /// Quantité déjà à la maison, dans l'unité de la ligne (0 si non renseignée).
    var have: Double = 0

    init(key: String, weekStart: Date, isChecked: Bool) {
        self.key = key
        self.weekStart = weekStart
        self.isChecked = isChecked
    }
}

@Model
final class ManualShoppingItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var weekStart: Date
    var isChecked: Bool
    var createdAt: Date

    init(name: String, weekStart: Date) {
        self.id = UUID()
        self.name = name
        self.weekStart = weekStart
        self.isChecked = false
        self.createdAt = .now
    }
}

/// Liste de courses regroupée par l'IA, mise en cache tant que les repas de la semaine ne changent pas.
@Model
final class ShoppingPlan {
    @Attribute(.unique) var weekStart: Date
    var fingerprint: String
    var itemsData: Data
    var usedAI: Bool
    var createdAt: Date

    init(weekStart: Date, fingerprint: String, items: [ConsolidatedItem], usedAI: Bool) {
        self.weekStart = weekStart
        self.fingerprint = fingerprint
        self.itemsData = (try? JSONEncoder().encode(items)) ?? Data()
        self.usedAI = usedAI
        self.createdAt = .now
    }

    var items: [ConsolidatedItem] {
        (try? JSONDecoder().decode([ConsolidatedItem].self, from: itemsData)) ?? []
    }
}

/// Ce qu'il y a déjà à la maison : retiré des courses, privilégié au planning et à la génération.
@Model
final class StockItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var addedAt: Date
    /// Quantité connue (« 500 g »), 0 si non précisée.
    var amount: Double = 0
    /// « g », « ml », « pièce », ou vide.
    var unit: String = ""

    init(name: String, amount: Double = 0, unit: String = "") {
        self.id = UUID()
        self.name = name
        self.addedAt = .now
        self.amount = amount
        self.unit = unit
    }

    var label: String {
        amount > 0 ? "\(name) · \(ShoppingPlanner.format(amount, unit: unit))" : name
    }
}
