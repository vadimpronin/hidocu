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

    private let lock = NSLock()
    private var cache: [String: TokenData] = [:]

    /// Saves token data to Keychain and updates the in-memory cache.
    ///
    /// - Parameters:
    ///   - token: Token data to store
    ///   - identifier: Account identifier (format: com.hidocu.llm.{provider}.{id})
    /// - Throws: Keychain operation errors
    func saveToken(_ token: TokenData, identifier: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tokenData = try encoder.encode(token)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }

        lock.lock()
        cache[identifier] = token
        lock.unlock()
    }

    /// Loads token data, returning a cached value if available.
    /// Only hits the keychain once per identifier per app session.
    ///
    /// - Parameter identifier: Account identifier
    /// - Returns: Token data if found, nil otherwise
    /// - Throws: Keychain operation errors
    func loadToken(identifier: String) throws -> TokenData? {
        lock.lock()
        if let cached = cache[identifier] {
            lock.unlock()
            return cached
        }
        lock.unlock()

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

        guard let tokenData = result as? Data else {
            throw KeychainError.invalidData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let token = try decoder.decode(TokenData.self, from: tokenData)

        lock.lock()
        cache[identifier] = token
        lock.unlock()

        return token
    }

    /// Deletes token data from Keychain and removes it from cache.
    ///
    /// - Parameter identifier: Account identifier
    /// - Throws: Keychain operation errors (errSecItemNotFound is not thrown)
    func deleteToken(identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: identifier
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }

        lock.lock()
        cache.removeValue(forKey: identifier)
        lock.unlock()
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
