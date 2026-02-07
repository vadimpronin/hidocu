//
//  FolderTreeViewModel.swift
//  HiDocu
//
//  Builds and manages the folder tree for sidebar display.
//

import Foundation

struct FolderNode: Identifiable, Hashable {
    let id: Int64
    let folder: Folder
    var children: [FolderNode]
    var byteCount: Int

    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
@MainActor
final class FolderTreeViewModel {

    var roots: [FolderNode] = []
    var allFolders: [Folder] = []

    private let folderRepository: any FolderRepository
    private let folderService: FolderService
    private let contextService: ContextService?
    private var observationTask: Task<Void, Never>?

    init(folderRepository: any FolderRepository, folderService: FolderService, contextService: ContextService? = nil) {
        self.folderRepository = folderRepository
        self.folderService = folderService
        self.contextService = contextService
    }

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task {
            do {
                for try await folders in folderRepository.observeAll() {
                    self.allFolders = folders
                    var tree = Self.buildTree(from: folders)
                    if let contextService {
                        await Self.populateByteCounts(nodes: &tree, contextService: contextService)
                    }
                    self.roots = tree
                }
            } catch {
                // Observation ended
            }
        }
    }

    private static func populateByteCounts(nodes: inout [FolderNode], contextService: ContextService) async {
        for i in nodes.indices {
            nodes[i].byteCount = (try? await contextService.calculateByteCount(folderId: nodes[i].id)) ?? 0
            await populateByteCounts(nodes: &nodes[i].children, contextService: contextService)
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Actions

    func createFolder(name: String, parentId: Int64?) async throws {
        _ = try await folderService.createFolder(name: name, parentId: parentId)
    }

    func renameFolder(id: Int64, newName: String) async throws {
        try await folderService.renameFolder(id: id, newName: newName)
    }

    func deleteFolder(id: Int64) async throws {
        try await folderService.deleteFolder(id: id)
    }

    // MARK: - Tree Building

    private static func buildTree(from folders: [Folder]) -> [FolderNode] {
        let byParent = Dictionary(grouping: folders, by: { $0.parentId })

        func buildNodes(parentId: Int64?) -> [FolderNode] {
            guard let children = byParent[parentId] else { return [] }
            return children.map { folder in
                FolderNode(
                    id: folder.id,
                    folder: folder,
                    children: buildNodes(parentId: folder.id),
                    byteCount: 0
                )
            }
        }

        return buildNodes(parentId: nil)
    }
}
