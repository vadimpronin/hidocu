//
//  DeletionLogRepository.swift
//  HiDocu
//
//  Protocol defining deletion log data access operations.
//

import Foundation

protocol DeletionLogRepository: Sendable {
    func fetchAll() async throws -> [DeletionLogEntry]
    func fetchById(_ id: Int64) async throws -> DeletionLogEntry?
    func insert(_ entry: DeletionLogEntry) async throws -> DeletionLogEntry
    func delete(id: Int64) async throws
    func fetchExpired() async throws -> [DeletionLogEntry]
    func deleteAll() async throws
}
