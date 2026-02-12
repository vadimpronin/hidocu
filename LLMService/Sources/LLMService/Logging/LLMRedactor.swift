import CryptoKit
import Foundation

enum LLMRedactor {
    private static let sensitiveHeaders: Set<String> = [
        "authorization", "api-key", "x-goog-api-key", "cookie"
    ]

    private static let sensitiveJSONKeys: Set<String> = [
        "access_token", "refresh_token", "session_key", "api_key"
    ]

    static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var redacted = headers
        for (key, value) in headers {
            if sensitiveHeaders.contains(key.lowercased()) {
                redacted[key] = redactValue(value)
            }
        }
        return redacted
    }

    static func redactJSONBody(_ data: Data) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) else {
            return data
        }
        json = redactJSONObject(json)
        guard let redactedData = try? JSONSerialization.data(withJSONObject: json) else {
            return data
        }
        return redactedData
    }

    private static func redactJSONObject(_ object: Any) -> Any {
        if var dict = object as? [String: Any] {
            for (key, value) in dict {
                if sensitiveJSONKeys.contains(key), let stringValue = value as? String {
                    dict[key] = redactValue(stringValue)
                } else {
                    dict[key] = redactJSONObject(value)
                }
            }
            return dict
        } else if let array = object as? [Any] {
            return array.map { redactJSONObject($0) }
        }
        return object
    }

    private static func redactValue(_ value: String) -> String {
        let hash = SHA256.hash(data: Data(value.utf8))
        let hexString = hash.map { String(format: "%02x", $0) }.joined()
        let suffix = String(hexString.suffix(4))
        return "REDACTED (\(suffix))"
    }
}
