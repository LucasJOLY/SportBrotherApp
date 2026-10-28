import Foundation
import Testing
@testable import RepasJOLY

private func source(_ ref: String, _ name: String, grams: Double = 0, detail: String = "", remaining: Bool = true,
                    recipe: String = "Recette", pantry: Bool = false) -> ShoppingSource {
    ShoppingSource(ref: ref, recipeTitle: recipe, mealLabel: "Lundi soir",
                   ingredient: Ingredient(name: name, detail: detail, grams: grams, aisle: .cremerie, isPantry: pantry),
                   isRemaining: remaining)
}

struct ShoppingPlannerTests {
    @Test func fingerprintIsStableAndOrderIndependent() {
        let a = [source("1", "Skyr", grams: 150), source("2", "Poulet")]
        let b = [source("2", "Poulet"), source("1", "Skyr", grams: 150)]
        #expect(ShoppingPlanner.fingerprint(a) == ShoppingPlanner.fingerprint(b))
        #expect(ShoppingPlanner.fingerprint(a) != ShoppingPlanner.fingerprint([source("1", "Skyr", grams: 200), source("2", "Poulet")]))
    }

    @Test func subtractsWhatIsAtHome() throws {
        let sources = [source("1", "Poulet", grams: 400, recipe: "Teriyaki"), source("2", "Poulet", grams: 350, recipe: "Curry")]
        let items = ShoppingPlanner.localItems(sources)
        let need = try #require(ShoppingPlanner.needs(items, sources: sources, have: ["poulet": 500]).first)
        #expect(need.needed == 750)
        #expect(need.toBuy == 250)
        #expect(need.quantityText == "250 g")
        #expect(need.recipes == ["Teriyaki", "Curry"])
        #expect(!need.isCoveredAtHome)
    }

    @Test func onlyRemainingMealsCount() throws {
        let sources = [source("1", "Skyr", grams: 150, remaining: false), source("2", "Skyr", grams: 100)]
        let need = try #require(ShoppingPlanner.needs(ShoppingPlanner.localItems(sources), sources: sources, have: [:]).first)
        #expect(need.needed == 100)
        #expect(ShoppingPlanner.needs(ShoppingPlanner.localItems([sources[0]]), sources: [sources[0]], have: [:]).isEmpty)
    }

    @Test func unknownQuantitiesAreCountedAsMeals() throws {
        let sources = [source("1", "Courgettes"), source("2", "Courgettes")]
        let need = try #require(ShoppingPlanner.needs(ShoppingPlanner.localItems(sources), sources: sources, have: [:]).first)
        #expect(need.quantityText == "pour 2 repas")
    }

    @Test func repairKeepsEachOccurrenceOnceAndRecoversForgottenOnes() {
        let sources = [source("a", "Skyr", grams: 150), source("b", "Skyr nature", grams: 100), source("c", "Miel")]
        let fromAI = [
            ConsolidatedItem(name: "Skyr nature", aisle: .cremerie, unit: "g", isPantry: false,
                             parts: [.init(ref: "a", amount: 150), .init(ref: "b", amount: 100), .init(ref: "a", amount: 150), .init(ref: "zzz", amount: 5)]),
        ]
        let repaired = ShoppingPlanner.repair(fromAI, sources: sources)
        #expect(repaired.first?.parts.map(\.ref) == ["a", "b"])
        #expect(repaired.contains { $0.name == "Miel" && $0.parts.map(\.ref) == ["c"] })
        let need = ShoppingPlanner.needs(repaired, sources: sources, have: [:]).first { $0.item.name == "Skyr nature" }
        #expect(need?.needed == 250)
    }

    @Test func estimatesSpoonsAndUnitsFromDetail() {
        #expect(ShoppingPlanner.estimatedAmount(detail: "3 c. à soupe", unit: "g") == 45)
        #expect(ShoppingPlanner.estimatedAmount(detail: "1 c. à café rase", unit: "ml") == 5)
        #expect(ShoppingPlanner.estimatedAmount(detail: "50 cl", unit: "ml") == 500)
        #expect(ShoppingPlanner.estimatedAmount(detail: "0,5 kg", unit: "g") == 500)
        #expect(ShoppingPlanner.estimatedAmount(detail: "2 blancs", unit: "g") == 0)
        #expect(ShoppingPlanner.estimatedAmount(detail: "3 c. à soupe", unit: "pièce") == 0)
    }

    @Test func repairFillsEmptyAmountsFromDetail() {
        let sources = [source("a", "Skyr", grams: 150), source("b", "Skyr nature", detail: "3 c. à soupe")]
        let fromAI = [ConsolidatedItem(name: "Skyr nature", aisle: .cremerie, unit: "g", isPantry: false,
                                       parts: [.init(ref: "a", amount: 150), .init(ref: "b", amount: 0)])]
        let need = ShoppingPlanner.needs(ShoppingPlanner.repair(fromAI, sources: sources), sources: sources, have: [:]).first
        #expect(need?.needed == 195)
        #expect(need?.quantityText == "195 g")
    }

    @Test func formatsUnits() {
        #expect(ShoppingPlanner.format(1250, unit: "g") == "1,25 kg")
        #expect(ShoppingPlanner.format(250, unit: "g") == "250 g")
        #expect(ShoppingPlanner.format(1500, unit: "ml") == "1,5 L")
        #expect(ShoppingPlanner.format(3, unit: "pièce") == "3")
    }
}

struct StockEntryTests {
    @Test func parsesQuantities() {
        #expect(StockEntry.parse("500 g poulet") == ("Poulet", 500, "g"))
        #expect(StockEntry.parse("poulet 500g") == ("Poulet", 500, "g"))
        #expect(StockEntry.parse("1,5 kg de bœuf") == ("Bœuf", 1500, "g"))
        #expect(StockEntry.parse("6 œufs") == ("Œufs", 6, "pièce"))
        #expect(StockEntry.parse("50 cl de crème") == ("Crème", 500, "ml"))
        #expect(StockEntry.parse("courgettes") == ("Courgettes", 0, ""))
    }
}
