import Foundation

/// Handles Claude/Anthropic OAuth authentication with PKCE
enum ClaudeCodeAuthProvider {

    private static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authURL = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let scopes = "org:create_api_key user:profile user:inference"

    // MARK: - Callback Configuration

    static let callbackPort: UInt16 = 54545
    static let callbackPath = "/callback"

    static var redirectURI: String {
        "http://localhost:\(callbackPort)\(callbackPath)"
    }

    /// Build the OAuth authorization URL with PKCE challenge
    static func buildAuthURL(
        pkceCodes: PKCEGenerator.PKCECodes,
        state: String,
        redirectURI: String
    ) -> URL {
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkceCodes.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Exchange authorization code for access and refresh tokens
    static func exchangeCodeForTokens(
        code: String,
        state: String,
        pkceCodes: PKCEGenerator.PKCECodes,
        redirectURI: String,
        httpClient: HTTPClient
    ) async throws -> (credentials: LLMCredentials, email: String?) {
        let body: [String: String] = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "code_verifier": pkceCodes.codeVerifier,
        ]

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: request)

        guard response.statusCode == 200 else {
            throw LLMServiceError(
                traceId: "claude-auth",
                message: "Token exchange failed with status \(response.statusCode)",
                statusCode: response.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw LLMServiceError(traceId: "claude-auth", message: "Invalid token response")
        }

        let refreshToken = json["refresh_token"] as? String
        let expiresIn = json["expires_in"] as? TimeInterval
        let email = (json["account"] as? [String: Any])?["email_address"] as? String

        let credentials = LLMCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresIn.map { Date(timeIntervalSinceNow: $0) }
        )

        return (credentials, email)
    }

    /// Refresh access token using a refresh token
    static func refreshToken(
        refreshToken: String,
        httpClient: HTTPClient
    ) async throws -> LLMCredentials {
        let body: [String: String] = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: request)

        guard response.statusCode == 200 else {
            throw LLMServiceError(
                traceId: "claude-refresh",
                message: "Token refresh failed with status \(response.statusCode)",
                statusCode: response.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw LLMServiceError(traceId: "claude-refresh", message: "Invalid refresh response")
        }

        let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
        let expiresIn = json["expires_in"] as? TimeInterval

        return LLMCredentials(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresIn.map { Date(timeIntervalSinceNow: $0) }
        )
    }
}
