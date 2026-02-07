//
//  FolderService.swift
//  HiDocu
//
//  Folder CRUD and settings management.
//

import Foundation

@Observable
final class FolderService {

    private let folderRepository: any FolderRepository
    private let documentRepository: any DocumentRepository
    private let sourceRepository: any SourceRepository
    private let transcriptRepository: any TranscriptRepository
    private let fileSystemService: FileSystemService

    init(
        folderRepository: any FolderRepository,
        documentRepository: any DocumentRepository,
        sourceRepository: any SourceRepository,
        transcriptRepository: any TranscriptRepository,
        fileSystemService: FileSystemService
    ) {
        self.folderRepository = folderRepository
        self.documentRepository = documentRepository
        self.sourceRepository = sourceRepository
        self.transcriptRepository = transcriptRepository
        self.fileSystemService = fileSystemService
    }

    func fetchFolder(id: Int64) async throws -> Folder? {
        try await folderRepository.fetchById(id)
    }

    func createFolder(name: String, parentId: Int64?) async throws -> Folder {
        // Fetch parent folder to get its diskPath
        let parentDiskPath: String
        if let parentId {
            guard let parent = try await folderRepository.fetchById(parentId) else {
                throw FolderServiceError.parentNotFound
            }
            parentDiskPath = parent.diskPath ?? ""
        } else {
            parentDiskPath = ""
        }

        // Sanitize name
        let sanitizedName = PathSanitizer.sanitize(name)

        // Resolve conflicts with sibling folders on disk
        let uniqueName = PathSanitizer.resolveConflict(
            baseName: sanitizedName,
            suffix: ""
        ) { candidate in
            let candidatePath = parentDiskPath.isEmpty
                ? candidate
                : "\(parentDiskPath)/\(candidate)"
            return fileSystemService.directoryExists(relativePath: candidatePath)
        }

        // Compute diskPath
        let diskPath = parentDiskPath.isEmpty
            ? uniqueName
            : "\(parentDiskPath)/\(uniqueName)"

        // Create physical directory
        try fileSystemService.ensureFolderDirectoryExists(relativePath: diskPath)

        // Create folder record with diskPath
        var folder = Folder(parentId: parentId, name: name)
        folder.diskPath = diskPath

        let inserted = try await folderRepository.insert(folder)
        do { try fileSystemService.writeFolderMetadata(inserted) }
        catch { AppLogger.fileSystem.warning("Failed to write metadata for new folder \(inserted.id): \(error.localizedDescription)") }
        AppLogger.fileSystem.info("Created folder '\(name)' id=\(inserted.id) diskPath=\(diskPath)")
        return inserted
    }

    func renameFolder(id: Int64, newName: String) async throws {
        guard var folder = try await folderRepository.fetchById(id) else { return }
        guard let oldDiskPath = folder.diskPath else { return }

        // Compute parent prefix
        let parentPrefix = (oldDiskPath as NSString).deletingLastPathComponent

        // Sanitize new name
        let sanitizedName = PathSanitizer.sanitize(newName)

        // Resolve conflicts
        let uniqueName = PathSanitizer.resolveConflict(
            baseName: sanitizedName,
            suffix: ""
        ) { candidate in
            let candidatePath = parentPrefix.isEmpty
                ? candidate
                : "\(parentPrefix)/\(candidate)"
            // Don't conflict with self
            if candidatePath == oldDiskPath { return false }
            return fileSystemService.directoryExists(relativePath: candidatePath)
        }

        // Compute newDiskPath
        let newDiskPath = parentPrefix.isEmpty
            ? uniqueName
            : "\(parentPrefix)/\(uniqueName)"

        // Move physical directory if paths differ
        if oldDiskPath != newDiskPath {
            try fileSystemService.moveDirectory(from: oldDiskPath, to: newDiskPath)
        }

        // Update folder record
        folder.name = newName
        folder.diskPath = newDiskPath
        folder.modifiedAt = Date()
        try await folderRepository.update(folder)

        // Write updated metadata
        do { try fileSystemService.writeFolderMetadata(folder) }
        catch { AppLogger.fileSystem.warning("Failed to write metadata after rename for folder \(id): \(error.localizedDescription)") }

        // Cascade update descendant paths if paths differ
        if oldDiskPath != newDiskPath {
            let oldPrefix = oldDiskPath + "/"
            let newPrefix = newDiskPath + "/"

            try await folderRepository.updateDiskPathPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix)
            try await documentRepository.updateDiskPathPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix)
            try await sourceRepository.updateDiskPathPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix)
            try await transcriptRepository.updateFilePathPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix)

            AppLogger.fileSystem.info("Renamed folder id=\(id) '\(oldDiskPath)' -> '\(newDiskPath)' and cascaded paths")
        } else {
            AppLogger.fileSystem.info("Renamed folder id=\(id) name only (diskPath unchanged)")
        }
    }

    func moveFolder(id: Int64, toParentId: Int64?) async throws {
        guard let folder = try await folderRepository.fetchById(id) else { return }
        guard let oldDiskPath = folder.diskPath else { return }

        // Check for circular reference
        if let toParentId {
            let descendants = try await folderRepository.fetchDescendantIds(rootId: id)
            guard !descendants.contains(toParentId) else {
                throw FolderServiceError.circularReference
            }
        }

        // Get new parent's diskPath
        let newParentDiskPath: String
        if let toParentId {
            guard let newParent = try await folderRepository.fetchById(toParentId) else { return }
            newParentDiskPath = newParent.diskPath ?? ""
        } else {
            newParentDiskPath = ""
        }

        // Compute newDiskPath (keep folder name, change parent prefix)
        let folderName = (oldDiskPath as NSString).lastPathComponent
        let newDiskPath = newParentDiskPath.isEmpty
            ? folderName
            : "\(newParentDiskPath)/\(folderName)"

        // Move physical directory if paths differ
        if oldDiskPath != newDiskPath {
            try fileSystemService.moveDirectory(from: oldDiskPath, to: newDiskPath)
        }

        // Update DB: parentId
        try await folderRepository.moveFolder(id: id, toParentId: toParentId)

        // Fetch updated folder and set diskPath
        guard var updatedFolder = try await folderRepository.fetchById(id) else { return }
        updatedFolder.diskPath = newDiskPath
        updatedFolder.modifiedAt = Date()
        try await folderRepository.update(updatedFolder)

        // Cascade descendant paths if paths differ
        if oldDiskPath != newDiskPath {
            let oldPrefix = oldDiskPath + "/"
            let newPrefix = newDiskPath + "/"

            try await folderRepository.updateDiskPathPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix)
            try await documentRepository.updateDiskPathPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix)
            try await sourceRepository.updateDiskPathPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix)
            try await transcriptRepository.updateFilePathPrefix(oldPrefix: oldPrefix, newPrefix: newPrefix)

            AppLogger.fileSystem.info("Moved folder id=\(id) '\(oldDiskPath)' -> '\(newDiskPath)' and cascaded paths")
        } else {
            AppLogger.fileSystem.info("Moved folder id=\(id) (diskPath unchanged)")
        }

        // Place moved folder at bottom of target parent
        let siblings = try await folderRepository.fetchChildren(parentId: toParentId)
        let maxOrder = siblings.map(\.sortOrder).max() ?? -1
        try await folderRepository.updateSortOrders([(id: id, sortOrder: maxOrder + 1)])

        // Write updated metadata
        if let finalFolder = try await folderRepository.fetchById(id) {
            do { try fileSystemService.writeFolderMetadata(finalFolder) }
            catch { AppLogger.fileSystem.warning("Failed to write metadata after move for folder \(id): \(error.localizedDescription)") }
        }
    }

    func deleteFolder(id: Int64) async throws {
        // Check for child folders
        let childFolders = try await folderRepository.fetchChildren(parentId: id)
        guard childFolders.isEmpty else {
            throw FolderServiceError.folderNotEmpty
        }

        // Check for child documents
        let childDocuments = try await documentRepository.fetchAll(folderId: id)
        guard childDocuments.isEmpty else {
            throw FolderServiceError.folderNotEmpty
        }

        // Get folder's diskPath
        let folder = try await folderRepository.fetchById(id)
        let diskPath = folder?.diskPath

        // Delete from DB
        try await folderRepository.delete(id: id)

        // Remove physical directory if diskPath exists
        if let diskPath, !diskPath.isEmpty {
            let url = fileSystemService.dataDirectory.appendingPathComponent(diskPath, isDirectory: true)
            try? FileManager.default.removeItem(at: url)
            AppLogger.fileSystem.info("Deleted folder id=\(id) diskPath=\(diskPath)")
        } else {
            AppLogger.fileSystem.info("Deleted folder id=\(id) (no diskPath)")
        }
    }

    func updateSettings(
        id: Int64,
        preferSummary: Bool? = nil,
        minimizeBeforeLLM: Bool? = nil,
        transcriptionContext: String? = nil,
        categorizationContext: String? = nil
    ) async throws {
        guard var folder = try await folderRepository.fetchById(id) else { return }
        if let ps = preferSummary { folder.preferSummary = ps }
        if let m = minimizeBeforeLLM { folder.minimizeBeforeLLM = m }
        if let tc = transcriptionContext { folder.transcriptionContext = tc }
        if let cc = categorizationContext { folder.categorizationContext = cc }
        folder.modifiedAt = Date()
        try await folderRepository.update(folder)

        // Write updated metadata
        do { try fileSystemService.writeFolderMetadata(folder) }
        catch { AppLogger.fileSystem.warning("Failed to write metadata after settings update for folder \(id): \(error.localizedDescription)") }
    }

    // MARK: - Sorting

    func reorderFolders(_ orderedIds: [Int64]) async throws {
        let updates = orderedIds.enumerated().map { (index, id) in
            (id: id, sortOrder: index)
        }
        try await folderRepository.updateSortOrders(updates)

        // Write metadata for each reordered folder
        for folderId in orderedIds {
            if let folder = try await folderRepository.fetchById(folderId) {
                do { try fileSystemService.writeFolderMetadata(folder) }
                catch { AppLogger.fileSystem.warning("Failed to write metadata after reorder for folder \(folderId): \(error.localizedDescription)") }
            }
        }
    }

    /// Resolve preferSummary setting for a folder.
    /// Returns the folder's value, or true as default if folder not found.
    func resolvePreferSummary(folderId: Int64?) async throws -> Bool {
        guard let folderId else { return true }
        guard let folder = try await folderRepository.fetchById(folderId) else { return true }
        return folder.preferSummary
    }
}

enum FolderServiceError: LocalizedError {
    case folderNotEmpty
    case parentNotFound
    case circularReference

    var errorDescription: String? {
        switch self {
        case .folderNotEmpty:
            return "Folder must be empty before deletion. Move or delete its contents first."
        case .parentNotFound:
            return "Parent folder not found."
        case .circularReference:
            return "Cannot move a folder into one of its own subfolders."
        }
    }
}
