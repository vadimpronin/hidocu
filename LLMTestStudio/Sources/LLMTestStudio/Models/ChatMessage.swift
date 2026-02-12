import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    var thinkingText: String
    var isStreaming: Bool

    enum Role {
        case user
        case assistant
    }

    init(role: Role, text: String, thinkingText: String = "", isStreaming: Bool = false) {
        self.role = role
        self.text = text
        self.thinkingText = thinkingText
        self.isStreaming = isStreaming
    }
}
