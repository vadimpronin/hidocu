//
//  SourceRepository.swift
//  HiDocu
//
//  Protocol defining source data access operations.
//

import Foundation

protocol SourceRepository: Sendable {
    func fetchForDocument(_ documentId: Int64) async throws -> [Source]
    func fetchById(_ id: Int64) async throws -> Source?
    func insert(_ source: Source) async throws -> Source
    func delete(id: Int64) async throws
}
