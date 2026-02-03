//
//  SQLiteRecordingRepository.swift
//  HiDocu
//
//  SQLite implementation of RecordingRepository using GRDB.
//

import Foundation
import GRDB

/// SQLite-backed implementation of RecordingRepository.
final class SQLiteRecordingRepository: RecordingRepository, @unchecked Sendable {
    
    private let db: DatabaseManager
    
    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }
    
    // MARK: - RecordingRepository
    
    func fetchAll(
        filterStatus: RecordingStatus?,
        sortBy: RecordingSortField,
        ascending: Bool
    ) async throws -> [Recording] {
        try await db.asyncRead { database in
            var query = RecordingDTO.all()
            
            // Apply status filter
            if let status = filterStatus {
                query = query.filter(RecordingDTO.Columns.status == status.rawValue)
            }
            
            // Apply sorting
            let column: Column
            switch sortBy {
            case .createdAt:
                column = RecordingDTO.Columns.createdAt
            case .modifiedAt:
                column = RecordingDTO.Columns.modifiedAt
            case .title:
                column = RecordingDTO.Columns.title
            case .filename:
                column = RecordingDTO.Columns.filename
            case .durationSeconds:
                column = RecordingDTO.Columns.durationSeconds
            case .fileSizeBytes:
                column = RecordingDTO.Columns.fileSizeBytes
            }
            
            query = ascending ? query.order(column.asc) : query.order(column.desc)
            
            let dtos = try query.fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }
    
    func fetchById(_ id: Int64) async throws -> Recording? {
        try await db.asyncRead { database in
            try RecordingDTO.fetchOne(database, key: id)?.toDomain()
        }
    }
    
    func fetchByFilename(_ filename: String) async throws -> Recording? {
        try await db.asyncRead { database in
            try RecordingDTO
                .filter(RecordingDTO.Columns.filename == filename)
                .fetchOne(database)?
                .toDomain()
        }
    }
    
    func insert(_ recording: Recording) async throws -> Recording {
        try await db.asyncWrite { database in
            let dto = RecordingDTO(from: recording)
            // Insert and get the row with assigned ID
            let inserted = try dto.inserted(database)
            return inserted.toDomain()
        }
    }
    
    func update(_ recording: Recording) async throws {
        try await db.asyncWrite { database in
            let dto = RecordingDTO(from: recording)
            try dto.save(database)
        }
    }
    
    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try RecordingDTO.deleteOne(database, key: id)
        }
    }
    
    func updatePlaybackPosition(id: Int64, seconds: Int) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE recordings SET playback_position_seconds = ? WHERE id = ?",
                arguments: [seconds, id]
            )
        }
    }
    
    func updateStatus(id: Int64, status: RecordingStatus) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE recordings SET status = ? WHERE id = ?",
                arguments: [status.rawValue, id]
            )
        }
    }
    
    func search(query: String) async throws -> [Recording] {
        try await db.asyncRead { database in
            let pattern = "%\(query)%"
            let dtos = try RecordingDTO
                .filter(
                    RecordingDTO.Columns.title.like(pattern) ||
                    RecordingDTO.Columns.filename.like(pattern)
                )
                .order(RecordingDTO.Columns.createdAt.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }
}
