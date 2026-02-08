//
//  LLMMessage.swift
//  HiDocu
//
//  Unified types for LLM chat interactions across providers.
//

import Foundation

/// A single message in an LLM conversation.
struct LLMMessage: Sendable, Equatable {
    enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

/// Configuration options for LLM API requests.
struct LLMRequestOptions: Sendable, Equatable {
    let maxTokens: Int?
    let temperature: Double?
    let systemPrompt: String?

    init(maxTokens: Int? = nil, temperature: Double? = nil, systemPrompt: String? = nil) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.systemPrompt = systemPrompt
    }
}

/// Response from an LLM chat completion request.
struct LLMResponse: Sendable, Equatable {
    let content: String
    let model: String
    let provider: LLMProvider
    let inputTokens: Int?
    let outputTokens: Int?
    let finishReason: String?
}

/// OAuth2 token bundle returned from authentication flows.
/// Contains provider-specific fields as optional properties.
struct OAuthTokenBundle: Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let email: String

    // Provider-specific optional fields
    let idToken: String?
    let accountId: String?
    let projectId: String?
    let clientSecret: String?

    init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        email: String,
        idToken: String? = nil,
        accountId: String? = nil,
        projectId: String? = nil,
        clientSecret: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.email = email
        self.idToken = idToken
        self.accountId = accountId
        self.projectId = projectId
        self.clientSecret = clientSecret
    }
}
