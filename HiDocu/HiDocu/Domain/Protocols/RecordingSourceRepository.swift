//
//  RecordingSourceRepository.swift
//  HiDocu
//
//  Repository protocol for recording source persistence.
//

import Foundation

protocol RecordingSourceRepository: Sendable {
    func fetchAll() async throws -> [RecordingSource]
    func fetchById(_ id: Int64) async throws -> RecordingSource?
    func fetchByUniqueIdentifier(_ identifier: String) async throws -> RecordingSource?
    func insert(_ source: RecordingSource) async throws -> RecordingSource
    func update(_ source: RecordingSource) async throws
    func delete(id: Int64) async throws
    func observeAll() -> AsyncThrowingStream<[RecordingSource], Error>
    func updateLastSeen(id: Int64, at: Date) async throws
    func updateLastSynced(id: Int64, at: Date) async throws
}
