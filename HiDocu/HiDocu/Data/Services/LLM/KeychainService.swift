//
//  KeychainService.swift
//  HiDocu
//
//  Secure token storage using macOS Keychain.
//

import Foundation
import Security

/// Token data stored in Keychain for an LLM account.
struct TokenData: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let idToken: String?
    let accountId: String?
    let projectId: String?
    let clientId: String?
    let clientSecret: String?
}

/// Service for storing and retrieving LLM tokens from macOS Keychain.
///
/// Maintains an in-memory cache to avoid repeated `SecItemCopyMatching` calls,
/// which trigger macOS keychain password prompts when the keychain is locked.
final class KeychainService: @unchecked Sendable {
    private static let service = "com.hidocu.llm"

    private let lock = NSRecursiveLock()
    private var cache: [String: TokenData] = [:]
    private var hasLoadedAll = false

    private static let blobAccount = "all_tokens_storage"

    /// Internal storage for all tokens in a single keychain item
    private struct KeychainBlob: Codable {
        var tokens: [String: TokenData]
    }

    /// Saves token data to Keychain (in the single blob) and updates the in-memory cache.
    ///
    /// - Parameters:
    ///   - token: Token data to store
    ///   - identifier: Account identifier (format: com.hidocu.llm.{provider}.{id})
    /// - Throws: Keychain operation errors
    func saveToken(_ token: TokenData, identifier: String) throws {
        lock.lock()
        defer { lock.unlock() }

        // Update cache
        cache[identifier] = token
        
        // Save to blob
        try saveBlob(cache)
        
        // Try to delete legacy item to clean up
        try? deleteLegacyToken(identifier: identifier)
    }

    /// Loads token data, returning a cached value if available.
    /// Handles migration from legacy individual items to the single blob.
    ///
    /// - Parameter identifier: Account identifier
    /// - Returns: Token data if found, nil otherwise
    /// - Throws: Keychain operation errors
    func loadToken(identifier: String) throws -> TokenData? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[identifier] {
            return cached
        }
        
        // If we haven't loaded the blob yet, do it
        if !hasLoadedAll {
            // Try to load from blob
            if let blob = try? loadBlob() {
                self.cache = blob.tokens
                hasLoadedAll = true
                if let cached = cache[identifier] {
                    return cached
                }
            } else {
                // Blob not found or failed, mark as loaded anyway so we don't retry endlessly?
                // Actually, if blob doesn't exist, we start with empty cache (or whatever we have)
                // We shouldn't set hasLoadedAll to true if we didn't confirm emptiness, 
                // but if loadBlob fails (e.g. item not found), it's effectively empty.
                // We'll proceed to try legacy load.
                hasLoadedAll = true
            }
        }
        
        // Check cache again after blob load
        if let cached = cache[identifier] {
            return cached
        }

        // Fallback: Try to load from legacy individual item
        if let legacyToken = try? loadLegacyToken(identifier: identifier) {
            // Found legacy token! Migrate it.
            cache[identifier] = legacyToken
            
            // Save to blob
            // Note: We are holding the lock, so this is safe.
            // Ignore save errors during migration reading? best effort.
            try? saveBlob(cache)
            
            // Delete legacy item
            try? deleteLegacyToken(identifier: identifier)
            
            return legacyToken
        }

        return nil
    }

    /// Deletes token data from Keychain (blob) and removes it from cache.
    ///
    /// - Parameter identifier: Account identifier
    /// - Throws: Keychain operation errors
    func deleteToken(identifier: String) throws {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: identifier)
        try saveBlob(cache) // Save updated blob
        
        // Ensure legacy is gone too
        try? deleteLegacyToken(identifier: identifier)
    }

    /// Deletes all tokens from Keychain and clears the in-memory cache.
    func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        hasLoadedAll = false
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.general.error("Keychain deleteAll failed with status: \(status)")
        }
    }

    // MARK: - Blob Management

    private func loadBlob() throws -> KeychainBlob? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.blobAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(KeychainBlob.self, from: data)
    }

    private func saveBlob(_ tokens: [String: TokenData]) throws {
        let blob = KeychainBlob(tokens: tokens)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(blob)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.blobAccount
        ]

        // Delete existing blob
        SecItemDelete(query as CFDictionary)

        // Add new blob
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    // MARK: - Legacy Helpers

    private func loadLegacyToken(identifier: String) throws -> TokenData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TokenData.self, from: data)
    }

    private func deleteLegacyToken(identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: identifier
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save token to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load token from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete token from Keychain (status: \(status))"
        case .invalidData:
            return "Invalid token data in Keychain"
        }
    }
}
