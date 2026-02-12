import Foundation

struct ChatAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let mimeType: String

    var isImage: Bool { mimeType.hasPrefix("image/") }

    var fileExtension: String {
        switch mimeType.lowercased() {
        case "image/png": "png"
        case "image/jpeg", "image/jpg": "jpg"
        case "image/gif": "gif"
        case "image/webp": "webp"
        default: "bin"
        }
    }

    static func decodeBase64(_ base64: String, mimeType: String) -> ChatAttachment? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return ChatAttachment(data: data, mimeType: mimeType)
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    var thinkingText: String
    var isStreaming: Bool
    var attachments: [ChatAttachment]

    enum Role {
        case user
        case assistant
    }

    init(role: Role, text: String, thinkingText: String = "", isStreaming: Bool = false, attachments: [ChatAttachment] = []) {
        self.role = role
        self.text = text
        self.thinkingText = thinkingText
        self.isStreaming = isStreaming
        self.attachments = attachments
    }
}
