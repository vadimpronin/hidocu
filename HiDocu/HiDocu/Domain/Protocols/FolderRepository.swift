//
//  FolderRepository.swift
//  HiDocu
//
//  Protocol defining folder data access operations.
//

import Foundation

protocol FolderRepository: Sendable {
    func fetchAll() async throws -> [Folder]
    func fetchChildren(parentId: Int64?) async throws -> [Folder]
    func fetchById(_ id: Int64) async throws -> Folder?
    func insert(_ folder: Folder) async throws -> Folder
    func update(_ folder: Folder) async throws
    func delete(id: Int64) async throws
    func moveFolder(id: Int64, toParentId: Int64?) async throws
    func fetchDescendantIds(rootId: Int64) async throws -> [Int64]
    func observeAll() -> AsyncThrowingStream<[Folder], Error>
}
