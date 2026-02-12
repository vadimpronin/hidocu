import CryptoKit
import Foundation

/// Caches thought signatures from Gemini/Antigravity responses so they can be
/// replayed on subsequent requests. Signatures are keyed by SHA-256 of the
/// model group + thinking text and expire after 3 hours.
actor ThoughtSignatureCache {
    static let shared = ThoughtSignatureCache()
    static let sentinel = "skip_thought_signature_validator"

    private static let minValidLength = 50
    private static let ttl: TimeInterval = 3 * 60 * 60 // 3 hours

    private var entries: [String: (signature: String, timestamp: Date)] = [:]

    // MARK: - Public

    func cache(modelName: String, thinkingText: String, signature: String) {
        let key = Self.cacheKey(modelName: modelName, thinkingText: thinkingText)
        entries[key] = (signature: signature, timestamp: Date())
    }

    func getCachedSignature(modelName: String, thinkingText: String) -> String? {
        let key = Self.cacheKey(modelName: modelName, thinkingText: thinkingText)
        cleanExpired()

        if let entry = entries[key] {
            return entry.signature
        }

        // For Gemini models, return sentinel when no cache hit
        if Self.modelGroup(modelName) == "gemini" {
            return Self.sentinel
        }

        return nil
    }

    // MARK: - Static Helpers

    static func isValid(_ signature: String) -> Bool {
        guard !signature.isEmpty else { return false }
        return signature.count >= minValidLength || signature == sentinel
    }

    static func modelGroup(_ modelName: String) -> String {
        let lower = modelName.lowercased()
        if lower.contains("gemini") { return "gemini" }
        if lower.contains("claude") { return "claude" }
        return "unknown"
    }

    // MARK: - Private

    private static func cacheKey(modelName: String, thinkingText: String) -> String {
        let group = modelGroup(modelName)
        let input = group + thinkingText
        let hash = SHA256.hash(data: Data(input.utf8))
        // Truncate to 16 hex chars
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func cleanExpired() {
        let now = Date()
        entries = entries.filter { now.timeIntervalSince($0.value.timestamp) < Self.ttl }
    }
}
