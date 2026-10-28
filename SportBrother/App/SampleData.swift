import Foundation
import SwiftData

/// Données de démonstration (lancement avec `-sampleData`, base en mémoire uniquement).
enum SampleData {
    static func insert(into context: ModelContext) {
        let recipes = makeRecipes()
        recipes.forEach(context.insert)
        insertSport(into: context)
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

    /// Deux profils, trois mois de séances Push / Pull / Jambes avec une progression régulière, des pesées.
    static func insertSport(into context: ModelContext) {
        let lucas = SportProfile(name: "Lucas", colorIndex: 0, sortOrder: 0)
        let tom = SportProfile(name: "Tom", colorIndex: 1, sortOrder: 1)
        [lucas, tom].forEach(context.insert)
        UserDefaults.standard.set(lucas.id.uuidString, forKey: myProfileKey)

        let plans: [(String, [(String, Double)])] = [
            ("Push", [("Barbell_Bench_Press_-_Medium_Grip", 60), ("Incline_Dumbbell_Press", 22), ("Side_Lateral_Raise", 8), ("Triceps_Pushdown_-_Rope_Attachment", 20)]),
            ("Pull", [("Pullups", 0), ("Wide-Grip_Lat_Pulldown", 50), ("Seated_Cable_Rows", 45), ("Hammer_Curls", 12)]),
            ("Jambes", [("Barbell_Squat", 70), ("Leg_Press", 120), ("Lying_Leg_Curls", 30), ("Standing_Calf_Raises", 40)]),
        ]
        let templates = plans.enumerated().map { index, plan in
            let template = SportTemplate(name: plan.0, sortOrder: index)
            context.insert(template)
            for (order, exercise) in plan.1.enumerated() {
                context.insert(SportTemplateItem(templateID: template.id, exerciseRef: exercise.0, sortOrder: order, setCount: 3))
            }
            return template
        }
        ["Barbell_Bench_Press_-_Medium_Grip", "Barbell_Squat", "Wide-Grip_Lat_Pulldown", "Hammer_Curls"].forEach { id in
            let favorite = SportExercise(id: id)
            favorite.isFavorite = true
            context.insert(favorite)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Lundi, mercredi, vendredi environ, avec quelques semaines creuses.
        let offsets = stride(from: 92, through: 1, by: -1).filter { day in
            let weekday = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: -day, to: today) ?? today)
            return [2, 4, 6].contains(weekday) && !(40...47).contains(day) && day % 17 != 0
        }
        for (count, offset) in offsets.enumerated() {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let planIndex = count % plans.count
            let withTom = count % 3 != 1
            let session = SportSession(
                day: day,
                startedAt: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day) ?? day,
                profileIDs: withTom ? [lucas.id, tom.id] : [lucas.id],
                templateID: templates[planIndex].id
            )
            session.endedAt = session.startedAt.addingTimeInterval(TimeInterval(55 * 60 + count * 37 % 900))
            context.insert(session)
            let progress = Double(count / plans.count)
            for (order, exercise) in plans[planIndex].1.enumerated() {
                let entry = SportEntry(sessionID: session.id, exerciseRef: exercise.0, sortOrder: order)
                context.insert(entry)
                for (profile, factor) in withTom ? [(lucas, 1.0), (tom, 0.85)] : [(lucas, 1.0)] {
                    let weight = ((exercise.1 + progress * exercise.1 * 0.012) * factor / 2.5).rounded() * 2.5
                    // Tractions au poids du corps : on progresse en reps.
                    let base = exercise.1 == 0 ? [6, 5, 4].map { $0 + Int(progress / 3) + (profile === tom ? 2 : 0) } : [12, 10, 9]
                    for index in 0..<3 {
                        let set = SportSet(entryID: entry.id, profileID: profile.id, index: index, weightKg: weight, reps: base[index] - (count + order) % 2)
                        set.doneAt = session.startedAt.addingTimeInterval(TimeInterval(order * 600 + index * 150))
                        context.insert(set)
                    }
                }
            }
        }
        // Abdos travaillés une seule fois il y a 16 jours : apparaît dans « Pas travaillé depuis un moment ».
        let absDay = calendar.date(byAdding: .day, value: -16, to: today) ?? today
        let absSession = SportSession(day: absDay, startedAt: calendar.date(bySettingHour: 12, minute: 15, second: 0, of: absDay) ?? absDay, profileIDs: [lucas.id])
        absSession.endedAt = absSession.startedAt.addingTimeInterval(1500)
        context.insert(absSession)
        for (order, exercise) in ["Cable_Crunch", "Plank"].enumerated() {
            let entry = SportEntry(sessionID: absSession.id, exerciseRef: exercise, sortOrder: order)
            context.insert(entry)
            for index in 0..<3 {
                let set = SportSet(entryID: entry.id, profileID: lucas.id, index: index, weightKg: exercise == "Plank" ? 0 : 35, reps: exercise == "Plank" ? 45 : 15)
                set.doneAt = absSession.startedAt.addingTimeInterval(TimeInterval(order * 500 + index * 120))
                context.insert(set)
            }
            let feedback = SportFeedback(entryID: entry.id, profileID: lucas.id)
            feedback.effort = exercise == "Plank" ? .dur : .bien
            feedback.note = exercise == "Plank" ? "Gainage en secondes plutôt qu'en reps" : nil
            context.insert(feedback)
        }

        let month = calendar.dateInterval(of: .month, for: .now)?.start ?? today
        let review = CoachReview(
            headline: "Régularité solide : 2,4 séances par semaine et le développé couché progresse bien.",
            tips: [
                "Les abdos n'ont pas été travaillés depuis 16 jours : ajoute 2 exos en fin de séance Jambes.",
                "Le tirage vertical stagne à 52,5 kg depuis 3 séances : passe en séries dégressives sur la dernière série.",
                "Ton volume de tirage est inférieur à celui de poussée : ajoute un rowing à la séance Push.",
            ]
        )
        context.insert(SportCoachReview(profileID: lucas.id, month: month, payload: (try? JSONEncoder().encode(review)) ?? Data()))

        for (index, offset) in stride(from: 90, through: 0, by: -10).enumerated() {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            context.insert(SportBodyWeight(profileID: lucas.id, day: day, kg: 76.4 + Double(index) * 0.18))
            context.insert(SportBodyWeight(profileID: tom.id, day: day, kg: 82.0 - Double(index) * 0.25))
        }
    }
}
