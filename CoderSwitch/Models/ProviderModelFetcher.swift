import Foundation

enum ProviderModelFetchError: LocalizedError {
    case missingAPIKey
    case httpStatus(Int)
    case unparseableResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "no API key"
        case .httpStatus(let status): "HTTP \(status)"
        case .unparseableResponse: "could not parse models response"
        }
    }
}

struct ProviderModelFetcher: Sendable {
    func fetchModels(account: Account, apiKey: String?) async throws -> [ProviderModel] {
        guard let apiKey, !apiKey.isEmpty else {
            throw ProviderModelFetchError.missingAPIKey
        }
        let url = try modelsURL(endpoint: account.endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch account.provider.compatibility {
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ProviderModelFetchError.httpStatus(status)
        }
        let models = try parseModels(data)
        guard !models.isEmpty else {
            throw ProviderModelFetchError.unparseableResponse
        }
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private func modelsURL(endpoint: String) throws -> URL {
        var base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/models") else {
            throw URLError(.badURL)
        }
        return url
    }

    private func parseModels(_ data: Data) throws -> [ProviderModel] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else {
            throw ProviderModelFetchError.unparseableResponse
        }

        return entries.compactMap { entry in
            guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
            let name = entry["name"] as? String
                ?? entry["display_name"] as? String
            let ownedBy = entry["owned_by"] as? String
                ?? entry["ownedBy"] as? String
            return ProviderModel(id: id, name: name, ownedBy: ownedBy)
        }
    }
}
