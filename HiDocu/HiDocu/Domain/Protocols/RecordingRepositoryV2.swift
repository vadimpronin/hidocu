//
//  RecordingRepositoryV2.swift
//  HiDocu
//
//  Simplified recording repository for context management system.
//

import Foundation

protocol RecordingRepositoryV2: Sendable {
    func fetchAll() async throws -> [RecordingV2]
    func fetchById(_ id: Int64) async throws -> RecordingV2?
    func fetchByFilename(_ filename: String) async throws -> RecordingV2?
    func insert(_ recording: RecordingV2) async throws -> RecordingV2
    func delete(id: Int64) async throws
    func exists(filename: String, sizeBytes: Int) async throws -> Bool
    func observeAll() -> AsyncThrowingStream<[RecordingV2], Error>
    func fetchBySourceId(_ sourceId: Int64) async throws -> [RecordingV2]
    func existsByFilenameAndSourceId(_ filename: String, sourceId: Int64) async throws -> Bool
    func fetchFilenamesForSource(_ sourceId: Int64) async throws -> Set<String>
    func observeBySourceId(_ sourceId: Int64) -> AsyncThrowingStream<[RecordingV2], Error>
    func updateSyncStatus(id: Int64, syncStatus: RecordingSyncStatus) async throws
}
