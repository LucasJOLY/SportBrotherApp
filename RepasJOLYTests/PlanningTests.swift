import Foundation
import Testing
@testable import RepasJOLY

/// Générateur reproductible pour des tests déterministes.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func recipe(_ category: RecipeCategory, favorite: Bool = false, rating: Int? = nil, cookedDaysAgo: Double? = nil) -> PlannerRecipe {
    PlannerRecipe(id: UUID(), category: category, isFavorite: favorite, rating: rating,
                  lastCookedAt: cookedDaysAgo.map { Date.now.addingTimeInterval(-$0 * 86_400) })
}

private func slots(_ count: Int) -> [PlannerSlot] {
    (0..<count).map { PlannerSlot(order: $0, lockedRecipeID: nil) }
}

struct LocalPlannerTests {
    @Test func fillsEverySlotWithoutRepeatsWhenEnoughRecipes() {
        let recipes = RecipeCategory.allCases.map { recipe($0) } + [recipe(.poulet), recipe(.boeuf), recipe(.poisson), recipe(.porc)]
        var generator = SeededGenerator(state: 1)
        let plan = LocalPlanner.plan(slots: slots(10), recipes: recipes, rules: PlannerRules(), using: &generator)
        #expect(plan.count == 10)
        #expect(Set(plan.values).count == 10)
    }

    @Test func reusesRecipesOnlyWhenLibraryIsTooSmall() {
        let recipes = [recipe(.poulet), recipe(.boeuf), recipe(.oeufs)]
        var generator = SeededGenerator(state: 2)
        let plan = LocalPlanner.plan(slots: slots(6), recipes: recipes, rules: PlannerRules(), using: &generator)
        let counts = Dictionary(grouping: plan.values, by: { $0 }).mapValues(\.count)
        #expect(counts.values.allSatisfy { $0 == 2 })
    }

    @Test func respectsExclusions() {
        let chicken = recipe(.poulet)
        let fish = recipe(.poisson)
        let beef = recipe(.boeuf)
        let rules = PlannerRules(excludedRecipeIDs: [beef.id], excludedCategories: [.poisson])
        var generator = SeededGenerator(state: 3)
        let plan = LocalPlanner.plan(slots: slots(4), recipes: [chicken, fish, beef], rules: rules, using: &generator)
        #expect(Set(plan.values) == [chicken.id])
    }

    @Test func keepsLockedSlots() {
        let locked = recipe(.porc)
        let recipes = [locked, recipe(.poulet), recipe(.oeufs)]
        var generator = SeededGenerator(state: 4)
        let plan = LocalPlanner.plan(
            slots: [PlannerSlot(order: 0, lockedRecipeID: nil), PlannerSlot(order: 1, lockedRecipeID: locked.id), PlannerSlot(order: 2, lockedRecipeID: nil)],
            recipes: recipes, rules: PlannerRules(), using: &generator
        )
        #expect(plan[1] == locked.id)
        #expect(plan[0] != locked.id && plan[2] != locked.id)
    }

    @Test func returnsOnlyLockedWhenNothingAllowed() {
        var generator = SeededGenerator(state: 5)
        let plan = LocalPlanner.plan(slots: slots(3), recipes: [recipe(.poulet)],
                                     rules: PlannerRules(excludedCategories: [.poulet]), using: &generator)
        #expect(plan.isEmpty)
    }

    @Test func weightsFavorRatedFavoritesAndPenalizeRecentOrRepeatedProtein() {
        let now = Date.now
        let base = LocalPlanner.weight(for: recipe(.poulet), previousCategory: nil, categoryCount: [:], now: now)
        let loved = LocalPlanner.weight(for: recipe(.poulet, favorite: true, rating: 5), previousCategory: nil, categoryCount: [:], now: now)
        let recent = LocalPlanner.weight(for: recipe(.poulet, cookedDaysAgo: 2), previousCategory: nil, categoryCount: [:], now: now)
        let samePrevious = LocalPlanner.weight(for: recipe(.poulet), previousCategory: .poulet, categoryCount: [:], now: now)
        #expect(loved > base)
        #expect(recent < base)
        #expect(samePrevious < base)
    }

    @Test func avoidsSameProteinTwiceInARowWhenPossible() {
        let recipes = (0..<4).flatMap { _ in [recipe(.poulet), recipe(.boeuf), recipe(.poisson), recipe(.oeufs)] }
        let byID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.category) })
        var consecutive = 0
        for seed in 1...40 {
            var generator = SeededGenerator(state: UInt64(seed))
            let plan = LocalPlanner.plan(slots: slots(10), recipes: recipes, rules: PlannerRules(), using: &generator)
            for order in 1..<10 where byID[plan[order]!] == byID[plan[order - 1]!] { consecutive += 1 }
        }
        // 360 paires au total : la pénalité doit garder les répétitions rares.
        #expect(consecutive < 40)
    }
}

struct LeftoverRulesTests {
    private func info(_ diners: [Int]) -> [LeftoverSlot] {
        diners.enumerated().map { LeftoverSlot(order: $0.offset, diners: $0.element, isLeftover: false, sendsLeftover: false) }
    }

    @Test func onlySoloMealsProduceLeftovers() {
        let slots = info([2, 1, 0, 1])
        #expect(LeftoverRules.candidates(for: slots[0], in: slots).isEmpty)
        #expect(LeftoverRules.candidates(for: slots[1], in: slots) == [3])
    }

    @Test func candidatesAreLaterSoloSlotsNotAlreadyUsed() {
        var slots = info([1, 1, 2, 1, 1])
        slots[3] = LeftoverSlot(order: 3, diners: 1, isLeftover: true, sendsLeftover: false)
        #expect(LeftoverRules.candidates(for: slots[0], in: slots) == [1, 4])
    }

    @Test func suggestedPairsDoNotChainLeftovers() {
        let pairs = LeftoverRules.suggestedPairs(in: info([1, 1, 1, 1, 2, 1]))
        #expect(pairs.map(\.source) == [0, 2])
        #expect(pairs.map(\.target) == [1, 3])
    }

    @Test func noSuggestionWithoutLaterSoloSlot() {
        #expect(LeftoverRules.suggestedPairs(in: info([2, 2, 1, 2])).isEmpty)
    }
}
