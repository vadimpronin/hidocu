import Foundation

/// Handles Google OAuth for GeminiCLI and Antigravity providers
enum GoogleOAuthProvider {

    // MARK: - Endpoints

    private static let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json")!
    private static let loadCodeAssistURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!

    // MARK: - GeminiCLI OAuth

    private static let geminiClientId = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
    private static let geminiClientSecret = "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"
    private static let geminiScopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
    ].joined(separator: " ")

    // MARK: - Antigravity OAuth

    private static let antigravityClientId = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private static let antigravityClientSecret = "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"
    private static let antigravityScopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs",
    ].joined(separator: " ")

    // MARK: - Helpers

    /// Character set for form URL encoding (RFC 3986 unreserved characters)
    private static let formEncodingAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    private static func clientId(for provider: LLMProvider) -> String {
        provider == .antigravity ? antigravityClientId : geminiClientId
    }

    private static func clientSecret(for provider: LLMProvider) -> String {
        provider == .antigravity ? antigravityClientSecret : geminiClientSecret
    }

    private static func scopes(for provider: LLMProvider) -> String {
        provider == .antigravity ? antigravityScopes : geminiScopes
    }

    // MARK: - Auth URL

    /// Build Google OAuth authorization URL
    static func buildAuthURL(
        provider: LLMProvider,
        state: String,
        callbackScheme: String
    ) -> URL {
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "client_id", value: clientId(for: provider)),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://auth/callback"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes(for: provider)),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    // MARK: - Token Exchange

    /// Exchange authorization code for tokens, then fetch user email
    static func exchangeCodeForTokens(
        code: String,
        provider: LLMProvider,
        callbackScheme: String,
        httpClient: HTTPClient
    ) async throws -> (credentials: LLMCredentials, email: String?) {
        let params: [(String, String)] = [
            ("code", code),
            ("client_id", clientId(for: provider)),
            ("client_secret", clientSecret(for: provider)),
            ("redirect_uri", "\(callbackScheme)://auth/callback"),
            ("grant_type", "authorization_code"),
        ]

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(params)

        let (data, response) = try await httpClient.data(for: request)

        guard response.statusCode == 200 else {
            throw LLMServiceError(
                traceId: "google-auth",
                message: "Token exchange failed with status \(response.statusCode)",
                statusCode: response.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw LLMServiceError(traceId: "google-auth", message: "Invalid token response")
        }

        let refreshToken = json["refresh_token"] as? String
        let expiresIn = json["expires_in"] as? TimeInterval

        let credentials = LLMCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresIn.map { Date(timeIntervalSinceNow: $0) }
        )

        let email = try? await fetchUserInfo(accessToken: accessToken, httpClient: httpClient)

        return (credentials, email)
    }

    // MARK: - User Info

    /// Fetch user email from Google userinfo endpoint
    static func fetchUserInfo(
        accessToken: String,
        httpClient: HTTPClient
    ) async throws -> String {
        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await httpClient.data(for: request)

        guard response.statusCode == 200 else {
            throw LLMServiceError(
                traceId: "google-userinfo",
                message: "User info fetch failed with status \(response.statusCode)",
                statusCode: response.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            throw LLMServiceError(traceId: "google-userinfo", message: "No email in user info response")
        }

        return email
    }

    // MARK: - Project ID (Antigravity)

    /// Fetch Antigravity project ID via loadCodeAssist
    static func fetchProjectID(
        accessToken: String,
        httpClient: HTTPClient
    ) async throws -> String {
        let body: [String: Any] = [
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI",
            ]
        ]

        var request = URLRequest(url: loadCodeAssistURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("google-api-nodejs-client/9.15.1", forHTTPHeaderField: "User-Agent")
        request.setValue("google-cloud-sdk vscode_cloudshelleditor/0.1", forHTTPHeaderField: "X-Goog-Api-Client")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: request)

        guard response.statusCode == 200 else {
            throw LLMServiceError(
                traceId: "antigravity-project",
                message: "loadCodeAssist failed with status \(response.statusCode)",
                statusCode: response.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projectId = json["cloudaicompanionProject"] as? String else {
            throw LLMServiceError(
                traceId: "antigravity-project",
                message: "No cloudaicompanionProject in loadCodeAssist response"
            )
        }

        return projectId
    }

    // MARK: - Token Refresh

    /// Refresh Google access token using a refresh token (form-encoded)
    static func refreshToken(
        refreshToken: String,
        provider: LLMProvider,
        httpClient: HTTPClient
    ) async throws -> LLMCredentials {
        let params: [(String, String)] = [
            ("client_id", clientId(for: provider)),
            ("client_secret", clientSecret(for: provider)),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ]

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(params)

        let (data, response) = try await httpClient.data(for: request)

        guard response.statusCode == 200 else {
            throw LLMServiceError(
                traceId: "google-refresh",
                message: "Token refresh failed with status \(response.statusCode)",
                statusCode: response.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw LLMServiceError(traceId: "google-refresh", message: "Invalid refresh response")
        }

        // Google may or may not return a new refresh token; keep the old one if not provided
        let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
        let expiresIn = json["expires_in"] as? TimeInterval

        return LLMCredentials(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresIn.map { Date(timeIntervalSinceNow: $0) }
        )
    }

    /// Encode key-value pairs as application/x-www-form-urlencoded
    private static func formEncode(_ params: [(String, String)]) -> Data {
        let encoded = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: formEncodingAllowedCharacters) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: formEncodingAllowedCharacters) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}
