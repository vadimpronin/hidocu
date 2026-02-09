//
//  LLMAccount.swift
//  HiDocu
//
//  Represents an authenticated LLM provider account.
//

import Foundation

/// An authenticated account for a specific LLM provider.
/// Token credentials are stored separately in Keychain.
struct LLMAccount: Identifiable, Sendable, Equatable {
    let id: Int64
    var provider: LLMProvider
    var email: String
    var displayName: String
    var isActive: Bool
    var lastUsedAt: Date?
    var createdAt: Date
    var pausedUntil: Date? // When set, account is paused due to rate limiting until this time

    /// Keychain identifier for retrieving this account's tokens.
    /// Format: com.hidocu.llm.{provider}.{id}
    var keychainIdentifier: String {
        "com.hidocu.llm.\(provider.rawValue).\(id)"
    }
}
