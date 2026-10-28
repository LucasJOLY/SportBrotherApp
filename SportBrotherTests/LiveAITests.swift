import Foundation
import SwiftData
import Testing
@testable import SportBrother

/// Appels réels à Claude, désactivés par défaut (coût : environ 1 centime).
/// Lancer avec `TEST_RUNNER_LIVE_AI=1 xcodebuild test … -only-testing:SportBrotherTests/LiveAITests`.
/// Les réponses sont écrites dans le fichier indiqué par `LIVE_AI_OUTPUT`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_AI"] == "1"), .serialized)
struct LiveAITests {
    private let context: ModelContext
    private let output = ProcessInfo.processInfo.environment["LIVE_AI_OUTPUT"] ?? NSTemporaryDirectory() + "live-ai.txt"

    init() throws {
        let container = try ModelContainer(
            for: Recipe.self, WeekPlan.self, MealSlot.self, CookingSession.self,
            ShoppingMark.self, ManualShoppingItem.self, UserProfile.self, StockItem.self, ShoppingPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        let profile = context.profile()
        profile.equipment = [.four, .plaques, .microOndes, .airfryer]
        profile.weightKg = 75
        profile.proteinTargetPerMeal = 50
    }

    private func log(_ title: String, _ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let text = "\n===== \(title) =====\n" + String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
        let handle = FileHandle(forWritingAtPath: output) ?? {
            FileManager.default.createFile(atPath: output, contents: nil)
            return FileHandle(forWritingAtPath: output)!
        }()
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try handle.close()
    }

    private func logUsage(_ step: String) throws {
        let profile = context.profile()
        try log("tokens après \(step)", ["input": profile.aiInputTokens, "output": profile.aiOutputTokens])
    }

    @Test func fullGenerationFlow() async throws {
        let service = AIService(context: context)
        let ingredients = ["Poulet"]
        let request = "un plat rapide le soir avec une vraie sauce"

        let questions = try await service.questions(ingredients: ingredients, request: request)
        try log("questions", questions)
        try logUsage("questions")
        #expect(!questions.isEmpty)

        let answers = Dictionary(uniqueKeysWithValues: questions.compactMap { q in q.options.first.map { (q.question, $0) } })
        let ideas = try await service.ideas(ingredients: ingredients, request: request, answers: answers, avoiding: [])
        try log("idées", ideas)
        try logUsage("idées")
        #expect(ideas.count == 3)

        let draft = try await service.detail(of: try #require(ideas.first), ingredients: ingredients, request: request, answers: answers)
        try log("recette détaillée", draft)
        try logUsage("recette détaillée")
        #expect(draft.category != .autre || !draft.ingredients.isEmpty)
        #expect(draft.steps.contains { $0.passive })
    }

    @Test func formatsQuickEntry() async throws {
        let raw = "boeuf haché, patates douces au four 25 min 200 degrés avec paprika, sauce skyr moutarde ancienne, " +
            "faire revenir le boeuf avec oignon, haricots verts vapeur"
        let draft = try await AIService(context: context).formatRecipe(raw)
        try log("mise en forme", draft)
        try logUsage("mise en forme")
        #expect(!draft.steps.isEmpty)
    }

    @Test func importsALink() async throws {
        let page = try await RecipeImporter.fetchText(from: "https://www.marmiton.org/recettes/recette_poulet-basquaise_11633.aspx")
        try log("page importée", page)
        let draft = try await AIService(context: context).formatRecipe(page)
        try log("recette importée", draft)
        try logUsage("import de lien")
        #expect(!draft.ingredients.isEmpty)
    }

    @Test func makesAVariant() async throws {
        let original = try #require(SampleData.makeRecipes().first)
        context.insert(original)
        let draft = try await AIService(context: context).variant(of: original, request: "Version airfryer avec du bœuf")
        try log("variante", draft)
        try logUsage("variante")
        #expect(draft.title != original.title)
    }

    @Test func consolidatesShopping() async throws {
        var sources: [ShoppingSource] = []
        let extra = [
            Ingredient(name: "Skyr", grams: 150, aisle: .cremerie),
            Ingredient(name: "Skyr nature", detail: "3 c. à soupe", aisle: .cremerie),
            Ingredient(name: "Escalopes de poulet", grams: 300, aisle: .boucherie),
            Ingredient(name: "Poulet en dés", detail: "2 blancs", aisle: .boucherie),
            Ingredient(name: "Citron", detail: "1/2 jus", aisle: .fruitsLegumes),
        ]
        for (index, recipe) in SampleData.makeRecipes().enumerated() {
            for (i, ingredient) in recipe.ingredients.enumerated() {
                sources.append(ShoppingSource(ref: "r\(index)-\(i)", recipeTitle: recipe.title, mealLabel: "Jour \(index)",
                                              ingredient: ingredient, isRemaining: true))
            }
        }
        for (i, ingredient) in extra.enumerated() {
            sources.append(ShoppingSource(ref: "x\(i)", recipeTitle: "Bowl skyr", mealLabel: "Samedi midi", ingredient: ingredient, isRemaining: true))
        }
        let items = try await AIService(context: context).consolidateShopping(sources)
        let needs = ShoppingPlanner.needs(items, sources: sources, have: [:])
        try log("courses regroupées", needs.map { "\($0.item.aisle.label) | \($0.item.name) | \($0.quantityText ?? "-") | \($0.recipes.count) recettes\($0.item.isPantry ? " | placard" : "")" })
        try logUsage("courses")
        #expect(needs.filter { $0.item.name.localizedStandardContains("skyr") }.count == 1)
    }

    @Test func revisesARecipe() async throws {
        let original = try #require(SampleData.makeRecipes().first)
        var form = RecipeForm(recipe: original)
        form.ingredients.append(Ingredient(name: "Crème liquide", detail: "10 cl", aisle: .cremerie, group: "Sauce"))
        let draft = try await AIService(context: context).revise(RecipeDraft(form: form), request: "du skyr au lieu de la crème liquide, sans noix de cajou")
        try log("retouche", draft)
        try logUsage("retouche")
        let names = draft.ingredients.map { $0.name.lowercased() }
        #expect(names.contains { $0.contains("skyr") })
        #expect(!names.contains { $0.contains("crème liquide") || $0.contains("cajou") })
    }

    @Test func plansAWeek() async throws {
        let recipes = SampleData.makeRecipes()
        recipes.forEach(context.insert)
        let slots = (0..<10).map { PlannerSlot(order: $0, lockedRecipeID: nil) }
        let plan = try await AIService(context: context).plan(slots: slots, recipes: recipes, rules: PlannerRules())
        let titles = slots.map { slot in plan[slot.order].flatMap { id in recipes.first { $0.id == id }?.title } ?? "—" }
        try log("planning", titles)
        try logUsage("planning")
        #expect(plan.count >= 8)
    }
}
