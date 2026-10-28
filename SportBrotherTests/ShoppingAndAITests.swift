import Foundation
import Testing
@testable import SportBrother

struct ShoppingListBuilderTests {
    @Test func countsMealsInsteadOfGramsWhenNoQuantity() throws {
        let sections = ShoppingListBuilder.build(meals: [
            [Ingredient(name: "Poulet", aisle: .boucherie), Ingredient(name: "Riz", aisle: .epicerie)],
            [Ingredient(name: "poulets", aisle: .boucherie)],
        ])
        let chicken = try #require(sections.first { $0.aisle == .boucherie }?.lines.first)
        #expect(chicken.name == "Poulet")
        #expect(chicken.occurrences == 2)
        #expect(chicken.quantityText == "×2")
    }

    @Test func sumsGramsWhenGiven() throws {
        let sections = ShoppingListBuilder.build(meals: [
            [Ingredient(name: "Bœuf haché", grams: 250, aisle: .boucherie)],
            [Ingredient(name: "boeuf hache", grams: 1000, aisle: .boucherie)],
        ])
        let beef = try #require(sections.first?.lines.first)
        #expect(beef.grams == 1250)
        #expect(beef.quantityText == "1,2 kg" || beef.quantityText == "1.2 kg")
    }

    @Test func keepsPrecisionsAndPantryFlag() throws {
        let sections = ShoppingListBuilder.build(meals: [
            [Ingredient(name: "Sauce soja", detail: "2 c. à soupe", aisle: .condiments, isPantry: true)],
            [Ingredient(name: "Sauce soja", detail: "1 c. à café", aisle: .condiments, isPantry: true)],
        ])
        let soy = try #require(sections.first?.lines.first)
        #expect(soy.details == ["2 c. à soupe", "1 c. à café"])
        #expect(soy.isPantry)
    }

    @Test func groupsByAisleInStoreOrder() {
        let sections = ShoppingListBuilder.build(meals: [[
            Ingredient(name: "Pâtes", aisle: .epicerie),
            Ingredient(name: "Tomates", aisle: .fruitsLegumes),
            Ingredient(name: "Steak", aisle: .boucherie),
        ]])
        #expect(sections.map(\.aisle) == [.fruitsLegumes, .boucherie, .epicerie])
    }

    @Test func countsAnIngredientOncePerMeal() throws {
        let sections = ShoppingListBuilder.build(meals: [[
            Ingredient(name: "Ail", detail: "1 gousse", aisle: .fruitsLegumes),
            Ingredient(name: "Ail", detail: "2 gousses", aisle: .fruitsLegumes),
        ]])
        #expect(try #require(sections.first?.lines.first).occurrences == 1)
    }
}

struct ClaudeDecodingTests {
    @Test func decodesRecipeDraft() throws {
        let json = """
        {"title":"Poulet curry","summary":"Rapide","category":"poulet","estimatedMinutes":25,"ovenTemperature":0,
         "ingredients":[{"name":"Poulet","detail":"","grams":0,"aisle":"boucherie","isPantry":false,"group":""},
                        {"name":"Curry","detail":"1 c. à soupe","grams":0,"aisle":"condiments","isPantry":true,"group":"Sauce"}],
         "steps":[{"title":"Le poulet","text":"Saisir le poulet","durationMinutes":8,"parallelHint":"Lancer le riz","passive":true}],
         "tip":"Saisir à feu vif","kcal":650,"protein":50,"carbs":70,"fat":15}
        """
        let draft = try JSONDecoder().decode(RecipeDraft.self, from: Data(json.utf8))
        let recipe = draft.makeRecipe(source: .ai, rawInput: "")
        #expect(recipe.category == .poulet)
        #expect(recipe.ingredients.count == 2)
        #expect(recipe.ingredients[1].isPantry)
        #expect(recipe.steps.first?.durationMinutes == 8)
        #expect(recipe.steps.first?.parallelHint == "Lancer le riz")
        #expect(recipe.steps.first?.isPassive == true)
        #expect(recipe.steps.first?.title == "Le poulet")
        #expect(recipe.tip == "Saisir à feu vif")
        #expect(recipe.protein == 50)
        #expect(recipe.ingredientGroups.map(\.name) == ["", "Sauce"])
    }

    @Test func neverOffersVegetarianCategory() {
        let categories = (AISchemas.recipe["properties"] as? [String: Any])?["category"] as? [String: Any]
        let values = categories?["enum"] as? [String] ?? []
        #expect(!values.isEmpty)
        #expect(!values.contains("vege"))
    }

    @Test func decodesStepsSavedBeforePassiveFlag() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Cuire le riz","durationMinutes":12,"parallelHint":""}"#
        let step = try JSONDecoder().decode(RecipeStep.self, from: Data(json.utf8))
        #expect(step.durationMinutes == 12)
        #expect(step.isPassive == false)
    }

    @Test func decodesQuestionsIdeasAndPlan() throws {
        let questions = try JSONDecoder().decode(QuestionsPayload.self, from: Data(
            #"{"questions":[{"question":"Quelle cuisine ?","options":["Asiatique","Méditerranéenne"]}]}"#.utf8))
        #expect(questions.questions.first?.options.count == 2)

        let ideas = try JSONDecoder().decode(IdeasPayload.self, from: Data(
            #"{"ideas":[{"title":"Bowl poulet teriyaki","pitch":"Riz, poulet glacé, brocolis."}]}"#.utf8))
        #expect(ideas.ideas.first?.title == "Bowl poulet teriyaki")

        let plan = try JSONDecoder().decode(PlanPayload.self, from: Data(#"{"assignments":[{"slot":3,"recipe":1}]}"#.utf8))
        #expect(plan.assignments.first?.slot == 3)
    }

    @Test func schemasForbidExtraProperties() {
        #expect(AISchemas.recipe["additionalProperties"] as? Bool == false)
        let required = AISchemas.recipe["required"] as? [String] ?? []
        #expect(Set(required) == ["title", "summary", "category", "estimatedMinutes", "ovenTemperature", "ingredients", "steps",
                                  "tip", "kcal", "protein", "carbs", "fat"])
    }
}

struct WeekCalendarTests {
    @Test func mondayAndDayIndex() throws {
        // Mercredi 28 octobre 2026.
        let wednesday = try #require(WeekCalendar.calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 19)))
        let monday = WeekCalendar.monday(of: wednesday)
        #expect(WeekCalendar.calendar.component(.day, from: monday) == 26)
        #expect(WeekCalendar.dayIndex(of: wednesday) == 2)
    }
}

struct QuantityScalerTests {
    @Test func halvesSpoonsAndCounts() {
        #expect(QuantityScaler.scale("3 c. à soupe", by: 0.5) == "1 ½ c. à soupe")
        #expect(QuantityScaler.scale("1 gousse hachée", by: 0.5) == "½ gousse hachée")
        #expect(QuantityScaler.scale("1 c. à café dans 4 c. à soupe d'eau froide", by: 0.5) == "½ c. à café dans 2 c. à soupe d'eau froide")
        #expect(QuantityScaler.scale("1/2 citron", by: 0.5) == "¼ citron")
    }

    @Test func leavesTemperaturesAndPerPersonAmounts() {
        #expect(QuantityScaler.scale("four à 200 °C", by: 0.5) == "four à 200 °C")
        #expect(QuantityScaler.scale("4 escalopes (environ 200 g par personne)", by: 0.5) == "2 escalopes (environ 200 g par personne)")
    }

    @Test func roundsGramsToWeighableValues() {
        #expect(QuantityScaler.scaleGrams(380, by: 0.5) == 190)
        #expect(QuantityScaler.scaleGrams(225, by: 0.5) == 115)
        #expect(QuantityScaler.scaleGrams(21, by: 0.5) == 11)
        #expect(QuantityScaler.scaleGrams(0, by: 0.5) == 0)
    }

    @Test func noChangeForTwo() {
        let ingredient = Ingredient(name: "Riz", detail: "3 c. à soupe", grams: 220)
        let scaled = ingredient.scaled(forServings: 2)
        #expect(scaled.grams == 220)
        #expect(scaled.detail == "3 c. à soupe")
    }
}
