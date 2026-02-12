import CryptoKit
import Foundation

enum PKCEGenerator {
    struct PKCECodes: Sendable {
        let codeVerifier: String
        let codeChallenge: String
    }

    static func generate() throws -> PKCECodes {
        var bytes = [UInt8](repeating: 0, count: 96)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw LLMServiceError(
                traceId: "pkce-gen",
                message: "Failed to generate random bytes: SecRandomCopyBytes returned \(status)"
            )
        }
        let verifier = Data(bytes).base64URLEncodedString()
        let challenge = SHA256.hash(data: Data(verifier.utf8)).base64URLEncodedString()
        return PKCECodes(codeVerifier: verifier, codeChallenge: challenge)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SHA256Digest {
    func base64URLEncodedString() -> String {
        Data(self).base64URLEncodedString()
    }
}
