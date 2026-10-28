import Foundation
import SwiftData

/// Point d'entrée des usages IA. Chaque méthode = un seul appel Haiku, tokens comptés dans le profil.
struct AIService {
    let context: ModelContext

    var isAvailable: Bool { ClaudeClient.configured != nil }

    private var client: ClaudeClient {
        get throws {
            guard let client = ClaudeClient.configured else { throw ClaudeError.missingAPIKey }
            return client
        }
    }

    private func track(_ usage: ClaudeUsage) {
        let profile = context.profile()
        profile.aiInputTokens += usage.inputTokens
        profile.aiOutputTokens += usage.outputTokens
    }

    /// Met au propre une recette écrite, importée d'un site ou photographiée.
    func formatRecipe(_ raw: String, images: [Data] = []) async throws -> RecipeDraft {
        let prompt = images.isEmpty ? raw : "Recette en photo ci-dessus.\(raw.isEmpty ? "" : " Précisions : \(raw)")"
        let (draft, usage) = try await client.send(
            RecipeDraft.self, system: Prompts.format, prompt: prompt, images: images,
            schema: AISchemas.recipe, maxTokens: 3000
        )
        track(usage)
        return draft
    }

    func questions(ingredients: [String], request: String) async throws -> [TasteQuestion] {
        let prompt = generationContext(ingredients: ingredients, request: request, answers: [:])
        let (payload, usage) = try await client.send(
            QuestionsPayload.self, system: Prompts.questions, prompt: prompt,
            schema: AISchemas.questions, maxTokens: 500
        )
        track(usage)
        return Array(payload.questions.prefix(4))
    }

    func ideas(ingredients: [String], request: String, answers: [String: String], avoiding: [String]) async throws -> [RecipeIdea] {
        var prompt = generationContext(ingredients: ingredients, request: request, answers: answers)
        if !avoiding.isEmpty { prompt += "\nDéjà proposées, à ne pas répéter : \(avoiding.joined(separator: ", "))." }
        let (payload, usage) = try await client.send(
            IdeasPayload.self, system: Prompts.ideas, prompt: prompt,
            schema: AISchemas.ideas, maxTokens: 3000, effort: .medium, thinks: true
        )
        track(usage)
        return Array(payload.ideas.prefix(3))
    }

    func detail(of idea: RecipeIdea, ingredients: [String], request: String, answers: [String: String]) async throws -> RecipeDraft {
        let prompt = generationContext(ingredients: ingredients, request: request, answers: answers)
            + "\nPlat choisi : \(idea.title) — \(idea.pitch)"
        let (draft, usage) = try await client.send(
            RecipeDraft.self, system: Prompts.detail, prompt: prompt,
            schema: AISchemas.recipe, maxTokens: 16000, effort: .medium, thinks: true
        )
        track(usage)
        return draft
    }

    /// Retouche libre d'une recette en cours d'édition (« du skyr au lieu de la crème liquide »).
    func revise(_ recipe: RecipeDraft, request: String) async throws -> RecipeDraft {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(recipe), as: UTF8.self)
        let prompt = [context.profile().promptContext, "Recette actuelle :", json, "Demande : \(request)"].joined(separator: "\n")
        let (draft, usage) = try await client.send(
            RecipeDraft.self, system: Prompts.revise, prompt: prompt,
            schema: AISchemas.recipe, maxTokens: 16000, effort: .medium, thinks: true
        )
        track(usage)
        return draft
    }

    /// Variante d'une recette existante (« version airfryer », « avec du bœuf »…).
    func variant(of recipe: Recipe, request: String) async throws -> RecipeDraft {
        let prompt = [context.profile().promptContext, "Recette d'origine :", recipe.promptText, "Variante demandée : \(request)"]
            .joined(separator: "\n")
        let (draft, usage) = try await client.send(
            RecipeDraft.self, system: Prompts.variant, prompt: prompt,
            schema: AISchemas.recipe, maxTokens: 16000, effort: .medium, thinks: true
        )
        track(usage)
        return draft
    }

    /// Regroupe les ingrédients de la semaine en une liste de courses propre. Un appel par planning.
    func consolidateShopping(_ sources: [ShoppingSource]) async throws -> [ConsolidatedItem] {
        guard !sources.isEmpty else { return [] }
        let lines = sources.enumerated().map { index, source in
            let ingredient = source.ingredient
            return "\(index)|\(ingredient.name)|\(ingredient.grams > 0 ? "\(Int(ingredient.grams)) g" : "-")|\(ingredient.detail.isEmpty ? "-" : ingredient.detail)|\(ingredient.aisle.rawValue)"
        }
        let prompt = "Occurrences (ref|ingrédient|grammes|précision|rayon) :\n" + lines.joined(separator: "\n")
        let (payload, usage) = try await client.send(
            ShoppingPayload.self, system: Prompts.shopping, prompt: prompt,
            schema: AISchemas.shopping, maxTokens: 6000
        )
        track(usage)
        let items = payload.items.map { item in
            ConsolidatedItem(
                name: ShoppingListBuilder.displayName(item.name), aisle: item.aisle, unit: item.unit, isPantry: item.isPantry,
                parts: item.parts.compactMap { part in
                    sources.indices.contains(part.ref) ? .init(ref: sources[part.ref].ref, amount: part.amount) : nil
                }
            )
        }
        return ShoppingPlanner.repair(items, sources: sources)
    }

    /// Planning IA : catalogue compressé en lignes, réponses en indices pour économiser les tokens.
    func plan(slots: [PlannerSlot], recipes: [Recipe], rules: PlannerRules) async throws -> [Int: UUID] {
        let allowed = recipes.filter {
            !rules.excludedRecipeIDs.contains($0.id) && !rules.excludedCategories.contains($0.category)
        }
        let open = slots.filter { $0.lockedRecipeID == nil }
        guard !allowed.isEmpty, !open.isEmpty else { return [:] }

        let stock = WeekPlanner(context: context).stockKeys
        let catalog = allowed.enumerated().map { index, recipe in
            let rating = recipe.rating.map { "\($0)/5" } ?? "-"
            let last = recipe.lastCookedAt.map { "\(Int(rules.now.timeIntervalSince($0) / 86_400))j" } ?? "jamais"
            let fridge = StockMatcher.matchCount(recipe.ingredients, stock: stock)
            return "\(index)|\(recipe.title)|\(recipe.category.label)|\(rating)|\(recipe.isFavorite ? "fav" : "-")|\(last)|\(fridge)"
        }
        let locked = slots.compactMap { slot in
            slot.lockedRecipeID.flatMap { id in allowed.firstIndex { $0.id == id } }.map { "\(slot.order)=\($0)" }
        }
        var prompt = "Recettes (n|nom|catégorie|note|favori|dernière fois|ingrédients déjà au frigo) :\n\(catalog.joined(separator: "\n"))"
        prompt += "\nCréneaux à remplir (n = jour*2 + 0 midi / 1 soir, jour 0 = lundi) : \(open.map { String($0.order) }.joined(separator: ","))"
        if !locked.isEmpty { prompt += "\nDéjà fixés : \(locked.joined(separator: ","))" }

        let (payload, usage) = try await client.send(
            PlanPayload.self, system: Prompts.planner, prompt: prompt,
            schema: AISchemas.plan, maxTokens: 400
        )
        track(usage)

        let openOrders = Set(open.map(\.order))
        var result: [Int: UUID] = [:]
        for assignment in payload.assignments where openOrders.contains(assignment.slot) && allowed.indices.contains(assignment.recipe) {
            result[assignment.slot] = allowed[assignment.recipe].id
        }
        return result
    }

    private func generationContext(ingredients: [String], request: String, answers: [String: String]) -> String {
        var lines = [context.profile().promptContext]
        let stock = ((try? context.fetch(FetchDescriptor<StockItem>())) ?? []).map(\.name)
        if !stock.isEmpty { lines.append("Déjà au frigo, à utiliser si possible : \(stock.joined(separator: ", ")).") }
        if !ingredients.isEmpty { lines.append("Ingrédients à utiliser : \(ingredients.joined(separator: ", ")).") }
        if !request.isEmpty { lines.append("Demande : \(request)") }
        if !answers.isEmpty {
            lines.append("Réponses : " + answers.map { "\($0.key) → \($0.value)" }.sorted().joined(separator: " ; "))
        }
        return lines.joined(separator: "\n")
    }
}
