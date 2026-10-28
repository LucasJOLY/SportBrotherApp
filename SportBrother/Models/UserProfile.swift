import Foundation
import SwiftData

@Model
final class UserProfile {
    var equipment: [Equipment]
    var burners: Int
    var cookwareNotes: String
    var excludedFoods: [String]
    var weightKg: Double
    var proteinTargetPerMeal: Int
    var kcalTargetPerMeal: Int
    var tasteLikes: [String]
    var tasteDislikes: [String]
    var aiPlanningByDefault: Bool
    /// Convives des 14 créneaux de la dernière semaine préparée (lundi midi → dimanche soir).
    var lastDinersTemplate: [Int]
    var aiInputTokens: Int
    var aiOutputTokens: Int

    init() {
        self.equipment = [.four, .plaques, .microOndes]
        self.burners = 4
        self.cookwareNotes = ""
        self.excludedFoods = []
        self.weightKg = 0
        self.proteinTargetPerMeal = 0
        self.kcalTargetPerMeal = 0
        self.tasteLikes = []
        self.tasteDislikes = []
        self.aiPlanningByDefault = true
        self.lastDinersTemplate = Array(repeating: 2, count: 14)
        self.aiInputTokens = 0
        self.aiOutputTokens = 0
    }

    /// Contexte compact envoyé à l'IA pour adapter les recettes générées.
    var promptContext: String {
        var lines: [String] = []
        let tools = equipment.map(\.label).joined(separator: ", ")
        lines.append("Matériel : \(tools.isEmpty ? "plaques" : tools), \(burners) feux.")
        if !cookwareNotes.isEmpty { lines.append("Ustensiles : \(cookwareNotes).") }
        if !excludedFoods.isEmpty {
            lines.append("INTERDITS (allergies/refus, jamais utiliser) : \(excludedFoods.joined(separator: ", ")).")
        }
        var goals: [String] = []
        if weightKg > 0 { goals.append("poids \(Int(weightKg)) kg") }
        if proteinTargetPerMeal > 0 { goals.append("\(proteinTargetPerMeal) g de protéines par repas") }
        if kcalTargetPerMeal > 0 { goals.append("\(kcalTargetPerMeal) kcal par repas") }
        if !goals.isEmpty { lines.append("Objectifs : \(goals.joined(separator: ", ")).") }
        if !tasteLikes.isEmpty { lines.append("Aime : \(tasteLikes.suffix(12).joined(separator: ", ")).") }
        if !tasteDislikes.isEmpty { lines.append("N'aime pas : \(tasteDislikes.suffix(12).joined(separator: ", ")).") }
        return lines.joined(separator: "\n")
    }
}

extension ModelContext {
    /// Le profil unique, créé à la première demande.
    func profile() -> UserProfile {
        if let existing = try? fetch(FetchDescriptor<UserProfile>()).first { return existing }
        let profile = UserProfile()
        insert(profile)
        return profile
    }
}
