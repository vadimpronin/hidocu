//
//  TrashService.swift
//  HiDocu
//
//  Trash management: list, restore, permanent delete, auto-cleanup.
//

import Foundation

@Observable
final class TrashService {

    private let deletionLogRepository: any DeletionLogRepository
    private let documentRepository: any DocumentRepository
    private let fileSystemService: FileSystemService

    init(
        deletionLogRepository: any DeletionLogRepository,
        documentRepository: any DocumentRepository,
        fileSystemService: FileSystemService
    ) {
        self.deletionLogRepository = deletionLogRepository
        self.documentRepository = documentRepository
        self.fileSystemService = fileSystemService
    }

    /// List all trashed documents sorted by deletion date
    func listTrashedDocuments() async throws -> [DeletionLogEntry] {
        try await deletionLogRepository.fetchAll()
    }

    /// Restore a document from trash
    func restoreDocument(deletionLogId: Int64, toFolderId: Int64?) async throws {
        guard let entry = try await deletionLogRepository.fetchById(deletionLogId) else { return }

        let diskPath = "\(entry.documentId).document"
        try fileSystemService.restoreDocumentFromTrash(trashPath: entry.trashPath, targetPath: diskPath)

        // Re-insert document in DB with original timestamps
        let doc = Document(
            folderId: toFolderId,
            title: entry.documentTitle ?? "Restored Document",
            diskPath: diskPath,
            createdAt: entry.originalCreatedAt ?? entry.deletedAt,
            modifiedAt: entry.originalModifiedAt ?? entry.deletedAt
        )
        _ = try await documentRepository.insert(doc)

        // Remove from deletion log
        try await deletionLogRepository.delete(id: deletionLogId)

        AppLogger.fileSystem.info("Restored document from trash: \(entry.trashPath)")
    }

    /// Permanently delete a trashed document
    func permanentlyDelete(deletionLogId: Int64) async throws {
        guard let entry = try await deletionLogRepository.fetchById(deletionLogId) else { return }
        fileSystemService.permanentlyDeleteTrash(trashPath: entry.trashPath)
        try await deletionLogRepository.delete(id: deletionLogId)
    }

    /// Auto-cleanup expired trash entries (called on app launch)
    func autoCleanup() async {
        do {
            let expired = try await deletionLogRepository.fetchExpired()
            guard !expired.isEmpty else { return }

            let paths = expired.map(\.trashPath)
            fileSystemService.cleanupExpiredTrash(trashPaths: paths)

            for entry in expired {
                try await deletionLogRepository.delete(id: entry.id)
            }

            AppLogger.fileSystem.info("Auto-cleaned \(expired.count) expired trash entries")
        } catch {
            AppLogger.fileSystem.error("Trash auto-cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Empty all trash
    func emptyTrash() async throws {
        let entries = try await deletionLogRepository.fetchAll()
        let paths = entries.map(\.trashPath)
        fileSystemService.cleanupExpiredTrash(trashPaths: paths)
        try await deletionLogRepository.deleteAll()
        AppLogger.fileSystem.info("Emptied trash (\(entries.count) entries)")
    }
}
