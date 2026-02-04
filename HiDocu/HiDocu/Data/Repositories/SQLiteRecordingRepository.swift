//
//  SQLiteRecordingRepository.swift
//  HiDocu
//
//  SQLite implementation of RecordingRepository using GRDB.
//

import Foundation
import GRDB

/// SQLite-backed implementation of RecordingRepository.
/// Handles path mapping between absolute URLs and relative paths for storage.
final class SQLiteRecordingRepository: RecordingRepository, @unchecked Sendable {
    
    private let db: DatabaseManager
    private let fileSystemService: FileSystemService
    
    init(databaseManager: DatabaseManager, fileSystemService: FileSystemService) {
        self.db = databaseManager
        self.fileSystemService = fileSystemService
    }
    
    // MARK: - Path Mapping Helpers
    
    /// Convert relative path from DB to absolute path for domain model
    private func toAbsolutePath(_ relativePath: String) -> String {
        do {
            return try fileSystemService.resolve(relativePath: relativePath).path
        } catch {
            // If resolution fails, return the relative path as-is
            // This handles edge cases during startup before storage is configured
            return relativePath
        }
    }
    
    /// Convert Recording DTO to domain with absolute path resolution
    private func toDomainWithAbsolutePath(_ dto: RecordingDTO) -> Recording {
        var recording = dto.toDomain()
        // Replace stored relative path with resolved absolute path
        return Recording(
            id: recording.id,
            filename: recording.filename,
            filepath: toAbsolutePath(recording.filepath),
            title: recording.title,
            durationSeconds: recording.durationSeconds,
            fileSizeBytes: recording.fileSizeBytes,
            createdAt: recording.createdAt,
            modifiedAt: recording.modifiedAt,
            deviceSerial: recording.deviceSerial,
            deviceModel: recording.deviceModel,
            recordingMode: recording.recordingMode,
            status: recording.status,
            playbackPositionSeconds: recording.playbackPositionSeconds
        )
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
            return dtos.map { self.toDomainWithAbsolutePath($0) }
        }
    }
    
    func fetchById(_ id: Int64) async throws -> Recording? {
        try await db.asyncRead { database in
            guard let dto = try RecordingDTO.fetchOne(database, key: id) else {
                return nil
            }
            return self.toDomainWithAbsolutePath(dto)
        }
    }
    
    func fetchByFilename(_ filename: String) async throws -> Recording? {
        try await db.asyncRead { database in
            guard let dto = try RecordingDTO
                .filter(RecordingDTO.Columns.filename == filename)
                .fetchOne(database) else {
                return nil
            }
            return self.toDomainWithAbsolutePath(dto)
        }
    }
    
    func insert(_ recording: Recording) async throws -> Recording {
        // Convert absolute filepath to relative for storage
        let relativePath = fileSystemService.relativePath(for: URL(fileURLWithPath: recording.filepath))
            ?? recording.filepath  // Fallback to original if not in storage dir
        
        // Create a recording with relative path for DB storage
        let recordingForStorage = Recording(
            id: recording.id,
            filename: recording.filename,
            filepath: relativePath,
            title: recording.title,
            durationSeconds: recording.durationSeconds,
            fileSizeBytes: recording.fileSizeBytes,
            createdAt: recording.createdAt,
            modifiedAt: recording.modifiedAt,
            deviceSerial: recording.deviceSerial,
            deviceModel: recording.deviceModel,
            recordingMode: recording.recordingMode,
            status: recording.status,
            playbackPositionSeconds: recording.playbackPositionSeconds
        )
        
        return try await db.asyncWrite { database in
            let dto = RecordingDTO(from: recordingForStorage)
            // Insert and get the row with assigned ID
            let inserted = try dto.inserted(database)
            return self.toDomainWithAbsolutePath(inserted)
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
            return dtos.map { self.toDomainWithAbsolutePath($0) }
        }
    }
    
    // MARK: - Observation

    func observeAll(
        filterStatus: RecordingStatus?,
        sortBy: RecordingSortField,
        ascending: Bool
    ) -> AsyncThrowingStream<[Recording], Error> {
        AsyncThrowingStream { continuation in
            let observation = ValueObservation.tracking { database -> [RecordingDTO] in
                var query = RecordingDTO.all()

                if let status = filterStatus {
                    query = query.filter(RecordingDTO.Columns.status == status.rawValue)
                }

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
                return try query.fetchAll(database)
            }

            let cancellable = observation.start(in: db.dbPool, scheduling: .async(onQueue: .main)) { error in
                continuation.finish(throwing: error)
            } onChange: { dtos in
                let recordings = dtos.map { self.toDomainWithAbsolutePath($0) }
                continuation.yield(recordings)
            }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    // MARK: - Sync Operations
    
    func exists(filename: String, sizeBytes: Int) async throws -> Bool {
        try await db.asyncRead { database in
            let count = try RecordingDTO
                .filter(RecordingDTO.Columns.filename == filename)
                .filter(RecordingDTO.Columns.fileSizeBytes == sizeBytes)
                .fetchCount(database)
            return count > 0
        }
    }
    
    func markAsDownloaded(id: Int64, relativePath: String) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: """
                    UPDATE recordings 
                    SET status = ?, filepath = ?, modified_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    RecordingStatus.downloaded.rawValue,
                    relativePath,
                    Date(),
                    id
                ]
            )
        }
    }
    
    func updateFilePath(id: Int64, newRelativePath: String, newFilename: String) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: """
                    UPDATE recordings 
                    SET filepath = ?, filename = ?, modified_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    newRelativePath,
                    newFilename,
                    Date(),
                    id
                ]
            )
        }
    }
}
