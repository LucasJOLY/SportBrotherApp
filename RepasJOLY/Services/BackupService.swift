import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Sauvegarde complète en un fichier JSON, pour réinstaller l'app sans rien perdre.
nonisolated struct Backup: Codable, Sendable {
    struct RecipeData: Codable, Sendable {
        var id: UUID, title: String, summary: String, category: RecipeCategory
        var estimatedMinutes: Int, ovenTemperature: Int
        var ingredients: [Ingredient], steps: [RecipeStep]
        var photo: Data?, isFavorite: Bool, rating: Int?
        var source: RecipeSource, rawInput: String, createdAt: Date, lastCookedAt: Date?
        var tip: String?, macros: [Int]?
    }
    struct SlotData: Codable, Sendable {
        var id: UUID, day: Int, meal: Meal, diners: Int, recipeID: UUID?
        var isLocked: Bool, leftoverSourceID: UUID?, status: SlotStatus
    }
    struct WeekData: Codable, Sendable {
        var weekStart: Date, usedAI: Bool, excludedRecipeIDs: [UUID], excludedCategories: [RecipeCategory]
        var slots: [SlotData]
    }
    struct SessionData: Codable, Sendable {
        var id: UUID, recipeID: UUID?, slotID: UUID?, startedAt: Date, endedAt: Date?, pausedSeconds: TimeInterval
    }
    struct ProfileData: Codable, Sendable {
        var equipment: [Equipment], burners: Int, cookwareNotes: String, excludedFoods: [String]
        var weightKg: Double, proteinTargetPerMeal: Int, kcalTargetPerMeal: Int
        var tasteLikes: [String], tasteDislikes: [String], aiPlanningByDefault: Bool
    }

    var version = 1
    var exportedAt: Date
    var recipes: [RecipeData]
    var weeks: [WeekData]
    var sessions: [SessionData]
    var profile: ProfileData
    var stock: [String]? = nil
}

enum BackupService {
    static func export(from context: ModelContext) throws -> Data {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let weeks = try context.fetch(FetchDescriptor<WeekPlan>())
        let sessions = try context.fetch(FetchDescriptor<CookingSession>())
        let profile = context.profile()

        let backup = Backup(
            exportedAt: .now,
            recipes: recipes.map {
                .init(id: $0.id, title: $0.title, summary: $0.summary, category: $0.category,
                      estimatedMinutes: $0.estimatedMinutes, ovenTemperature: $0.ovenTemperature,
                      ingredients: $0.ingredients, steps: $0.steps, photo: $0.photo, isFavorite: $0.isFavorite,
                      rating: $0.rating, source: $0.source, rawInput: $0.rawInput, createdAt: $0.createdAt,
                      lastCookedAt: $0.lastCookedAt, tip: $0.tip, macros: [$0.kcal, $0.protein, $0.carbs, $0.fat])
            },
            weeks: weeks.map { week in
                .init(weekStart: week.weekStart, usedAI: week.usedAI, excludedRecipeIDs: week.excludedRecipeIDs,
                      excludedCategories: week.excludedCategories,
                      slots: week.slots.map {
                          .init(id: $0.id, day: $0.day, meal: $0.meal, diners: $0.diners, recipeID: $0.recipe?.id,
                                isLocked: $0.isLocked, leftoverSourceID: $0.leftoverSourceID, status: $0.status)
                      })
            },
            sessions: sessions.map {
                .init(id: $0.id, recipeID: $0.recipe?.id, slotID: $0.slotID, startedAt: $0.startedAt,
                      endedAt: $0.endedAt, pausedSeconds: $0.pausedSeconds)
            },
            profile: .init(equipment: profile.equipment, burners: profile.burners, cookwareNotes: profile.cookwareNotes,
                           excludedFoods: profile.excludedFoods, weightKg: profile.weightKg,
                           proteinTargetPerMeal: profile.proteinTargetPerMeal, kcalTargetPerMeal: profile.kcalTargetPerMeal,
                           tasteLikes: profile.tasteLikes, tasteDislikes: profile.tasteDislikes,
                           aiPlanningByDefault: profile.aiPlanningByDefault)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var full = backup
        full.stock = try context.fetch(FetchDescriptor<StockItem>()).map(\.name)
        return try encoder.encode(full)
    }

    /// Remplace toutes les données locales par celles de la sauvegarde.
    static func restore(_ data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)

        try context.delete(model: CookingSession.self)
        try context.delete(model: MealSlot.self)
        try context.delete(model: WeekPlan.self)
        try context.delete(model: Recipe.self)
        try context.delete(model: ShoppingMark.self)
        try context.delete(model: ManualShoppingItem.self)
        try context.delete(model: StockItem.self)
        for name in backup.stock ?? [] { context.insert(StockItem(name: name)) }

        var recipes: [UUID: Recipe] = [:]
        for item in backup.recipes {
            let recipe = Recipe(title: item.title, summary: item.summary, category: item.category,
                                estimatedMinutes: item.estimatedMinutes, ovenTemperature: item.ovenTemperature,
                                ingredients: item.ingredients, steps: item.steps, source: item.source, rawInput: item.rawInput)
            recipe.id = item.id
            recipe.photo = item.photo
            recipe.isFavorite = item.isFavorite
            recipe.rating = item.rating
            recipe.createdAt = item.createdAt
            recipe.lastCookedAt = item.lastCookedAt
            recipe.tip = item.tip ?? ""
            if let macros = item.macros, macros.count == 4 {
                (recipe.kcal, recipe.protein, recipe.carbs, recipe.fat) = (macros[0], macros[1], macros[2], macros[3])
            }
            context.insert(recipe)
            recipes[item.id] = recipe
        }
        for item in backup.weeks {
            let week = WeekPlan(weekStart: item.weekStart, usedAI: item.usedAI)
            week.excludedRecipeIDs = item.excludedRecipeIDs
            week.excludedCategories = item.excludedCategories
            context.insert(week)
            for slotData in item.slots {
                let slot = MealSlot(day: slotData.day, meal: slotData.meal, diners: slotData.diners)
                slot.id = slotData.id
                slot.recipe = slotData.recipeID.flatMap { recipes[$0] }
                slot.isLocked = slotData.isLocked
                slot.leftoverSourceID = slotData.leftoverSourceID
                slot.status = slotData.status
                slot.week = week
                context.insert(slot)
            }
        }
        for item in backup.sessions {
            guard let recipe = item.recipeID.flatMap({ recipes[$0] }) else { continue }
            let session = CookingSession(recipe: recipe, slotID: item.slotID, startedAt: item.startedAt)
            session.id = item.id
            session.endedAt = item.endedAt
            session.pausedSeconds = item.pausedSeconds
            context.insert(session)
        }

        let profile = context.profile()
        profile.equipment = backup.profile.equipment
        profile.burners = backup.profile.burners
        profile.cookwareNotes = backup.profile.cookwareNotes
        profile.excludedFoods = backup.profile.excludedFoods
        profile.weightKg = backup.profile.weightKg
        profile.proteinTargetPerMeal = backup.profile.proteinTargetPerMeal
        profile.kcalTargetPerMeal = backup.profile.kcalTargetPerMeal
        profile.tasteLikes = backup.profile.tasteLikes
        profile.tasteDislikes = backup.profile.tasteDislikes
        profile.aiPlanningByDefault = backup.profile.aiPlanningByDefault
        try context.save()
    }
}

struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
