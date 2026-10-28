import Foundation

/// Recette telle que renvoyée par l'IA (0 et "" signifient « non renseigné »).
nonisolated struct RecipeDraft: Codable, Sendable {
    struct DraftIngredient: Codable, Sendable {
        var name: String
        var detail: String
        var grams: Double
        var aisle: Aisle
        var isPantry: Bool
        var group: String
    }
    struct DraftStep: Codable, Sendable {
        var title: String
        var text: String
        var durationMinutes: Int
        var parallelHint: String
        var passive: Bool
    }

    var title: String
    var summary: String
    var category: RecipeCategory
    var estimatedMinutes: Int
    var ovenTemperature: Int
    var ingredients: [DraftIngredient]
    var steps: [DraftStep]
    var tip: String
    var kcal: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    func makeRecipe(source: RecipeSource, rawInput: String) -> Recipe {
        let recipe = Recipe(
            title: title,
            summary: summary,
            category: category,
            estimatedMinutes: estimatedMinutes,
            ovenTemperature: ovenTemperature,
            ingredients: ingredients.map {
                Ingredient(name: $0.name, detail: $0.detail, grams: $0.grams, aisle: $0.aisle, isPantry: $0.isPantry, group: $0.group)
            },
            steps: steps.map {
                RecipeStep(title: $0.title, text: $0.text, durationMinutes: $0.durationMinutes,
                           parallelHint: $0.parallelHint, isPassive: $0.passive)
            },
            source: source,
            rawInput: rawInput
        )
        recipe.tip = tip
        (recipe.kcal, recipe.protein, recipe.carbs, recipe.fat) = (kcal, protein, carbs, fat)
        return recipe
    }
}

nonisolated struct TasteQuestion: Codable, Hashable, Sendable {
    var question: String
    var options: [String]
}

nonisolated struct RecipeIdea: Codable, Hashable, Sendable {
    var title: String
    var pitch: String
}

nonisolated struct QuestionsPayload: Codable, Sendable { var questions: [TasteQuestion] }
nonisolated struct IdeasPayload: Codable, Sendable { var ideas: [RecipeIdea] }
nonisolated struct PlanPayload: Codable, Sendable {
    struct Assignment: Codable, Sendable {
        var slot: Int
        var recipe: Int
    }
    var assignments: [Assignment]
}

/// Schémas JSON stricts (additionalProperties: false partout, pas de nullables).
enum AISchemas {
    static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": Array(properties.keys), "additionalProperties": false]
    }
    static func array(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
    static let string: [String: Any] = ["type": "string"]
    static let integer: [String: Any] = ["type": "integer"]
    static let number: [String: Any] = ["type": "number"]
    static let boolean: [String: Any] = ["type": "boolean"]
    static func enumeration(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }

    static let recipe = object([
        "title": string,
        "summary": string,
        "category": enumeration(RecipeCategory.allCases.map(\.rawValue)),
        "estimatedMinutes": integer,
        "ovenTemperature": integer,
        "ingredients": array(object([
            "name": string,
            "detail": string,
            "grams": number,
            "aisle": enumeration(Aisle.allCases.map(\.rawValue)),
            "isPantry": boolean,
            "group": string,
        ])),
        "steps": array(object([
            "title": string,
            "text": string,
            "durationMinutes": integer,
            "parallelHint": string,
            "passive": boolean,
        ])),
        "tip": string,
        "kcal": integer,
        "protein": integer,
        "carbs": integer,
        "fat": integer,
    ])

    static let questions = object(["questions": array(object(["question": string, "options": array(string)]))])
    static let ideas = object(["ideas": array(object(["title": string, "pitch": string]))])
    static let plan = object(["assignments": array(object(["slot": integer, "recipe": integer]))])
}
