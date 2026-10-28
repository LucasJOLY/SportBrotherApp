import SwiftUI

nonisolated enum RecipeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case poulet, boeuf, porc, poisson, oeufs, autre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .poulet: "Volaille"
        case .boeuf: "Bœuf"
        case .porc: "Porc"
        case .poisson: "Poisson"
        case .oeufs: "Œufs"
        case .autre: "Autre"
        }
    }

    /// Teinte discrète de la catégorie (l'orange reste réservé aux actions).
    var color: Color {
        let base: Color = switch self {
        case .poulet: .brown
        case .boeuf: .red
        case .porc: .pink
        case .poisson: .blue
        case .oeufs: .teal
        case .autre: .gray
        }
        return base.opacity(0.85)
    }

    var symbol: String {
        switch self {
        case .poulet: "bird"
        case .boeuf: "fork.knife"
        case .porc: "fork.knife.circle"
        case .poisson: "fish"
        case .oeufs: "frying.pan"
        case .autre: "basket"
        }
    }
}

nonisolated enum Aisle: String, Codable, CaseIterable, Identifiable, Sendable {
    case fruitsLegumes, boucherie, poissonnerie, cremerie, epicerie, condiments, surgeles, boulangerie, autre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fruitsLegumes: "Fruits et légumes"
        case .boucherie: "Boucherie"
        case .poissonnerie: "Poissonnerie"
        case .cremerie: "Crèmerie"
        case .epicerie: "Épicerie"
        case .condiments: "Épices et condiments"
        case .surgeles: "Surgelés"
        case .boulangerie: "Boulangerie"
        case .autre: "Autre"
        }
    }
}

nonisolated enum Meal: String, Codable, CaseIterable, Identifiable, Sendable {
    case lunch, dinner

    var id: String { rawValue }
    var label: String { self == .lunch ? "Midi" : "Soir" }
}

nonisolated enum SlotStatus: String, Codable, Sendable {
    case planned, done, skipped, eatenOut

    var label: String {
        switch self {
        case .planned: "Prévu"
        case .done: "Fait"
        case .skipped: "Sauté"
        case .eatenOut: "Mangé dehors"
        }
    }
}

nonisolated enum RecipeSource: String, Codable, Sendable {
    case manual, ai
}

nonisolated enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case four, microOndes, plaques, airfryer, cocotteMinute, robotCuiseur, blender, mixeurPlongeant, wok, cuiseurRiz, balance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .four: "Four"
        case .microOndes: "Micro-ondes"
        case .plaques: "Plaques de cuisson"
        case .airfryer: "Airfryer"
        case .cocotteMinute: "Cocotte-minute"
        case .robotCuiseur: "Robot cuiseur"
        case .blender: "Blender"
        case .mixeurPlongeant: "Mixeur plongeant"
        case .wok: "Wok"
        case .cuiseurRiz: "Cuiseur à riz"
        case .balance: "Balance de cuisine"
        }
    }
}
