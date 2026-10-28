import Foundation

nonisolated enum ClaudeError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case refused
    case truncated
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Aucune clé API Claude n'est configurée (Config/Secrets.xcconfig)."
        case .http(let status, let message): "Claude a répondu \(status) : \(message)"
        case .refused: "Claude a refusé cette demande. Reformule-la."
        case .truncated: "La réponse de Claude a été coupée. Réessaie avec une demande plus courte."
        case .invalidResponse: "La réponse de Claude est illisible. Réessaie."
        }
    }
}

nonisolated struct ClaudeUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int
}

/// Client minimal de l'API Messages : un appel = un JSON validé par schéma.
nonisolated struct ClaudeClient: Sendable {
    static let model = "claude-haiku-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String

    static var configured: ClaudeClient? {
        let key = (Bundle.main.object(forInfoDictionaryKey: "ClaudeAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-") else { return nil }
        return ClaudeClient(apiKey: key)
    }

    enum Effort: String { case low, medium }

    func send<Output: Decodable>(
        _ type: Output.Type,
        system: String,
        prompt: String,
        images: [Data] = [],
        schema: [String: Any],
        maxTokens: Int,
        effort: Effort = .low,
        thinks: Bool = false
    ) async throws -> (Output, ClaudeUsage) {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "system": system,
            // Réflexion réservée à la création de recettes ; elle compte dans max_tokens.
            "thinking": ["type": thinks ? "adaptive" : "disabled"],
            "output_config": [
                "effort": effort.rawValue,
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": Self.content(prompt: prompt, images: images)]],
        ]

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
            throw ClaudeError.http(status: status, message: message ?? "erreur inconnue")
        }

        let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
        switch envelope.stopReason {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        guard let text = envelope.content.first(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8),
              let output = try? JSONDecoder().decode(Output.self, from: json)
        else { throw ClaudeError.invalidResponse }

        let usage = ClaudeUsage(inputTokens: envelope.usage.inputTokens, outputTokens: envelope.usage.outputTokens)
        #if DEBUG
        print("[Claude] \(Output.self): \(usage.inputTokens) in / \(usage.outputTokens) out")
        #endif
        return (output, usage)
    }
}

extension ClaudeClient {
    /// Texte seul, ou images JPEG suivies du texte.
    nonisolated static func content(prompt: String, images: [Data]) -> Any {
        guard !images.isEmpty else { return prompt }
        let imageBlocks: [[String: Any]] = images.map { data in
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
        }
        return imageBlocks + [["type": "text", "text": prompt]]
    }
}

private nonisolated struct MessageEnvelope: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
    let content: [Block]
    let stopReason: String?
    let usage: Usage
    enum CodingKeys: String, CodingKey {
        case content, usage
        case stopReason = "stop_reason"
    }
}

private nonisolated struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}
