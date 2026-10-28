import Foundation

nonisolated struct PlannerRecipe: Hashable, Sendable {
    let id: UUID
    let category: RecipeCategory
    let isFavorite: Bool
    let rating: Int?
    let lastCookedAt: Date?
    /// Ingrédients principaux déjà au frigo.
    var stockMatches: Int = 0
}

nonisolated struct PlannerSlot: Hashable, Sendable {
    /// Position dans la semaine (jour * 2 + repas).
    let order: Int
    /// Recette imposée (créneau verrouillé), à garder telle quelle.
    let lockedRecipeID: UUID?
}

nonisolated struct PlannerRules: Sendable {
    var excludedRecipeIDs: Set<UUID> = []
    var excludedCategories: Set<RecipeCategory> = []
    var now: Date = .now
}

/// Répartition locale : hasard pondéré, sans appel IA.
nonisolated enum LocalPlanner {
    /// Retourne la recette choisie pour chaque créneau (clé = `order`).
    static func plan<G: RandomNumberGenerator>(
        slots: [PlannerSlot],
        recipes: [PlannerRecipe],
        rules: PlannerRules,
        using generator: inout G
    ) -> [Int: UUID] {
        let allowed = allowedRecipes(recipes, rules: rules)
        let byID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        var result: [Int: UUID] = [:]
        var useCount: [UUID: Int] = [:]
        var categoryCount: [RecipeCategory: Int] = [:]

        for slot in slots {
            guard let locked = slot.lockedRecipeID else { continue }
            result[slot.order] = locked
            useCount[locked, default: 0] += 1
            if let category = byID[locked]?.category { categoryCount[category, default: 0] += 1 }
        }

        guard !allowed.isEmpty else { return result }

        for slot in slots.sorted(by: { $0.order < $1.order }) where slot.lockedRecipeID == nil {
            let previousCategory = result[slot.order - 1].flatMap { byID[$0]?.category }
            let minUse = allowed.map { useCount[$0.id, default: 0] }.min() ?? 0
            // Une recette ne revient qu'une fois toutes les autres utilisées.
            let pool = allowed.filter { useCount[$0.id, default: 0] == minUse }
            let weights = pool.map { recipe in
                weight(for: recipe, previousCategory: previousCategory, categoryCount: categoryCount, now: rules.now)
            }
            let pick = pool[weightedIndex(weights, using: &generator)]
            result[slot.order] = pick.id
            useCount[pick.id, default: 0] += 1
            categoryCount[pick.category, default: 0] += 1
        }
        return result
    }

    static func allowedRecipes(_ recipes: [PlannerRecipe], rules: PlannerRules) -> [PlannerRecipe] {
        recipes.filter { !rules.excludedRecipeIDs.contains($0.id) && !rules.excludedCategories.contains($0.category) }
    }

    static func weight(
        for recipe: PlannerRecipe,
        previousCategory: RecipeCategory?,
        categoryCount: [RecipeCategory: Int],
        now: Date
    ) -> Double {
        var weight = 1.0
        if recipe.isFavorite { weight += 1 }
        if recipe.stockMatches > 0 { weight *= 1 + 0.75 * Double(min(recipe.stockMatches, 3)) }
        if let rating = recipe.rating { weight *= 0.6 + Double(rating) * 0.2 }
        if let last = recipe.lastCookedAt {
            let days = now.timeIntervalSince(last) / 86_400
            if days < 7 { weight *= 0.3 } else if days < 14 { weight *= 0.6 }
        }
        if recipe.category == previousCategory { weight *= 0.2 }
        weight *= pow(0.5, Double(categoryCount[recipe.category, default: 0]))
        return max(weight, 0.01)
    }

    static func weightedIndex<G: RandomNumberGenerator>(_ weights: [Double], using generator: inout G) -> Int {
        let total = weights.reduce(0, +)
        var target = Double.random(in: 0..<total, using: &generator)
        for (index, weight) in weights.enumerated() {
            target -= weight
            if target < 0 { return index }
        }
        return weights.count - 1
    }
}
