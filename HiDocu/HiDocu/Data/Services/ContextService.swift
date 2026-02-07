//
//  ContextService.swift
//  HiDocu
//
//  Context building and token counting for LLM context management.
//

import Foundation
import AppKit

@Observable
final class ContextService {

    private let folderRepository: any FolderRepository
    private let documentRepository: any DocumentRepository
    private let folderService: FolderService

    init(
        folderRepository: any FolderRepository,
        documentRepository: any DocumentRepository,
        folderService: FolderService
    ) {
        self.folderRepository = folderRepository
        self.documentRepository = documentRepository
        self.folderService = folderService
    }

    /// Build context string for a folder (recursive).
    /// Uses summaryText or bodyPreview from DB cache — no disk reads needed.
    func buildContext(folderId: Int64) async throws -> String {
        let folderIds = try await folderRepository.fetchDescendantIds(rootId: folderId)
        let documents = try await documentRepository.fetchAllRecursive(folderIds: folderIds)
        let resolvedPreferSummary = try await folderService.resolvePreferSummary(folderId: folderId)

        var parts: [String] = []
        for doc in documents {
            let preferSummary = doc.preferSummary || resolvedPreferSummary

            let text: String?
            if preferSummary, let summary = doc.summaryText, !summary.isEmpty {
                text = summary
            } else if let body = doc.bodyPreview, !body.isEmpty {
                text = body
            } else {
                text = doc.summaryText ?? doc.bodyPreview
            }

            if let text, !text.isEmpty {
                parts.append("## \(doc.title)\n\n\(text)")
            }
        }

        return parts.joined(separator: "\n\n---\n\n")
    }

    /// Calculate total byte count for a folder (from DB cache).
    func calculateByteCount(folderId: Int64) async throws -> Int {
        let folderIds = try await folderRepository.fetchDescendantIds(rootId: folderId)
        let documents = try await documentRepository.fetchAllRecursive(folderIds: folderIds)

        return documents.reduce(0) { total, doc in
            let bodyBytes = doc.bodyPreview?.utf8.count ?? 0
            let summaryBytes = doc.summaryText?.utf8.count ?? 0
            return total + max(bodyBytes, summaryBytes)
        }
    }

    /// Copy folder context to system clipboard.
    func copyContextToClipboard(folderId: Int64) async throws {
        let context = try await buildContext(folderId: folderId)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(context, forType: .string)
        AppLogger.general.info("Copied context to clipboard (\(context.utf8.count) bytes)")
    }
}
