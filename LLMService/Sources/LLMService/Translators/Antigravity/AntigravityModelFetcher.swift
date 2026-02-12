import Foundation
import OSLog

private let logger = Logger(subsystem: "com.llmservice", category: "AntigravityModelFetcher")

/// Fetches available models from the Antigravity fetchAvailableModels endpoint
enum AntigravityModelFetcher {

    private static let modelsURL = URL(
        string: "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
    )!

    /// Models to skip from the listing
    private static let skippedModels: Set<String> = [
        "chat_20706", "chat_23310",
    ]

    /// Fetches available models from the fetchAvailableModels endpoint.
    ///
    /// - Parameters:
    ///   - credentials: Valid credentials with access token
    ///   - httpClient: HTTP client for making the request
    /// - Returns: Array of (id, displayName) tuples sorted by model ID
    static func fetchAvailableModels(
        credentials: LLMCredentials,
        httpClient: HTTPClient
    ) async throws -> [(id: String, displayName: String)] {
        let token = credentials.accessToken ?? ""

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/1.104.0 darwin/arm64", forHTTPHeaderField: "User-Agent")

        request.httpBody = try JSONSerialization.data(withJSONObject: [:] as [String: Any])

        let (data, response) = try await httpClient.data(for: request)

        guard (200..<300).contains(response.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("fetchAvailableModels failed with status \(response.statusCode): \(errorMsg)")
            throw LLMServiceError(
                traceId: "antigravity-models",
                message: "fetchAvailableModels failed: \(errorMsg)",
                statusCode: response.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [String: Any] else {
            throw LLMServiceError(
                traceId: "antigravity-models",
                message: "Missing models in fetchAvailableModels response"
            )
        }

        var result: [(id: String, displayName: String)] = []
        for (modelId, modelData) in models {
            let trimmedId = modelId.trimmingCharacters(in: .whitespaces)
            guard !trimmedId.isEmpty, !skippedModels.contains(trimmedId) else { continue }

            var displayName = trimmedId
            if let modelInfo = modelData as? [String: Any],
               let name = modelInfo["displayName"] as? String, !name.isEmpty {
                displayName = name
            }
            result.append((id: trimmedId, displayName: displayName))
        }

        let sorted = result.sorted { $0.id < $1.id }
        logger.info("fetchAvailableModels returned \(sorted.count) models")
        return sorted
    }
}
