import Foundation
import SwiftData

/// Données de démonstration (lancement avec `-sampleData`, base en mémoire uniquement).
enum SampleData {
    static func insert(into context: ModelContext) {
        let recipes = makeRecipes()
        recipes.forEach(context.insert)
        ["Poulet", "Brocolis", "Riz basmati"].forEach { context.insert(StockItem(name: $0)) }
        let profile = context.profile()
        profile.tasteLikes = ["Saumon fumé en fin de cuisson, ajouté hors du feu pour garder le fondant", "Pâtes sèches (type tagliatelle ou penne)",
                              "Cuisine italienne", "Moins de 30 minutes", "Herbes de Provence et ail"]
        profile.aiInputTokens = 1_234_567
        profile.aiOutputTokens = 2_345_678
        recipes[0].rating = 5
        recipes[0].isFavorite = true
        recipes[2].rating = 4

        let start = WeekCalendar.monday(of: .now)
        let diners = [2, 2, 1, 1, 0, 2, 1, 2, 2, 2, 0, 0, 0, 0]
        let planner = WeekPlanner(context: context)
        let week = planner.createWeek(start: start, diners: diners, leftovers: [(3, 6)])
        let picks = [0, 1, 2, 3, 4, 5, 6, 7]
        for (index, slot) in week.orderedSlots.filter(\.needsCooking).enumerated() {
            slot.recipe = recipes[picks[index % picks.count] % recipes.count]
        }
        planner.syncLeftovers(in: week)
        let today = WeekCalendar.dayIndex(of: .now)
        for slot in week.slots where slot.day < today && !slot.isAbsent { slot.status = .done }
        if let skipped = week.slots.first(where: { $0.day < today && $0.meal == .lunch && $0.needsCooking }) {
            skipped.status = .eatenOut
        }
    }

    static func makeRecipes() -> [Recipe] {
        [
            {
                let recipe = Recipe(
                    title: "Poulet teriyaki, riz basmati et brocolis",
                    summary: "Digeste le soir, riche en protéines et en glucides complexes, avec une sauce caramélisée qui ne fait pas exploser les lipides.",
                    category: .poulet, estimatedMinutes: 20,
                    ingredients: [
                        Ingredient(name: "Filets de poulet", detail: "en dés", grams: 380, aisle: .boucherie),
                        Ingredient(name: "Riz basmati", grams: 220, aisle: .epicerie),
                        Ingredient(name: "Brocolis", grams: 350, aisle: .fruitsLegumes),
                        Ingredient(name: "Huile de sésame", detail: "1 c. à soupe", aisle: .condiments, isPantry: true),
                        Ingredient(name: "Sauce soja", detail: "3 c. à soupe", aisle: .condiments, isPantry: true, group: "Sauce"),
                        Ingredient(name: "Miel", detail: "1 c. à soupe", aisle: .epicerie, isPantry: true, group: "Sauce"),
                        Ingredient(name: "Ail", detail: "1 gousse hachée", aisle: .fruitsLegumes, group: "Sauce"),
                        Ingredient(name: "Gingembre", detail: "râpé", aisle: .fruitsLegumes, group: "Sauce"),
                        Ingredient(name: "Maïzena", detail: "1 c. à café dans 4 c. à soupe d'eau froide", aisle: .epicerie, isPantry: true, group: "Sauce"),
                        Ingredient(name: "Noix de cajou", detail: "concassées", grams: 20, aisle: .epicerie, group: "Finition"),
                    ],
                    steps: [
                        RecipeStep(title: "Le riz et les légumes", text: "Lance le riz dans l'eau bouillante salée.", durationMinutes: 12,
                                   parallelHint: "Pendant ce temps : prépare la sauce puis saisis le poulet. Ajoute les brocolis dans la casserole du riz 5 min avant la fin.",
                                   isPassive: true),
                        RecipeStep(title: "La sauce", text: "Dans un bol, mélange soja, miel, ail, gingembre et la Maïzena diluée jusqu'à ce qu'il n'y ait plus de grumeaux."),
                        RecipeStep(title: "Le poulet", text: "Chauffe l'huile dans une grande poêle ou un wok, plaque sur 8, et saisis les dés de poulet jusqu'à ce qu'ils soient bien dorés.", durationMinutes: 6),
                        RecipeStep(title: "Le laquage", text: "Passe la plaque sur 5, ajoute les brocolis égouttés et verse la sauce. Mélange : elle épaissit et enrobe la viande.", durationMinutes: 2),
                        RecipeStep(title: "Le dressage", text: "Sers le riz au fond des assiettes, le poulet laqué par-dessus, et parsème de noix de cajou."),
                    ])
                recipe.tip = "La Maïzena épaissit la sauce et nappe le poulet sans ajouter de gras. Les brocolis cuits avec le riz font gagner une casserole."
                (recipe.kcal, recipe.protein, recipe.carbs, recipe.fat) = (720, 54, 88, 14)
                return recipe
            }(),
            Recipe(title: "Bœuf sauté aux poivrons", category: .boeuf, estimatedMinutes: 25,
                   ingredients: [Ingredient(name: "Bœuf", aisle: .boucherie), Ingredient(name: "Poivrons", aisle: .fruitsLegumes),
                                 Ingredient(name: "Sauce soja", detail: "3 c. à soupe", aisle: .condiments), Ingredient(name: "Riz basmati", aisle: .epicerie)],
                   steps: [RecipeStep(text: "Saisis le bœuf émincé à feu vif."), RecipeStep(text: "Ajoute les poivrons et la sauce soja.", durationMinutes: 8)]),
            Recipe(title: "Saumon, patate douce et haricots verts", category: .poisson, estimatedMinutes: 30, ovenTemperature: 190,
                   ingredients: [Ingredient(name: "Saumon", aisle: .poissonnerie), Ingredient(name: "Patate douce", aisle: .fruitsLegumes),
                                 Ingredient(name: "Haricots verts", aisle: .surgeles)],
                   steps: [RecipeStep(text: "Rôtis la patate douce en cubes.", durationMinutes: 25), RecipeStep(text: "Cuis le saumon à la poêle.", durationMinutes: 6)]),
            Recipe(title: "Curry de poulet aux pois chiches", category: .poulet, estimatedMinutes: 30,
                   ingredients: [Ingredient(name: "Poulet", aisle: .boucherie), Ingredient(name: "Pois chiches", aisle: .epicerie), Ingredient(name: "Lait de coco", aisle: .epicerie),
                                 Ingredient(name: "Curry", detail: "1 c. à soupe", aisle: .condiments, isPantry: true), Ingredient(name: "Riz basmati", aisle: .epicerie)],
                   steps: [RecipeStep(text: "Fais revenir l'oignon et le curry."), RecipeStep(text: "Ajoute pois chiches et lait de coco, laisse mijoter.", durationMinutes: 15)]),
            Recipe(title: "Dinde, quinoa et courgettes", category: .poulet, estimatedMinutes: 25,
                   ingredients: [Ingredient(name: "Escalopes de dinde", aisle: .boucherie), Ingredient(name: "Quinoa", aisle: .epicerie),
                                 Ingredient(name: "Courgettes", aisle: .fruitsLegumes)],
                   steps: [RecipeStep(text: "Cuis le quinoa.", durationMinutes: 12), RecipeStep(text: "Poêle la dinde et les courgettes.")]),
            Recipe(title: "Omelette aux épinards et feta", category: .oeufs, estimatedMinutes: 10,
                   ingredients: [Ingredient(name: "Œufs", aisle: .cremerie), Ingredient(name: "Épinards", aisle: .fruitsLegumes), Ingredient(name: "Feta", aisle: .cremerie)],
                   steps: [RecipeStep(text: "Bats les œufs, ajoute épinards et feta, cuis à feu doux.", durationMinutes: 5)]),
            Recipe(title: "Pâtes complètes bolognaise", category: .boeuf, estimatedMinutes: 30,
                   ingredients: [Ingredient(name: "Bœuf haché", aisle: .boucherie), Ingredient(name: "Pâtes complètes", aisle: .epicerie),
                                 Ingredient(name: "Coulis de tomate", aisle: .epicerie)],
                   steps: [RecipeStep(text: "Fais revenir le bœuf, ajoute le coulis.", durationMinutes: 15), RecipeStep(text: "Cuis les pâtes.", durationMinutes: 10)]),
            Recipe(title: "Filet mignon, purée de pommes de terre", category: .porc, estimatedMinutes: 40, ovenTemperature: 180,
                   ingredients: [Ingredient(name: "Filet mignon", aisle: .boucherie), Ingredient(name: "Pommes de terre", aisle: .fruitsLegumes)],
                   steps: [RecipeStep(text: "Rôtis le filet mignon.", durationMinutes: 30), RecipeStep(text: "Prépare la purée.")]),
        ]
    }
}
