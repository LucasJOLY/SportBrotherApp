import Foundation

/// Rapproche les ingrédients des recettes de ce qu'il y a au frigo (« poulet » ↔ « Filets de poulet »).
nonisolated enum StockMatcher {
    static func keys(_ names: [String]) -> Set<String> {
        // « 2 escalopes » compte comme « escalope » : seule la nature de l'aliment sert à la comparaison.
        Set(names.map { name in
            ShoppingListBuilder.normalizedKey(name)
                .split(separator: " ")
                .filter { $0.allSatisfy { !$0.isNumber } }
                .joined(separator: " ")
        }.filter { !$0.isEmpty })
    }

    static func matches(_ ingredientName: String, stock: Set<String>) -> Bool {
        guard !stock.isEmpty else { return false }
        let key = " \(ShoppingListBuilder.normalizedKey(ingredientName)) "
        return stock.contains { key.contains(" \($0) ") }
    }

    /// Nombre d'ingrédients principaux (hors placard) déjà à la maison.
    static func matchCount(_ ingredients: [Ingredient], stock: Set<String>) -> Int {
        ingredients.filter { !$0.isPantry && matches($0.name, stock: stock) }.count
    }
}
