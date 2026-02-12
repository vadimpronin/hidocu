import Foundation

public enum LLMContent: Sendable {
    case text(String)
    case thinking(String, signature: String?)
    case file(URL)
    case fileContent(Data, mimeType: String, filename: String?)
}
