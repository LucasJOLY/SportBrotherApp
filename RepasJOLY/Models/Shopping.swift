import Foundation
import SwiftData

/// État coché d'une ligne de courses générée, mémorisé par semaine.
@Model
final class ShoppingMark {
    var key: String
    var weekStart: Date
    var isChecked: Bool

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

/// Ce qu'il y a déjà à la maison : retiré des courses, privilégié au planning et à la génération.
@Model
final class StockItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var addedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.addedAt = .now
    }
}
