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
    private let folderRepository: any FolderRepository
    private let fileSystemService: FileSystemService

    init(
        documentRepository: any DocumentRepository,
        sourceRepository: any SourceRepository,
        transcriptRepository: any TranscriptRepository,
        deletionLogRepository: any DeletionLogRepository,
        folderRepository: any FolderRepository,
        fileSystemService: FileSystemService
    ) {
        self.documentRepository = documentRepository
        self.sourceRepository = sourceRepository
        self.transcriptRepository = transcriptRepository
        self.deletionLogRepository = deletionLogRepository
        self.folderRepository = folderRepository
        self.fileSystemService = fileSystemService
    }

    // MARK: - Document CRUD

    func createDocument(title: String, folderId: Int64?) async throws -> Document {
        try fileSystemService.ensureDataDirectoryExists()

        // Resolve parent folder path
        let parentPath: String
        if let folderId {
            if let folder = try await folderRepository.fetchById(folderId) {
                parentPath = folder.diskPath ?? ""
            } else {
                parentPath = ""
            }
        } else {
            parentPath = ""
        }

        // Ensure parent directory exists
        if !parentPath.isEmpty {
            try fileSystemService.ensureFolderDirectoryExists(relativePath: parentPath)
        }

        // Create document folder with human-readable title
        let diskPath = try fileSystemService.createDocumentFolder(title: title, parentRelativePath: parentPath)

        // Insert document with real diskPath (no placeholder!)
        let doc = Document(
            folderId: folderId,
            title: title,
            diskPath: diskPath
        )
        let inserted = try await documentRepository.insert(doc)

        // Write full metadata
        try fileSystemService.writeDocumentMetadata(inserted)

        AppLogger.fileSystem.info("Created document '\(title)' id=\(inserted.id) at \(diskPath)")
        return inserted
    }

    func renameDocument(id: Int64, newTitle: String) async throws {
        guard var doc = try await documentRepository.fetchById(id) else { return }
        let oldDiskPath = doc.diskPath

        // Physical rename on disk
        let newDiskPath = try fileSystemService.renameDocumentFolder(oldDiskPath: oldDiskPath, newTitle: newTitle)

        // Update database
        doc.title = newTitle
        doc.diskPath = newDiskPath
        doc.modifiedAt = Date()
        try await documentRepository.update(doc)

        // Write updated metadata
        do { try fileSystemService.writeDocumentMetadata(doc) }
        catch { AppLogger.fileSystem.warning("Failed to write metadata after rename for document \(id): \(error.localizedDescription)") }

        // Cascade path updates if paths changed (append / for correct prefix matching)
        if oldDiskPath != newDiskPath {
            let oldCascadePrefix = oldDiskPath + "/"
            let newCascadePrefix = newDiskPath + "/"
            try await sourceRepository.updateDiskPathPrefix(oldPrefix: oldCascadePrefix, newPrefix: newCascadePrefix)
            try await transcriptRepository.updateFilePathPrefix(oldPrefix: oldCascadePrefix, newPrefix: newCascadePrefix)
            AppLogger.fileSystem.info("Renamed document \(id) on disk: \(oldDiskPath) -> \(newDiskPath)")
        }
    }

    func deleteDocument(id: Int64) async throws {
        guard let doc = try await documentRepository.fetchById(id) else { return }

        // Resolve folder path for deletion_log
        let folderPath: String?
        if let folderId = doc.folderId,
           let folder = try await folderRepository.fetchById(folderId) {
            folderPath = folder.diskPath
        } else {
            folderPath = nil
        }

        // Move to trash on disk
        let trashPath = try fileSystemService.moveDocumentToTrash(diskPath: doc.diskPath, documentId: id)

        // Delete from DB (cascades sources/transcripts)
        try await documentRepository.delete(id: id)

        // Record in deletion log so it appears in Trash
        let entry = DeletionLogEntry(
            documentId: id,
            documentTitle: doc.title,
            folderPath: folderPath,
            deletedAt: Date(),
            trashPath: trashPath,
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())!,
            originalCreatedAt: doc.createdAt,
            originalModifiedAt: doc.modifiedAt
        )
        _ = try await deletionLogRepository.insert(entry)
    }

    func moveDocument(id: Int64, toFolderId: Int64?) async throws {
        guard var doc = try await documentRepository.fetchById(id) else { return }
        let oldDiskPath = doc.diskPath

        // Resolve new parent folder's diskPath
        let newParentPath: String
        if let toFolderId {
            if let folder = try await folderRepository.fetchById(toFolderId) {
                newParentPath = folder.diskPath ?? ""
            } else {
                newParentPath = ""
            }
        } else {
            newParentPath = ""
        }

        // Get document directory name (e.g., "Meeting Notes.document")
        let docDirName = (doc.diskPath as NSString).lastPathComponent

        // Compute new disk path
        let newDiskPath: String
        if newParentPath.isEmpty {
            newDiskPath = docDirName
        } else {
            newDiskPath = (newParentPath as NSString).appendingPathComponent(docDirName)
        }

        // Handle conflict at destination
        let finalDiskPath: String
        if oldDiskPath != newDiskPath {
            let baseName = (docDirName as NSString).deletingPathExtension
            let suffix = "." + (docDirName as NSString).pathExtension
            let parent = (newDiskPath as NSString).deletingLastPathComponent

            let uniqueName = PathSanitizer.resolveConflict(
                baseName: baseName,
                suffix: suffix,
                existsCheck: { candidateName in
                    let candidatePath = parent.isEmpty ? candidateName : (parent as NSString).appendingPathComponent(candidateName)
                    let candidateURL = fileSystemService.dataDirectory.appendingPathComponent(candidatePath, isDirectory: true)
                    return FileManager.default.fileExists(atPath: candidateURL.path)
                }
            )

            finalDiskPath = parent.isEmpty ? uniqueName : (parent as NSString).appendingPathComponent(uniqueName)

            // Ensure parent directory exists
            if !newParentPath.isEmpty {
                try fileSystemService.ensureFolderDirectoryExists(relativePath: newParentPath)
            }

            // Physical move on disk
            try fileSystemService.moveDirectory(from: oldDiskPath, to: finalDiskPath)

            // Update database with new folderId and diskPath
            doc.folderId = toFolderId
            doc.diskPath = finalDiskPath
            doc.modifiedAt = Date()
            try await documentRepository.update(doc)

            // Cascade source/transcript path updates (append / for correct prefix matching)
            let oldCascadePrefix = oldDiskPath + "/"
            let newCascadePrefix = finalDiskPath + "/"
            try await sourceRepository.updateDiskPathPrefix(oldPrefix: oldCascadePrefix, newPrefix: newCascadePrefix)
            try await transcriptRepository.updateFilePathPrefix(oldPrefix: oldCascadePrefix, newPrefix: newCascadePrefix)

            AppLogger.fileSystem.info("Moved document \(id) on disk: \(oldDiskPath) -> \(finalDiskPath)")
        } else {
            // No physical move needed, just update folderId
            try await documentRepository.moveDocument(id: id, toFolderId: toFolderId)
        }

        // Place moved document at bottom of target folder
        let targetDocs = try await documentRepository.fetchAll(folderId: toFolderId)
        let maxOrder = targetDocs.map(\.sortOrder).max() ?? -1
        try await documentRepository.updateSortOrders([(id: id, sortOrder: maxOrder + 1)])

        // Write updated metadata
        if let movedDoc = try await documentRepository.fetchById(id) {
            do { try fileSystemService.writeDocumentMetadata(movedDoc) }
            catch { AppLogger.fileSystem.warning("Failed to write metadata after move for document \(id): \(error.localizedDescription)") }
        }
    }

    func fetchDocument(id: Int64) async throws -> Document? {
        try await documentRepository.fetchById(id)
    }

    func updateTitle(id: Int64, newTitle: String) async throws {
        guard var doc = try await documentRepository.fetchById(id) else { return }
        doc.title = newTitle
        doc.modifiedAt = Date()
        try await documentRepository.update(doc)
        do { try fileSystemService.writeDocumentMetadata(doc) }
        catch { AppLogger.fileSystem.warning("Failed to write metadata after title update for document \(id): \(error.localizedDescription)") }
    }

    func renameDocumentOnDisk(id: Int64) async throws {
        guard var doc = try await documentRepository.fetchById(id) else { return }
        let oldDiskPath = doc.diskPath
        let newDiskPath = try fileSystemService.renameDocumentFolder(oldDiskPath: oldDiskPath, newTitle: doc.title)

        if oldDiskPath != newDiskPath {
            doc.diskPath = newDiskPath
            doc.modifiedAt = Date()
            try await documentRepository.update(doc)
            do { try fileSystemService.writeDocumentMetadata(doc) }
            catch { AppLogger.fileSystem.warning("Failed to write metadata after disk rename for document \(id): \(error.localizedDescription)") }
            let oldCascadePrefix = oldDiskPath + "/"
            let newCascadePrefix = newDiskPath + "/"
            try await sourceRepository.updateDiskPathPrefix(oldPrefix: oldCascadePrefix, newPrefix: newCascadePrefix)
            try await transcriptRepository.updateFilePathPrefix(oldPrefix: oldCascadePrefix, newPrefix: newCascadePrefix)
            AppLogger.fileSystem.info("Renamed document \(id) on disk (deferred): \(oldDiskPath) -> \(newDiskPath)")
        }
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
        do { try fileSystemService.writeDocumentMetadata(doc) }
        catch { AppLogger.fileSystem.warning("Failed to write metadata after body update for document \(documentId): \(error.localizedDescription)") }
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
        do { try fileSystemService.writeDocumentMetadata(doc) }
        catch { AppLogger.fileSystem.warning("Failed to write metadata after summary update for document \(documentId): \(error.localizedDescription)") }
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

        // Insert source with placeholder diskPath to get ID
        let source = Source(
            documentId: documentId,
            sourceType: .recording,
            recordingId: recordingId,
            diskPath: "pending",
            displayName: displayName
        )
        let inserted = try await sourceRepository.insert(source)

        // Create source folder using real ID
        let correctPath = try fileSystemService.createSourceFolder(
            documentDiskPath: doc.diskPath,
            sourceId: inserted.id
        )

        // Delete and re-insert with correct path
        // (SourceRepository only has insert/delete, no update method)
        try await sourceRepository.delete(id: inserted.id)
        let final_ = try await sourceRepository.insert(Source(
            documentId: documentId,
            sourceType: .recording,
            recordingId: recordingId,
            diskPath: correctPath,
            displayName: displayName
        ))

        AppLogger.fileSystem.info("Added source \(final_.id) to document \(documentId) at \(correctPath)")
        return final_
    }

    func removeSource(id: Int64) async throws {
        guard let source = try await sourceRepository.fetchById(id) else { return }
        fileSystemService.removeSourceFolder(diskPath: source.diskPath)
        try await sourceRepository.delete(id: id)
    }

    // MARK: - Sorting

    func reorderDocuments(_ orderedIds: [Int64]) async throws {
        let updates = orderedIds.enumerated().map { (index, id) in
            (id: id, sortOrder: index)
        }
        try await documentRepository.updateSortOrders(updates)

        // Write metadata for each reordered document
        for docId in orderedIds {
            if let doc = try await documentRepository.fetchById(docId) {
                do { try fileSystemService.writeDocumentMetadata(doc) }
                catch { AppLogger.fileSystem.warning("Failed to write metadata after reorder for document \(docId): \(error.localizedDescription)") }
            }
        }
    }

    func sortDocuments(folderId: Int64?, by criterion: DocumentSortCriterion) async throws {
        let docs = try await documentRepository.fetchAll(folderId: folderId)
        let sorted: [Document] = switch criterion {
        case .nameAscending:
            docs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateCreatedAscending:
            docs.sorted { $0.createdAt < $1.createdAt }
        case .dateCreatedDescending:
            docs.sorted { $0.createdAt > $1.createdAt }
        }
        try await reorderDocuments(sorted.map(\.id))
    }

    // MARK: - Helpers

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum DocumentSortCriterion {
    case nameAscending
    case dateCreatedAscending
    case dateCreatedDescending
}

enum DocumentServiceError: LocalizedError {
    case documentNotFound

    var errorDescription: String? {
        switch self {
        case .documentNotFound: return "Document not found"
        }
    }
}
