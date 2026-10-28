import Foundation
import Testing
@testable import SportBrother

struct StockMatcherTests {
    @Test func matchesIngredientContainingStockWord() {
        let stock = StockMatcher.keys(["Poulet", "2 courgettes"])
        #expect(StockMatcher.matches("Filets de poulet", stock: stock))
        #expect(StockMatcher.matches("Courgettes", stock: stock))
        #expect(!StockMatcher.matches("Bœuf haché", stock: stock))
    }

    @Test func countsOnlyMainIngredients() {
        let stock = StockMatcher.keys(["sel", "poulet"])
        let ingredients = [Ingredient(name: "Poulet"), Ingredient(name: "Sel", isPantry: true), Ingredient(name: "Riz")]
        #expect(StockMatcher.matchCount(ingredients, stock: stock) == 1)
    }

    @Test func plannerFavorsRecipesUsingStock() {
        let plain = PlannerRecipe(id: UUID(), category: .boeuf, isFavorite: false, rating: nil, lastCookedAt: nil)
        let fridge = PlannerRecipe(id: UUID(), category: .boeuf, isFavorite: false, rating: nil, lastCookedAt: nil, stockMatches: 2)
        let now = Date.now
        #expect(LocalPlanner.weight(for: fridge, previousCategory: nil, categoryCount: [:], now: now)
                > LocalPlanner.weight(for: plain, previousCategory: nil, categoryCount: [:], now: now))
    }
}

struct RecipeImporterTests {
    @Test func readsStructuredRecipe() throws {
        let html = """
        <html><head><script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[{"@type":"WebSite"},{"@type":"Recipe","name":"Poulet basquaise",
         "recipeYield":"4 personnes","recipeIngredient":["1 poulet","3 poivrons"],
         "recipeInstructions":[{"@type":"HowToStep","text":"Faire dorer le poulet."},{"@type":"HowToStep","text":"Ajouter les poivrons."}]}]}
        </script></head><body>Menu Pub</body></html>
        """
        let text = try #require(RecipeImporter.extractText(fromHTML: html))
        #expect(text.contains("Poulet basquaise"))
        #expect(text.contains("- 3 poivrons"))
        #expect(text.contains("2. Ajouter les poivrons."))
        #expect(!text.contains("Menu Pub"))
    }

    @Test func fallsBackOnShareDescription() throws {
        let caption = "Bowl de poulet croustillant, sauce yaourt-citron et riz : 300 g de poulet, 2 c. à soupe de yaourt, l'astuce c'est de bien sécher la viande."
        let html = #"<html><head><meta property="og:title" content="Recette du jour"><meta property="og:description" content="\#(caption)"></head></html>"#
        let text = try #require(RecipeImporter.extractText(fromHTML: html))
        #expect(text.contains("l'astuce c'est de bien sécher"))
    }

    @Test func rejectsEmptyPages() {
        #expect(RecipeImporter.extractText(fromHTML: "<html><body>Erreur</body></html>") == nil)
    }
}

struct CookingStatsTests {
    private func week(_ offset: Int, done: Int, planned: Int = 10) -> CookingStats.WeekScore {
        let start = WeekCalendar.calendar.date(byAdding: .day, value: -7 * offset, to: WeekCalendar.monday(of: .now))!
        return .init(weekStart: start, done: done, planned: planned)
    }

    @Test func countsConsecutiveRespectedWeeksIgnoringCurrentInProgress() {
        let current = WeekCalendar.monday(of: .now)
        #expect(CookingStats.streak([week(0, done: 3), week(1, done: 9), week(2, done: 8), week(3, done: 5), week(4, done: 10)],
                                    currentWeekStart: current) == 2)
    }

    @Test func gapBreaksTheStreak() {
        let current = WeekCalendar.monday(of: .now)
        #expect(CookingStats.streak([week(1, done: 9), week(3, done: 9)], currentWeekStart: current) == 1)
    }

    @Test func progressionNeedsTwoSessions() {
        #expect(CookingStats.progression([(Date.now, 1200)]) == nil)
        let result = CookingStats.progression([(Date.now, 1500), (Date.now.addingTimeInterval(-86_400 * 7), 1900)])
        #expect(result?.first == 1900 && result?.last == 1500)
    }
}

struct MealAnnouncerTests {
    @Test func readsTodayMeals() {
        let sentence = MealAnnouncer.sentence(for: [
            .init(isLunch: true, title: "Bœuf sauté", status: .planned, isLeftover: true),
            .init(isLunch: false, title: "Poulet teriyaki", status: .planned, isLeftover: false),
        ])
        #expect(sentence == "Ce midi, tu finis le reste de Bœuf sauté. Ce soir : Poulet teriyaki.")
        #expect(MealAnnouncer.sentence(for: []) == "Rien n'est prévu aujourd'hui.")
        #expect(MealAnnouncer.sentence(for: [.init(isLunch: false, title: nil, status: .eatenOut, isLeftover: false)])
                == "Ce soir, tu manges dehors.")
    }
}
