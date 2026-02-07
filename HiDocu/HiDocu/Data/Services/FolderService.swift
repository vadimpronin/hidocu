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

    init(folderRepository: any FolderRepository) {
        self.folderRepository = folderRepository
    }

    func fetchFolder(id: Int64) async throws -> Folder? {
        try await folderRepository.fetchById(id)
    }

    func createFolder(name: String, parentId: Int64?) async throws -> Folder {
        let folder = Folder(parentId: parentId, name: name)
        let inserted = try await folderRepository.insert(folder)
        AppLogger.fileSystem.info("Created folder '\(name)' id=\(inserted.id)")
        return inserted
    }

    func renameFolder(id: Int64, newName: String) async throws {
        guard var folder = try await folderRepository.fetchById(id) else { return }
        folder.name = newName
        folder.modifiedAt = Date()
        try await folderRepository.update(folder)
    }

    func deleteFolder(id: Int64) async throws {
        try await folderRepository.delete(id: id)
    }

    func moveFolder(id: Int64, toParentId: Int64?) async throws {
        try await folderRepository.moveFolder(id: id, toParentId: toParentId)
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
    }

    /// Walk parent chain to resolve preferSummary setting.
    /// Returns the first explicit value found, or true as default.
    func resolvePreferSummary(folderId: Int64?) async throws -> Bool {
        guard let folderId else { return true }
        var currentId: Int64? = folderId
        while let id = currentId {
            guard let folder = try await folderRepository.fetchById(id) else { break }
            return folder.preferSummary
        }
        return true
    }
}
