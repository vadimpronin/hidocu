//
//  LLMError.swift
//  HiDocu
//
//  Typed errors for LLM operations with user-friendly descriptions.
//

import Foundation

/// Errors that can occur during LLM operations.
enum LLMError: LocalizedError, Sendable, Equatable {
    case noAccountsConfigured(LLMProvider)
    case authenticationFailed(provider: LLMProvider, detail: String)
    case tokenRefreshFailed(provider: LLMProvider, detail: String)
    case rateLimited(provider: LLMProvider, retryAfter: TimeInterval?)
    case apiError(provider: LLMProvider, statusCode: Int, message: String)
    case networkError(underlying: String)
    case invalidResponse(detail: String)
    case documentNotFound
    case generationCancelled
    case portInUse(port: UInt16)
    case oauthTimeout

    var errorDescription: String? {
        switch self {
        case .noAccountsConfigured(let provider):
            return "No \(provider.displayName) accounts configured. Please add an account in Settings."
        case .authenticationFailed(let provider, let detail):
            return "Authentication with \(provider.displayName) failed: \(detail)"
        case .tokenRefreshFailed(let provider, let detail):
            return "Failed to refresh \(provider.displayName) access token: \(detail)"
        case .rateLimited(let provider, let retryAfter):
            if let seconds = retryAfter {
                return "\(provider.displayName) rate limit exceeded. Retry after \(Int(seconds)) seconds."
            }
            return "\(provider.displayName) rate limit exceeded. Please try again later."
        case .apiError(let provider, let statusCode, let message):
            return "\(provider.displayName) API error (\(statusCode)): \(message)"
        case .networkError(let underlying):
            return "Network error: \(underlying)"
        case .invalidResponse(let detail):
            return "Invalid response from API: \(detail)"
        case .documentNotFound:
            return "Document not found."
        case .generationCancelled:
            return "Generation was cancelled."
        case .portInUse(let port):
            return "Port \(port) is already in use. Close other applications using this port and try again."
        case .oauthTimeout:
            return "OAuth authentication timed out. Please try again."
        }
    }

    static func == (lhs: LLMError, rhs: LLMError) -> Bool {
        switch (lhs, rhs) {
        case (.noAccountsConfigured(let lhsProvider), .noAccountsConfigured(let rhsProvider)):
            return lhsProvider == rhsProvider
        case (.authenticationFailed(let lhsProvider, let lhsDetail), .authenticationFailed(let rhsProvider, let rhsDetail)):
            return lhsProvider == rhsProvider && lhsDetail == rhsDetail
        case (.tokenRefreshFailed(let lhsProvider, let lhsDetail), .tokenRefreshFailed(let rhsProvider, let rhsDetail)):
            return lhsProvider == rhsProvider && lhsDetail == rhsDetail
        case (.rateLimited(let lhsProvider, let lhsRetry), .rateLimited(let rhsProvider, let rhsRetry)):
            return lhsProvider == rhsProvider && lhsRetry == rhsRetry
        case (.apiError(let lhsProvider, let lhsCode, let lhsMsg), .apiError(let rhsProvider, let rhsCode, let rhsMsg)):
            return lhsProvider == rhsProvider && lhsCode == rhsCode && lhsMsg == rhsMsg
        case (.networkError(let lhsUnderlying), .networkError(let rhsUnderlying)):
            return lhsUnderlying == rhsUnderlying
        case (.invalidResponse(let lhsDetail), .invalidResponse(let rhsDetail)):
            return lhsDetail == rhsDetail
        case (.documentNotFound, .documentNotFound):
            return true
        case (.generationCancelled, .generationCancelled):
            return true
        case (.portInUse(let lhsPort), .portInUse(let rhsPort)):
            return lhsPort == rhsPort
        case (.oauthTimeout, .oauthTimeout):
            return true
        default:
            return false
        }
    }
}
