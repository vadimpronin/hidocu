//
//  DocumentService.swift
//  HiDocu
//
//  Orchestrates document lifecycle: creation, editing, deletion, sources.
//

import Foundation
import CryptoKit

@Observable
final class DocumentService {

    private let documentRepository: any DocumentRepository
    private let sourceRepository: any SourceRepository
    private let transcriptRepository: any TranscriptRepository
    private let deletionLogRepository: any DeletionLogRepository
    private let fileSystemService: FileSystemService

    init(
        documentRepository: any DocumentRepository,
        sourceRepository: any SourceRepository,
        transcriptRepository: any TranscriptRepository,
        deletionLogRepository: any DeletionLogRepository,
        fileSystemService: FileSystemService
    ) {
        self.documentRepository = documentRepository
        self.sourceRepository = sourceRepository
        self.transcriptRepository = transcriptRepository
        self.deletionLogRepository = deletionLogRepository
        self.fileSystemService = fileSystemService
    }

    // MARK: - Document CRUD

    func createDocument(title: String, folderId: Int64?) async throws -> Document {
        try fileSystemService.ensureDataDirectoryExists()

        // Insert with placeholder disk path to get the ID
        let placeholder = Document(
            folderId: folderId,
            title: title,
            diskPath: "pending"
        )
        let inserted = try await documentRepository.insert(placeholder)

        // Create disk folder using the assigned ID
        let diskPath = try fileSystemService.createDocumentFolder(documentId: inserted.id)
        try fileSystemService.updateDocumentMetadata(diskPath: diskPath, title: title)

        // Update with real disk path
        var updated = inserted
        updated.diskPath = diskPath
        try await documentRepository.update(updated)

        AppLogger.fileSystem.info("Created document '\(title)' id=\(inserted.id)")
        return updated
    }

    func renameDocument(id: Int64, newTitle: String) async throws {
        guard var doc = try await documentRepository.fetchById(id) else { return }
        doc.title = newTitle
        doc.modifiedAt = Date()
        try await documentRepository.update(doc)
        try fileSystemService.updateDocumentMetadata(diskPath: doc.diskPath, title: newTitle)
    }

    func deleteDocument(id: Int64) async throws {
        guard let doc = try await documentRepository.fetchById(id) else { return }

        // Move to trash on disk
        let trashPath = try fileSystemService.moveDocumentToTrash(diskPath: doc.diskPath, documentId: id)

        // Delete from DB (cascades sources/transcripts)
        try await documentRepository.delete(id: id)

        // Record in deletion log so it appears in Trash
        let entry = DeletionLogEntry(
            documentId: id,
            documentTitle: doc.title,
            folderPath: nil,
            deletedAt: Date(),
            trashPath: trashPath,
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())!,
            originalCreatedAt: doc.createdAt,
            originalModifiedAt: doc.modifiedAt
        )
        _ = try await deletionLogRepository.insert(entry)
    }

    func moveDocument(id: Int64, toFolderId: Int64?) async throws {
        try await documentRepository.moveDocument(id: id, toFolderId: toFolderId)
    }

    // MARK: - Body & Summary

    func readBody(diskPath: String) throws -> String {
        try fileSystemService.readDocumentBody(diskPath: diskPath)
    }

    func writeBody(documentId: Int64, diskPath: String, content: String) async throws {
        try fileSystemService.writeDocumentBody(diskPath: diskPath, content: content)

        // Update DB caches
        guard var doc = try await documentRepository.fetchById(documentId) else { return }
        doc.bodyPreview = String(content.prefix(500))
        doc.bodyHash = sha256(content)
        doc.modifiedAt = Date()
        try await documentRepository.update(doc)
    }

    func readSummary(diskPath: String) throws -> String {
        try fileSystemService.readDocumentSummary(diskPath: diskPath)
    }

    func writeSummary(documentId: Int64, diskPath: String, content: String) async throws {
        try fileSystemService.writeDocumentSummary(diskPath: diskPath, content: content)

        guard var doc = try await documentRepository.fetchById(documentId) else { return }
        doc.summaryText = content
        doc.summaryHash = sha256(content)
        doc.modifiedAt = Date()
        try await documentRepository.update(doc)
    }

    func writeBodyById(documentId: Int64, content: String) async throws {
        guard let doc = try await documentRepository.fetchById(documentId) else {
            throw DocumentServiceError.documentNotFound
        }
        try await writeBody(documentId: documentId, diskPath: doc.diskPath, content: content)
    }

    // MARK: - Sources

    func addSource(documentId: Int64, recordingId: Int64, displayName: String?) async throws -> Source {
        guard let doc = try await documentRepository.fetchById(documentId) else {
            throw DocumentServiceError.documentNotFound
        }

        let sourceDiskPath = try fileSystemService.createSourceFolder(
            documentDiskPath: doc.diskPath,
            sourceId: 0 // placeholder
        )

        let source = Source(
            documentId: documentId,
            sourceType: .recording,
            recordingId: recordingId,
            diskPath: sourceDiskPath,
            displayName: displayName
        )
        let inserted = try await sourceRepository.insert(source)

        // Recreate with correct ID-based path
        let correctPath = try fileSystemService.createSourceFolder(
            documentDiskPath: doc.diskPath,
            sourceId: inserted.id
        )
        var fixed = inserted
        fixed.diskPath = correctPath
        try await sourceRepository.delete(id: inserted.id)
        let final_ = try await sourceRepository.insert(Source(
            documentId: documentId,
            sourceType: .recording,
            recordingId: recordingId,
            diskPath: correctPath,
            displayName: displayName
        ))

        return final_
    }

    func removeSource(id: Int64) async throws {
        guard let source = try await sourceRepository.fetchById(id) else { return }
        fileSystemService.removeSourceFolder(diskPath: source.diskPath)
        try await sourceRepository.delete(id: id)
    }

    // MARK: - Helpers

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum DocumentServiceError: LocalizedError {
    case documentNotFound

    var errorDescription: String? {
        switch self {
        case .documentNotFound: return "Document not found"
        }
    }
}
