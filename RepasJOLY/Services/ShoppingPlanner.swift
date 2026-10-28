import Foundation

/// Une occurrence d'ingrédient dans un repas de la semaine.
nonisolated struct ShoppingSource: Hashable, Sendable {
    let ref: String
    let recipeTitle: String
    let mealLabel: String
    let ingredient: Ingredient
    /// Le repas reste à cuisiner (ni fait, ni sauté, ni mangé dehors).
    let isRemaining: Bool
}

/// Ligne de courses consolidée : un produit, une unité, les occurrences qu'il couvre.
nonisolated struct ConsolidatedItem: Codable, Hashable, Sendable {
    struct Part: Codable, Hashable, Sendable {
        var ref: String
        /// Quantité dans l'unité de la ligne, 0 si inconnue.
        var amount: Double
    }

    var name: String
    var aisle: Aisle
    /// « g », « ml », « pièce », ou vide.
    var unit: String
    var isPantry: Bool
    var parts: [Part]

    var key: String { ShoppingListBuilder.normalizedKey(name) }
}

/// Ce qu'il reste à acheter pour une ligne, calculé localement.
nonisolated struct ShoppingNeed: Identifiable, Hashable, Sendable {
    struct Use: Hashable, Sendable {
        let recipeTitle: String
        let mealLabel: String
        let amount: Double
        let detail: String
    }

    let item: ConsolidatedItem
    let needed: Double
    /// Repas dont la quantité n'est pas précisée.
    let unknownMeals: Int
    let uses: [Use]
    let have: Double

    var id: String { item.key }
    var toBuy: Double { max(0, needed - have) }
    var isCoveredAtHome: Bool { needed > 0 && have >= needed }
    var recipes: [String] {
        var seen: Set<String> = []
        return uses.map(\.recipeTitle).filter { seen.insert($0).inserted }
    }

    /// « 250 g », « 3 », « pour 2 repas ».
    var quantityText: String? {
        if needed > 0 {
            let main = ShoppingPlanner.format(toBuy, unit: item.unit)
            return unknownMeals > 0 ? "\(main) +" : main
        }
        return unknownMeals > 1 ? "pour \(unknownMeals) repas" : nil
    }
}

nonisolated enum ShoppingPlanner {
    /// Empreinte stable des repas et ingrédients : l'IA ne repasse que si elle change.
    static func fingerprint(_ sources: [ShoppingSource]) -> String {
        let text = sources
            .map { "\($0.ref)|\($0.ingredient.name)|\($0.ingredient.grams)|\($0.ingredient.detail)" }
            .sorted()
            .joined(separator: "\n")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// Regroupement local (sans IA) : même nom normalisé, grammes additionnés.
    static func localItems(_ sources: [ShoppingSource]) -> [ConsolidatedItem] {
        var order: [String] = []
        var items: [String: ConsolidatedItem] = [:]
        for source in sources {
            let key = ShoppingListBuilder.normalizedKey(source.ingredient.name)
            guard !key.isEmpty else { continue }
            let part = ConsolidatedItem.Part(ref: source.ref, amount: source.ingredient.grams)
            if var item = items[key] {
                item.parts.append(part)
                if source.ingredient.grams > 0 { item.unit = "g" }
                item.isPantry = item.isPantry && source.ingredient.isPantry
                items[key] = item
            } else {
                order.append(key)
                items[key] = ConsolidatedItem(
                    name: ShoppingListBuilder.displayName(source.ingredient.name),
                    aisle: source.ingredient.aisle,
                    unit: source.ingredient.grams > 0 ? "g" : "",
                    isPantry: source.ingredient.isPantry,
                    parts: [part]
                )
            }
        }
        return order.compactMap { items[$0] }
    }

    /// Quantité lisible dans une précision (« 3 c. à soupe », « 50 cl », « 200 g »), convertie dans l'unité de l'article.
    static func estimatedAmount(detail: String, unit: String) -> Double {
        guard unit == "g" || unit == "ml" else { return 0 }
        let text = detail.lowercased()
        let pattern = #"(\d+(?:[.,]\d+)?|½|¼|¾)\s*(c\.? ?à ?s(?:oupe)?|c\.? ?à ?c(?:afé)?|cs|cc|kg|g|cl|ml|l)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = QuantityScaler.number(String(text[numberRange]))
        else { return 0 }
        let written = text[unitRange].replacingOccurrences(of: " ", with: "")
        switch written {
        case _ where written.hasPrefix("c.às") || written.hasPrefix("càs") || written == "cs": return value * 15
        case _ where written.hasPrefix("c.àc") || written.hasPrefix("càc") || written == "cc": return value * 5
        case "kg": return unit == "g" ? value * 1000 : 0
        case "g": return unit == "g" ? value : 0
        case "l": return unit == "ml" ? value * 1000 : 0
        case "cl": return unit == "ml" ? value * 10 : 0
        case "ml": return unit == "ml" ? value : 0
        default: return 0
        }
    }

    /// Fiabilise une réponse IA : chaque occurrence apparaît une seule fois, les oubliées sont regroupées localement,
    /// et les quantités laissées vides sont déduites de la précision quand c'est possible.
    static func repair(_ items: [ConsolidatedItem], sources: [ShoppingSource]) -> [ConsolidatedItem] {
        let known = Set(sources.map(\.ref))
        let byRef = Dictionary(uniqueKeysWithValues: sources.map { ($0.ref, $0) })
        var used: Set<String> = []
        var cleaned: [ConsolidatedItem] = []
        for var item in items {
            item.parts = item.parts.filter { known.contains($0.ref) && used.insert($0.ref).inserted }
            let unit = item.unit
            item.parts = item.parts.map { part in
                var amount = max(0, part.amount)
                if amount == 0, let source = byRef[part.ref] {
                    amount = source.ingredient.grams > 0 && unit == "g"
                        ? source.ingredient.grams
                        : estimatedAmount(detail: source.ingredient.detail, unit: unit)
                }
                return ConsolidatedItem.Part(ref: part.ref, amount: amount)
            }
            if !item.parts.isEmpty && !item.name.trimmingCharacters(in: .whitespaces).isEmpty { cleaned.append(item) }
        }
        let missing = sources.filter { !used.contains($0.ref) }
        for item in localItems(missing) {
            if let index = cleaned.firstIndex(where: { $0.key == item.key && ($0.unit == item.unit || item.unit.isEmpty) }) {
                cleaned[index].parts += item.parts
            } else {
                cleaned.append(item)
            }
        }
        return cleaned
    }

    /// Besoins restants : seuls les repas encore à cuisiner comptent.
    static func needs(_ items: [ConsolidatedItem], sources: [ShoppingSource], have: [String: Double]) -> [ShoppingNeed] {
        let byRef = Dictionary(uniqueKeysWithValues: sources.map { ($0.ref, $0) })
        return items.compactMap { item in
            let remaining = item.parts.compactMap { part in byRef[part.ref].flatMap { $0.isRemaining ? (part, $0) : nil } }
            guard !remaining.isEmpty else { return nil }
            let uses = remaining.map { part, source in
                ShoppingNeed.Use(recipeTitle: source.recipeTitle, mealLabel: source.mealLabel,
                                 amount: part.amount, detail: source.ingredient.detail)
            }
            return ShoppingNeed(
                item: item,
                needed: remaining.map(\.0.amount).reduce(0, +),
                unknownMeals: remaining.filter { $0.0.amount <= 0 }.count,
                uses: uses,
                have: have[item.key] ?? 0
            )
        }
    }

    /// 1250 g → « 1,25 kg », 3 pièces → « 3 ».
    static func format(_ value: Double, unit: String) -> String {
        let french = Locale(identifier: "fr_FR")
        func number(_ value: Double, digits: Int) -> String {
            value.formatted(.number.precision(.fractionLength(0...digits)).locale(french))
        }
        switch unit {
        case "g": return value >= 1000 ? "\(number(value / 1000, digits: 2)) kg" : "\(Int(value.rounded())) g"
        case "ml": return value >= 1000 ? "\(number(value / 1000, digits: 2)) L" : "\(Int(value.rounded())) ml"
        default: return number(value, digits: 1)
        }
    }
}

/// Saisie du frigo : « 500 g poulet », « poulet 500g », « 6 œufs », « 1,5 kg de bœuf ».
nonisolated enum StockEntry {
    static func parse(_ text: String) -> (name: String, amount: Double, unit: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let unitPattern = #"(kg|g|ml|cl|l)?"#
        let number = #"(\d+(?:[.,]\d+)?)"#
        let leading = try? NSRegularExpression(pattern: "^\(number)\\s*\(unitPattern)\\s+(?:de |d')?(.+)$", options: .caseInsensitive)
        let trailing = try? NSRegularExpression(pattern: "^(.+?)\\s+\(number)\\s*\(unitPattern)$", options: .caseInsensitive)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: trimmed) else { return "" }
            return String(trimmed[range])
        }
        func build(name: String, amount: String, unit: String) -> (String, Double, String) {
            let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            switch unit.lowercased() {
            case "kg": return (name, value * 1000, "g")
            case "g": return (name, value, "g")
            case "l": return (name, value * 1000, "ml")
            case "cl": return (name, value * 10, "ml")
            case "ml": return (name, value, "ml")
            default: return (name, value, "pièce")
            }
        }

        if let match = leading?.firstMatch(in: trimmed, range: range) {
            let entry = build(name: group(match, 3), amount: group(match, 1), unit: group(match, 2))
            return (ShoppingListBuilder.displayName(entry.0), entry.1, entry.2)
        }
        if let match = trailing?.firstMatch(in: trimmed, range: range) {
            let entry = build(name: group(match, 1), amount: group(match, 2), unit: group(match, 3))
            return (ShoppingListBuilder.displayName(entry.0), entry.1, entry.2)
        }
        return (ShoppingListBuilder.displayName(trimmed), 0, "")
    }
}
