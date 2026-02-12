import Foundation
import OSLog

// MARK: - Provider Resolution & Networking

extension LLMService {

    internal func resolveProvider() throws -> InternalProvider {
        switch session.info.provider {
        case .claudeCode:
            return ClaudeCodeProvider()
        case .geminiCLI:
            let projectId = session.info.metadata["project_id"] ?? ""
            return GeminiCLIProvider(projectId: projectId)
        case .antigravity:
            let projectId = session.info.metadata["project_id"] ?? ""
            return AntigravityProvider(projectId: projectId)
        }
    }

    internal func getCredentialsWithRefresh(traceId: String) async throws -> LLMCredentials {
        let credentials = try await session.getCredentials()
        if let expiresAt = credentials.expiresAt, expiresAt <= Date() {
            return try await refreshAndSave(credentials: credentials, traceId: traceId)
        }
        return credentials
    }

    internal func refreshAndSave(credentials: LLMCredentials, traceId: String) async throws -> LLMCredentials {
        guard let refreshToken = credentials.refreshToken else {
            throw LLMServiceError(traceId: traceId, message: "No refresh token available")
        }
        let newCredentials = try await TokenRefresher.refresh(
            provider: session.info.provider,
            refreshToken: refreshToken,
            httpClient: makeTracingClient(traceId: traceId, method: "tokenRefresh")
        )
        try await session.save(info: session.info, credentials: newCredentials)
        return newCredentials
    }

    internal func withRetry<T>(
        request: URLRequest,
        traceId: String,
        perform: (URLRequest) async throws -> (T, HTTPURLResponse)
    ) async throws -> (T, HTTPURLResponse) {
        let (result, response) = try await perform(request)

        captureRateLimitHeaders(from: response)

        if response.statusCode == 401 {
            let credentials = try await session.getCredentials()
            guard let refreshToken = credentials.refreshToken else {
                throw LLMServiceError(traceId: traceId, message: "Unauthorized and no refresh token", statusCode: 401)
            }
            let newCredentials = try await TokenRefresher.refresh(
                provider: session.info.provider,
                refreshToken: refreshToken,
                httpClient: makeTracingClient(traceId: traceId, method: "tokenRefresh")
            )
            try await session.save(info: session.info, credentials: newCredentials)

            var newRequest = request
            let token = newCredentials.accessToken ?? newCredentials.apiKey ?? ""
            newRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (retryResult, retryResponse) = try await perform(newRequest)
            captureRateLimitHeaders(from: retryResponse)
            return (retryResult, retryResponse)
        }

        return (result, response)
    }

    internal func captureRateLimitHeaders(from response: HTTPURLResponse) {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            let keyStr = "\(key)".lowercased()
            if keyStr.hasPrefix("x-ratelimit") {
                headers[keyStr] = "\(value)"
            }
        }
        if !headers.isEmpty {
            lastResponseHeaders = headers
        }
    }

    internal func parseResetTime(_ value: String?) -> TimeInterval? {
        guard let str = value, !str.isEmpty else { return nil }

        // Raw number → treat as seconds
        if let raw = Double(str) {
            return raw
        }

        // Handle duration formats like "30s", "1m30s", "500ms"
        // Use a simple regex-free scan: collect number+suffix pairs
        var total: TimeInterval = 0
        var matched = false
        var remaining = str[str.startIndex...]

        while !remaining.isEmpty {
            // Skip non-digit prefix
            guard let digitStart = remaining.firstIndex(where: { $0.isNumber || $0 == "." }) else { break }
            remaining = remaining[digitStart...]

            // Collect digits
            let afterDigits = remaining.firstIndex(where: { !$0.isNumber && $0 != "." }) ?? remaining.endIndex
            guard let num = Double(remaining[remaining.startIndex..<afterDigits]) else { break }
            remaining = remaining[afterDigits...]

            // Check suffix
            if remaining.hasPrefix("ms") {
                total += num / 1000.0
                remaining = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...]
                matched = true
            } else if remaining.hasPrefix("h") {
                total += num * 3600
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
                matched = true
            } else if remaining.hasPrefix("m") {
                total += num * 60
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
                matched = true
            } else if remaining.hasPrefix("s") {
                total += num
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
                matched = true
            } else {
                break
            }
        }

        return matched ? total : nil
    }
}
