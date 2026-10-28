import Foundation

nonisolated struct ShoppingLine: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let aisle: Aisle
    /// Nombre de repas qui utilisent cet ingrédient.
    let occurrences: Int
    let grams: Double
    let details: [String]
    let isPantry: Bool

    var id: String { key }

    var quantityText: String? {
        if grams > 0 { return grams >= 1000 ? "\((grams / 1000).formatted(.number.precision(.fractionLength(0...1)))) kg" : "\(Int(grams)) g" }
        return occurrences > 1 ? "×\(occurrences)" : nil
    }
}

nonisolated struct ShoppingSection: Identifiable, Hashable, Sendable {
    let aisle: Aisle
    let lines: [ShoppingLine]
    var id: Aisle { aisle }
}

/// Construit la liste de courses : un ingrédient = une ligne, compté par repas plutôt qu'en grammes.
nonisolated enum ShoppingListBuilder {
    static func build(meals: [[Ingredient]]) -> [ShoppingSection] {
        var order: [String] = []
        var lines: [String: (name: String, aisle: Aisle, count: Int, grams: Double, details: [String], pantry: Bool)] = [:]

        for ingredients in meals {
            var seenInMeal: Set<String> = []
            for ingredient in ingredients {
                let key = normalizedKey(ingredient.name)
                guard !key.isEmpty else { continue }
                var line = lines[key] ?? (displayName(ingredient.name), ingredient.aisle, 0, 0, [], ingredient.isPantry)
                if lines[key] == nil { order.append(key) }
                if seenInMeal.insert(key).inserted { line.count += 1 }
                line.grams += max(ingredient.grams, 0)
                let detail = ingredient.detail.trimmingCharacters(in: .whitespaces)
                if !detail.isEmpty { line.details.append(detail) }
                line.pantry = line.pantry && ingredient.isPantry
                lines[key] = line
            }
        }

        let all = order.compactMap { key -> ShoppingLine? in
            guard let line = lines[key] else { return nil }
            return ShoppingLine(key: key, name: line.name, aisle: line.aisle, occurrences: line.count,
                                grams: line.grams, details: line.details, isPantry: line.pantry)
        }
        return Aisle.allCases.compactMap { aisle in
            let inAisle = all.filter { $0.aisle == aisle }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return inAisle.isEmpty ? nil : ShoppingSection(aisle: aisle, lines: inAisle)
        }
    }

    /// « Poulets », « poulet » et « Poulet » donnent la même clé.
    static func normalizedKey(_ name: String) -> String {
        let folded = name
            .lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { word in
                word.count > 3 && (word.hasSuffix("s") || word.hasSuffix("x")) ? String(word.dropLast()) : String(word)
            }
        return folded.joined(separator: " ")
    }

    static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
}
