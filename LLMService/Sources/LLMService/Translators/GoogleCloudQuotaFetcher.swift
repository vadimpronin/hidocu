import Foundation
import OSLog

private let logger = Logger(subsystem: "com.llmservice", category: "GoogleCloudQuotaFetcher")

/// Fetches available model IDs from the Google Cloud Code retrieveUserQuota endpoint.
///
/// Used by both GeminiCLIProvider and AntigravityProvider to discover
/// which models the user has access to.
enum GoogleCloudQuotaFetcher {

    private static let quotaURL = URL(
        string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    )!

    /// Fetches model IDs available to the user from the retrieveUserQuota endpoint.
    ///
    /// Filters out `_vertex` suffixed duplicates and returns unique base model IDs.
    ///
    /// - Parameters:
    ///   - projectId: Google Cloud project ID
    ///   - credentials: Valid credentials with access token
    ///   - httpClient: HTTP client for making the request
    ///   - userAgent: User-Agent header value (differs between GeminiCLI and Antigravity)
    ///   - apiClient: X-Goog-Api-Client header value
    /// - Returns: Sorted array of unique model ID strings
    static func fetchAvailableModelIds(
        projectId: String,
        credentials: LLMCredentials,
        httpClient: HTTPClient,
        userAgent: String,
        apiClient: String
    ) async throws -> [String] {
        let token = credentials.accessToken ?? ""

        var request = URLRequest(url: quotaURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(apiClient, forHTTPHeaderField: "X-Goog-Api-Client")

        let body: [String: Any] = ["project": projectId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: request)

        guard (200..<300).contains(response.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("retrieveUserQuota failed with status \(response.statusCode): \(errorMsg)")
            throw LLMServiceError(
                traceId: "quota",
                message: "retrieveUserQuota failed: \(errorMsg)",
                statusCode: response.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["buckets"] as? [[String: Any]] else {
            throw LLMServiceError(
                traceId: "quota",
                message: "Missing buckets in retrieveUserQuota response"
            )
        }

        // Extract unique model IDs, removing _vertex suffix duplicates
        var modelIds = Set<String>()
        for bucket in buckets {
            if let modelId = bucket["modelId"] as? String, !modelId.isEmpty {
                let baseModel = modelId.hasSuffix("_vertex")
                    ? String(modelId.dropLast(7))
                    : modelId
                modelIds.insert(baseModel)
            }
        }

        let sorted = modelIds.sorted()
        logger.info("retrieveUserQuota returned \(sorted.count) unique models")
        return sorted
    }
}
