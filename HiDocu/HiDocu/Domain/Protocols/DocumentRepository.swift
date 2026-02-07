//
//  DocumentRepository.swift
//  HiDocu
//
//  Protocol defining document data access operations.
//

import Foundation

protocol DocumentRepository: Sendable {
    func fetchAll(folderId: Int64?) async throws -> [Document]
    func fetchAllRecursive(folderIds: [Int64]) async throws -> [Document]
    func fetchAllDocuments() async throws -> [Document]
    func fetchById(_ id: Int64) async throws -> Document?
    func insert(_ document: Document) async throws -> Document
    func update(_ document: Document) async throws
    func delete(id: Int64) async throws
    func moveDocument(id: Int64, toFolderId: Int64?) async throws
    func observeAll(folderId: Int64?) -> AsyncThrowingStream<[Document], Error>
    func observeAllDocuments() -> AsyncThrowingStream<[Document], Error>
    func updateDiskPathPrefix(oldPrefix: String, newPrefix: String) async throws
    func updateSortOrders(_ updates: [(id: Int64, sortOrder: Int)]) async throws
}
