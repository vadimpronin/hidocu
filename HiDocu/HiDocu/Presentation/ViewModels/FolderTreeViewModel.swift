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
        && lhs.folder.sortOrder == rhs.folder.sortOrder
        && lhs.children.map(\.id) == rhs.children.map(\.id)
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

    // MARK: - Sorting

    func reorderRootFolders(from source: IndexSet, to destination: Int) {
        var reordered = roots
        reordered.move(fromOffsets: source, toOffset: destination)
        roots = reordered  // Optimistic update
        let orderedIds = reordered.map(\.id)
        Task {
            do { try await folderService.reorderFolders(orderedIds) }
            catch { AppLogger.general.error("Failed to reorder folders: \(error.localizedDescription)") }
        }
    }

    func reorderChildFolders(parentId: Int64, from source: IndexSet, to destination: Int) {
        // Optimistic update: mutate tree in-place
        var updatedRoots = roots
        if mutateChildren(ofParentId: parentId, in: &updatedRoots, source: source, destination: destination) {
            roots = updatedRoots
        }

        // Compute new order from the (possibly updated) children
        guard let children = findChildren(ofParentId: parentId, in: roots) else { return }
        let orderedIds = children.map(\.id)
        Task {
            do { try await folderService.reorderFolders(orderedIds) }
            catch { AppLogger.general.error("Failed to reorder child folders: \(error.localizedDescription)") }
        }
    }

    private func findChildren(ofParentId parentId: Int64, in nodes: [FolderNode]) -> [FolderNode]? {
        for node in nodes {
            if node.id == parentId { return node.children }
            if let found = findChildren(ofParentId: parentId, in: node.children) { return found }
        }
        return nil
    }

    @discardableResult
    private func mutateChildren(ofParentId parentId: Int64, in nodes: inout [FolderNode], source: IndexSet, destination: Int) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == parentId {
                nodes[i].children.move(fromOffsets: source, toOffset: destination)
                return true
            }
            if mutateChildren(ofParentId: parentId, in: &nodes[i].children, source: source, destination: destination) {
                return true
            }
        }
        return false
    }

    // MARK: - Tree Building

    private static func buildTree(from folders: [Folder]) -> [FolderNode] {
        let byParent = Dictionary(grouping: folders, by: { $0.parentId })

        func buildNodes(parentId: Int64?) -> [FolderNode] {
            guard let children = byParent[parentId] else { return [] }
            return children.sorted(by: { $0.sortOrder < $1.sortOrder }).map { folder in
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
