//
//  TranscriptRepository.swift
//  HiDocu
//
//  Protocol defining transcript data access operations.
//

import Foundation

protocol TranscriptRepository: Sendable {
    func fetchForSource(_ sourceId: Int64) async throws -> [Transcript]
    func fetchById(_ id: Int64) async throws -> Transcript?
    func fetchPrimary(sourceId: Int64) async throws -> Transcript?
    func insert(_ transcript: Transcript) async throws -> Transcript
    func update(_ transcript: Transcript) async throws
    func delete(id: Int64) async throws
    func setPrimary(id: Int64, sourceId: Int64) async throws
    func updateFilePathPrefix(oldPrefix: String, newPrefix: String) async throws
}
