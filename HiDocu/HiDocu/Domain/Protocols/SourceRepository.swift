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
    func update(_ source: Source) async throws
    func delete(id: Int64) async throws
    func updateDiskPathPrefix(oldPrefix: String, newPrefix: String) async throws
    func existsByDisplayName(_ displayName: String) async throws -> Bool
    func fetchDocumentIdsByRecordingIds(_ recordingIds: [Int64]) async throws -> [Int64: Int64]
}
