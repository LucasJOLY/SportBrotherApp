import Foundation

/// Recalcule les quantités d'une recette écrite pour 2 quand on la fait pour un autre nombre de personnes.
nonisolated enum QuantityScaler {
    /// Toutes les recettes sont écrites pour 2 personnes.
    static let baseServings = 2

    private static let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]

    /// « 3 c. à soupe » × 0,5 → « 1 ½ c. à soupe ». Les nombres suivis de « °», « % » ou « par personne » ne bougent pas.
    static func scale(_ text: String, by factor: Double) -> String {
        guard factor != 1, !text.isEmpty else { return text }
        let pattern = #"(\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?|[½¼¾⅓⅔])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let token = source.substring(with: match.range)
            let after = source.substring(from: match.range.location + match.range.length)
                .trimmingCharacters(in: .whitespaces).lowercased()
            if isFixed(after) {
                result += token
            } else if let value = number(token) {
                result += format(value * factor)
            } else {
                result += token
            }
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    /// Températures, pourcentages et quantités « par personne » ne dépendent pas du nombre de portions.
    private static func isFixed(_ after: String) -> Bool {
        after.hasPrefix("°") || after.hasPrefix("%")
            || after.range(of: #"^(g|kg|ml|cl|l)?\s*par personne"#, options: .regularExpression) != nil
    }

    /// Grammes arrondis à une valeur qu'on pèse vraiment.
    static func scaleGrams(_ grams: Double, by factor: Double) -> Double {
        guard grams > 0 else { return 0 }
        let value = grams * factor
        return value >= 50 ? (value / 5).rounded() * 5 : max(1, value.rounded())
    }

    static func number(_ token: String) -> Double? {
        if token.count == 1, let first = token.first, let fraction = fractions[first] { return fraction }
        if token.contains("/") {
            let parts = token.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]), bottom != 0 else { return nil }
            return top / bottom
        }
        return Double(token.replacingOccurrences(of: ",", with: "."))
    }

    /// 1.5 → « 1 ½ », 0.25 → « ¼ », 2.4 → « 2,4 ».
    static func format(_ value: Double) -> String {
        let whole = Int(value)
        let rest = value - Double(whole)
        let glyph: String? = switch rest {
        case ..<0.05: ""
        case 0.2..<0.3: "¼"
        case 0.3..<0.37: "⅓"
        case 0.45..<0.55: "½"
        case 0.62..<0.7: "⅔"
        case 0.7..<0.8: "¾"
        default: nil
        }
        if rest > 0.95 { return "\(whole + 1)" }
        guard let glyph else { return value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR"))) }
        if glyph.isEmpty { return "\(whole)" }
        return whole == 0 ? glyph : "\(whole) \(glyph)"
    }
}

extension Ingredient {
    func scaled(forServings servings: Int) -> Ingredient {
        let factor = Double(servings) / Double(QuantityScaler.baseServings)
        var copy = self
        copy.grams = QuantityScaler.scaleGrams(grams, by: factor)
        copy.detail = QuantityScaler.scale(detail, by: factor)
        return copy
    }
}
