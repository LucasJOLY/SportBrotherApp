import Foundation
import SwiftData

/// Opérations sur le planning de la semaine, au-dessus des modèles SwiftData.
struct WeekPlanner {
    let context: ModelContext

    /// Ce qu'il y a au frigo, normalisé pour la comparaison avec les ingrédients.
    var stockKeys: Set<String> {
        StockMatcher.keys(((try? context.fetch(FetchDescriptor<StockItem>())) ?? []).map(\.name))
    }

    func week(containing date: Date = .now) -> WeekPlan? {
        let start = WeekCalendar.monday(of: date)
        return try? context.fetch(FetchDescriptor<WeekPlan>(predicate: #Predicate { $0.weekStart == start })).first
    }

    /// Crée (ou remplace) la semaine avec les convives et les restes choisis, sans recettes.
    func createWeek(start: Date, diners: [Int], leftovers: [(source: Int, target: Int)]) -> WeekPlan {
        if let existing = try? context.fetch(FetchDescriptor<WeekPlan>(predicate: #Predicate { $0.weekStart == start })).first {
            context.delete(existing)
        }
        let week = WeekPlan(weekStart: start)
        context.insert(week)
        for order in 0..<14 {
            let slot = MealSlot(day: order / 2, meal: order.isMultiple(of: 2) ? .lunch : .dinner, diners: diners[order])
            slot.week = week
            context.insert(slot)
        }
        let byOrder = Dictionary(uniqueKeysWithValues: week.slots.map { ($0.order, $0) })
        for pair in leftovers {
            byOrder[pair.target]?.leftoverSourceID = byOrder[pair.source]?.id
        }
        context.profile().lastDinersTemplate = diners
        return week
    }

    /// Remplit les créneaux à cuisiner non verrouillés. L'IA d'abord si demandée, le local complète.
    func fill(_ week: WeekPlan, recipes: [Recipe], useAI: Bool) async -> String? {
        let rules = PlannerRules(
            excludedRecipeIDs: Set(week.excludedRecipeIDs),
            excludedCategories: Set(week.excludedCategories)
        )
        let cooking = week.orderedSlots.filter(\.needsCooking)
        let slots = cooking.map { PlannerSlot(order: $0.order, lockedRecipeID: $0.isLocked ? $0.recipe?.id : nil) }
        var assignments: [Int: UUID] = [:]
        var warning: String?

        if useAI {
            do {
                assignments = try await AIService(context: context).plan(slots: slots, recipes: recipes, rules: rules)
            } catch {
                warning = "Planification IA indisponible, répartition locale utilisée. \(error.localizedDescription)"
            }
        }

        let missing = slots.filter { $0.lockedRecipeID == nil && assignments[$0.order] == nil }
        if !missing.isEmpty {
            let fixed = slots.map { slot in
                PlannerSlot(order: slot.order, lockedRecipeID: slot.lockedRecipeID ?? assignments[slot.order])
            }
            var generator = SystemRandomNumberGenerator()
            assignments.merge(
                LocalPlanner.plan(slots: fixed, recipes: recipes.map { $0.plannerRecipe(stock: stockKeys) }, rules: rules, using: &generator),
                uniquingKeysWith: { current, _ in current }
            )
        }

        let byID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        for slot in cooking where !slot.isLocked {
            slot.recipe = assignments[slot.order].flatMap { byID[$0] }
        }
        week.usedAI = useAI
        syncLeftovers(in: week)
        return warning
    }

    /// Change la recette d'un seul créneau, en local (0 token).
    func reroll(_ slot: MealSlot, recipes: [Recipe]) {
        guard let week = slot.week, slot.needsCooking else { return }
        let rules = PlannerRules(
            excludedRecipeIDs: Set(week.excludedRecipeIDs),
            excludedCategories: Set(week.excludedCategories)
        )
        let usedElsewhere = Set(week.slots.filter { $0.id != slot.id }.compactMap { $0.recipe?.id })
        var pool = recipes.map { $0.plannerRecipe(stock: stockKeys) }.filter { $0.id != slot.recipe?.id }
        let unused = pool.filter { !usedElsewhere.contains($0.id) }
        if !LocalPlanner.allowedRecipes(unused, rules: rules).isEmpty { pool = unused }

        let previous = week.slots.first { $0.order == slot.order - 1 }?.recipe?.id
        var generator = SystemRandomNumberGenerator()
        let plan = LocalPlanner.plan(
            slots: [PlannerSlot(order: slot.order - 1, lockedRecipeID: previous),
                    PlannerSlot(order: slot.order, lockedRecipeID: nil)],
            recipes: pool,
            rules: rules,
            using: &generator
        )
        if let id = plan[slot.order] { slot.recipe = recipes.first { $0.id == id } }
        syncLeftovers(in: week)
    }

    func swap(_ first: MealSlot, _ second: MealSlot) {
        guard first.needsCooking, second.needsCooking, first.id != second.id else { return }
        (first.recipe, second.recipe) = (second.recipe, first.recipe)
        (first.isLocked, second.isLocked) = (second.isLocked, first.isLocked)
        if let week = first.week { syncLeftovers(in: week) }
    }

    func assign(_ recipe: Recipe, to slot: MealSlot) {
        slot.recipe = recipe
        slot.isLocked = true
        if let week = slot.week { syncLeftovers(in: week) }
    }

    func setLeftover(from source: MealSlot, to target: MealSlot?) {
        guard let week = source.week else { return }
        for slot in week.slots where slot.leftoverSourceID == source.id { slot.leftoverSourceID = nil }
        target?.leftoverSourceID = source.id
        target?.isLocked = false
        syncLeftovers(in: week)
    }

    /// Un reste porte toujours la recette de son créneau source.
    func syncLeftovers(in week: WeekPlan) {
        let byID = Dictionary(uniqueKeysWithValues: week.slots.map { ($0.id, $0) })
        for slot in week.slots {
            guard let sourceID = slot.leftoverSourceID else { continue }
            if let source = byID[sourceID], source.diners == 1 {
                slot.recipe = source.recipe
            } else {
                slot.leftoverSourceID = nil
            }
        }
    }

    func leftoverInfo(in week: WeekPlan) -> [LeftoverSlot] {
        week.slots.map { slot in
            LeftoverSlot(
                order: slot.order, diners: slot.diners, isLeftover: slot.isLeftover,
                sendsLeftover: week.slots.contains { $0.leftoverSourceID == slot.id }
            )
        }
    }

    func setStatus(_ status: SlotStatus, for slot: MealSlot) {
        slot.status = status
        if status == .done, slot.needsCooking { slot.recipe?.lastCookedAt = .now }
    }
}

extension Recipe {
    func plannerRecipe(stock: Set<String>) -> PlannerRecipe {
        PlannerRecipe(id: id, category: category, isFavorite: isFavorite, rating: rating, lastCookedAt: lastCookedAt,
                      stockMatches: StockMatcher.matchCount(ingredients, stock: stock))
    }
}
