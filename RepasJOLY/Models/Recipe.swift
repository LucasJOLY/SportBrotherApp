import Foundation
import SwiftData

nonisolated struct Ingredient: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    /// Précision libre : « 2 c. à soupe », « 1 pincée »… vide si non renseignée.
    var detail: String = ""
    /// Grammes, 0 si non renseignés.
    var grams: Double = 0
    var aisle: Aisle = .autre
    /// Basique du placard (sel, huile…) : affiché « en stock » par défaut dans les courses.
    var isPantry: Bool = false
    /// Bloc de la recette : vide pour la base, sinon « Sauce », « Finition »…
    var group: String = ""
}

extension Ingredient {
    private enum CodingKeys: String, CodingKey {
        case id, name, detail, grams, aisle, isPantry, group
    }

    /// Tolère les données enregistrées avant l'ajout de `group`.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        grams = try container.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        aisle = try container.decodeIfPresent(Aisle.self, forKey: .aisle) ?? .autre
        isPantry = try container.decodeIfPresent(Bool.self, forKey: .isPantry) ?? false
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? ""
    }
}

nonisolated struct RecipeStep: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    /// Titre court de l'étape (« Le laquage »), vide si aucun.
    var title: String = ""
    var text: String
    /// Durée d'attente de l'étape (cuisson, repos…), 0 si aucune.
    var durationMinutes: Int = 0
    /// Ce qu'on peut lancer en parallèle pendant cette étape, vide sinon.
    var parallelHint: String = ""
    /// L'étape tourne seule une fois lancée (four, mijotage, cuisson à l'eau, repos) :
    /// on lance son minuteur et on enchaîne la suite pendant ce temps.
    var isPassive: Bool = false
}

extension RecipeStep {
    private enum CodingKeys: String, CodingKey {
        case id, title, text, durationMinutes, parallelHint, isPassive
    }

    /// Tolère les données enregistrées avant l'ajout de `isPassive`.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try container.decode(String.self, forKey: .text)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        parallelHint = try container.decodeIfPresent(String.self, forKey: .parallelHint) ?? ""
        isPassive = try container.decodeIfPresent(Bool.self, forKey: .isPassive) ?? false
    }
}

@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String
    var category: RecipeCategory
    var estimatedMinutes: Int
    /// Température du four en °C, 0 si pas de four.
    var ovenTemperature: Int
    var ingredients: [Ingredient]
    var steps: [RecipeStep]
    /// Astuce du chef, vide si aucune.
    var tip: String = ""
    /// Valeurs estimées par personne, 0 si inconnues.
    var kcal: Int = 0
    var protein: Int = 0
    var carbs: Int = 0
    var fat: Int = 0
    @Attribute(.externalStorage) var photo: Data?
    var isFavorite: Bool
    var rating: Int?
    var source: RecipeSource
    var rawInput: String
    var createdAt: Date
    var lastCookedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \CookingSession.recipe)
    var sessions: [CookingSession] = []

    @Relationship(deleteRule: .nullify, inverse: \MealSlot.recipe)
    var slots: [MealSlot] = []

    init(
        title: String,
        summary: String = "",
        category: RecipeCategory = .autre,
        estimatedMinutes: Int = 30,
        ovenTemperature: Int = 0,
        ingredients: [Ingredient] = [],
        steps: [RecipeStep] = [],
        source: RecipeSource = .manual,
        rawInput: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.category = category
        self.estimatedMinutes = estimatedMinutes
        self.ovenTemperature = ovenTemperature
        self.ingredients = ingredients
        self.steps = steps
        self.isFavorite = false
        self.rating = nil
        self.source = source
        self.rawInput = rawInput
        self.createdAt = .now
    }

    var finishedSessions: [CookingSession] { sessions.filter { $0.endedAt != nil } }

    var hasMacros: Bool { kcal > 0 }

    /// Version texte compacte, envoyée à l'IA pour créer une variante.
    var promptText: String {
        var lines = [title]
        if !summary.isEmpty { lines.append(summary) }
        lines.append("Ingrédients : " + ingredients.map { item in
            [item.group.isEmpty ? nil : "[\(item.group)]", item.name, item.grams > 0 ? "\(Int(item.grams)) g" : nil,
             item.detail.isEmpty ? nil : item.detail].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: " ; "))
        lines += steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }
        if ovenTemperature > 0 { lines.append("Four : \(ovenTemperature) °C") }
        return lines.joined(separator: "\n")
    }

    /// Ingrédients regroupés par bloc, la base d'abord.
    var ingredientGroups: [(name: String, items: [Ingredient])] {
        var order: [String] = []
        for item in ingredients where !order.contains(item.group) { order.append(item.group) }
        order.sort { $0.isEmpty && !$1.isEmpty }
        return order.map { name in (name, ingredients.filter { $0.group == name }) }
    }

    /// Temps réel moyen mesuré par le chrono, en secondes.
    var averageCookingSeconds: TimeInterval? {
        let durations = finishedSessions.map(\.activeSeconds)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }
}
