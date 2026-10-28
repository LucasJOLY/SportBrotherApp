import Foundation

nonisolated enum ImportError: LocalizedError {
    case invalidURL
    case unreadable

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Ce lien n'est pas valide."
        case .unreadable: "Impossible de lire une recette sur cette page."
        }
    }
}

/// Récupère le texte d'une recette depuis une page web, en limitant ce qui part à l'IA.
nonisolated enum RecipeImporter {
    static func fetchText(from link: String) async throws -> String {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, ["http", "https"].contains(scheme) else { throw ImportError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(decoding: data, as: UTF8.self)
        guard let text = extractText(fromHTML: html) else { throw ImportError.unreadable }
        return "Source : \(url.absoluteString)\n\(text)"
    }

    /// 1. Recette structurée (JSON-LD, présente sur la plupart des sites de cuisine).
    /// 2. Description de partage (légende Instagram…). 3. Texte brut de la page, tronqué.
    static func extractText(fromHTML html: String) -> String? {
        if let recipe = jsonLDRecipe(in: html) { return recipe }
        let title = meta("og:title", in: html) ?? firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html)
        if let description = meta("og:description", in: html), description.count > 80 {
            return [title, description].compactMap { $0 }.map(decodeEntities).joined(separator: "\n")
        }
        let body = plainText(html)
        guard body.count > 200 else { return nil }
        return String(body.prefix(8000))
    }

    static func jsonLDRecipe(in html: String) -> String? {
        let scripts = allMatches(#"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#, in: html)
        for script in scripts {
            guard let data = script.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let recipe = findRecipe(in: json) else { continue }
            var lines: [String] = []
            if let name = recipe["name"] as? String { lines.append(name) }
            if let servings = recipe["recipeYield"] { lines.append("Pour : \(flatten(servings).joined(separator: ", "))") }
            let ingredients = flatten(recipe["recipeIngredient"] ?? [])
            if !ingredients.isEmpty { lines.append("Ingrédients :\n- " + ingredients.joined(separator: "\n- ")) }
            let steps = instructions(recipe["recipeInstructions"] ?? [])
            if !steps.isEmpty { lines.append("Étapes :\n" + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")) }
            guard !ingredients.isEmpty || !steps.isEmpty else { continue }
            return decodeEntities(lines.joined(separator: "\n"))
        }
        return nil
    }

    private static func findRecipe(in json: Any) -> [String: Any]? {
        if let object = json as? [String: Any] {
            let type = object["@type"]
            if (type as? String) == "Recipe" || (type as? [String])?.contains("Recipe") == true { return object }
            if let graph = object["@graph"] { return findRecipe(in: graph) }
        }
        if let array = json as? [Any] {
            for item in array { if let recipe = findRecipe(in: item) { return recipe } }
        }
        return nil
    }

    private static func instructions(_ value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let object = value as? [String: Any] {
            if let items = object["itemListElement"] { return instructions(items) }
            if let text = object["text"] as? String { return [text] }
            return []
        }
        if let array = value as? [Any] { return array.flatMap(instructions) }
        return []
    }

    private static func flatten(_ value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let number = value as? NSNumber { return [number.stringValue] }
        if let array = value as? [Any] { return array.flatMap(flatten) }
        return []
    }

    /// Contenu d'une balise meta, entre guillemets doubles ou simples (une légende contient souvent des apostrophes).
    private static func meta(_ property: String, in html: String) -> String? {
        for quote in ["\"", "'"] {
            let value = "\(quote)([^\(quote)]*)\(quote)"
            let key = "(?:property|name)=[\"']\(property)[\"']"
            if let found = firstMatch("<meta[^>]+\(key)[^>]+content=\(value)", in: html)
                ?? firstMatch("<meta[^>]+content=\(value)[^>]+\(key)", in: html) {
                return found
            }
        }
        return nil
    }

    private static func plainText(_ html: String) -> String {
        var text = html
        for pattern in [#"<script.*?</script>"#, #"<style.*?</style>"#, #"<[^>]+>"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return decodeEntities(text).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
         ("&lt;", "<"), ("&gt;", ">"), ("&eacute;", "é"), ("&egrave;", "è"), ("&agrave;", "à"), ("&ccedil;", "ç")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        allMatches(pattern, in: text).first
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            match.numberOfRanges > 1 ? source.substring(with: match.range(at: 1)) : nil
        }
    }
}
