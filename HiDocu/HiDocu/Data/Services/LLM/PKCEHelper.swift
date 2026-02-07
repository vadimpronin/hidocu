//
//  PKCEHelper.swift
//  HiDocu
//
//  PKCE (Proof Key for Code Exchange) code generation for OAuth2 flows.
//

import Foundation
import Security
import CryptoKit

/// PKCE code pair for OAuth2 authorization.
struct PKCECodes: Sendable {
    let codeVerifier: String
    let codeChallenge: String
}

/// Helper for generating PKCE codes and state parameters per RFC 7636.
enum PKCEHelper {
    /// Generates a PKCE code verifier and challenge pair.
    ///
    /// The code verifier is a cryptographically random 128-character URL-safe base64 string.
    /// The code challenge is the SHA256 hash of the verifier, also base64url-encoded.
    ///
    /// - Returns: PKCE codes containing verifier and challenge
    /// - Throws: Error if random number generation fails
    static func generatePKCECodes() throws -> PKCECodes {
        let codeVerifier = try generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        return PKCECodes(codeVerifier: codeVerifier, codeChallenge: codeChallenge)
    }

    /// Generates a random state parameter for CSRF protection.
    ///
    /// - Returns: 32-character hexadecimal string
    /// - Throws: Error if random number generation fails
    static func generateState() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard result == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: "Failed to generate random bytes for state"]
            )
        }

        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    /// Generates a cryptographically random code verifier.
    /// Uses 96 random bytes which produces 128 base64 characters (no padding).
    private static func generateCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 96)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard result == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: "Failed to generate random bytes for code verifier"]
            )
        }

        let data = Data(bytes)
        return data.base64URLEncodedString()
    }

    /// Generates a code challenge from a verifier using SHA256.
    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

// MARK: - Data Extension

private extension Data {
    /// Encodes data to base64url format (RFC 4648 Section 5).
    /// Replaces + with -, / with _, and removes padding (=).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
