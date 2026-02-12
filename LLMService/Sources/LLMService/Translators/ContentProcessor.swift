import Foundation
import UniformTypeIdentifiers

enum ContentProcessor {
    enum ProcessedContent: Sendable {
        case text(String)
        case binary(Data, mimeType: String, filename: String?)
    }

    static func processContent(_ content: LLMContent) throws -> ProcessedContent {
        switch content {
        case .text(let string):
            return .text(string)

        case .thinking(let string, _):
            return .text(string)

        case .file(let url):
            return try processFileURL(url)

        case .fileContent(let data, let mimeType, let filename):
            return .binary(data, mimeType: mimeType, filename: filename)
        }
    }

    private static func processFileURL(_ url: URL) throws -> ProcessedContent {
        let filename = url.lastPathComponent
        let utType = UTType(filenameExtension: url.pathExtension)

        if let utType, utType.conforms(to: .image) {
            let data = try Data(contentsOf: url)
            let mimeType = utType.preferredMIMEType ?? "application/octet-stream"
            return .binary(data, mimeType: mimeType, filename: filename)
        }

        if let utType, utType.conforms(to: .audio) {
            let data = try Data(contentsOf: url)
            let mimeType = utType.preferredMIMEType ?? "application/octet-stream"
            return .binary(data, mimeType: mimeType, filename: filename)
        }

        if let utType, utType.conforms(to: .audiovisualContent) {
            let data = try Data(contentsOf: url)
            let mimeType = utType.preferredMIMEType ?? "application/octet-stream"
            return .binary(data, mimeType: mimeType, filename: filename)
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        return .text("--- FILE: \(filename) ---\n\(text)\n--- END FILE ---")
    }
}
