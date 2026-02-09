//
//  LLMJobDTO.swift
//  HiDocu
//
//  Data Transfer Object for LLM jobs - maps between database and domain model.
//

import Foundation
import GRDB

struct LLMJobDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "llm_jobs"

    var id: Int64?
    var jobType: String
    var status: String
    var priority: Int
    var provider: String
    var model: String
    var accountId: Int64?
    var payload: String
    var resultRef: String?
    var errorMessage: String?
    var attemptCount: Int
    var maxAttempts: Int
    var nextRetryAt: Date?
    var documentId: Int64?
    var sourceId: Int64?
    var transcriptId: Int64?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let jobType = Column(CodingKeys.jobType)
        static let status = Column(CodingKeys.status)
        static let priority = Column(CodingKeys.priority)
        static let provider = Column(CodingKeys.provider)
        static let model = Column(CodingKeys.model)
        static let accountId = Column(CodingKeys.accountId)
        static let payload = Column(CodingKeys.payload)
        static let resultRef = Column(CodingKeys.resultRef)
        static let errorMessage = Column(CodingKeys.errorMessage)
        static let attemptCount = Column(CodingKeys.attemptCount)
        static let maxAttempts = Column(CodingKeys.maxAttempts)
        static let nextRetryAt = Column(CodingKeys.nextRetryAt)
        static let documentId = Column(CodingKeys.documentId)
        static let sourceId = Column(CodingKeys.sourceId)
        static let transcriptId = Column(CodingKeys.transcriptId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let startedAt = Column(CodingKeys.startedAt)
        static let completedAt = Column(CodingKeys.completedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case jobType = "job_type"
        case status
        case priority
        case provider
        case model
        case accountId = "account_id"
        case payload
        case resultRef = "result_ref"
        case errorMessage = "error_message"
        case attemptCount = "attempt_count"
        case maxAttempts = "max_attempts"
        case nextRetryAt = "next_retry_at"
        case documentId = "document_id"
        case sourceId = "source_id"
        case transcriptId = "transcript_id"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }

    init(from domain: LLMJob) {
        self.id = domain.id == 0 ? nil : domain.id
        self.jobType = domain.jobType.rawValue
        self.status = domain.status.rawValue
        self.priority = domain.priority
        self.provider = domain.provider.rawValue
        self.model = domain.model
        self.accountId = domain.accountId
        self.payload = domain.payload
        self.resultRef = domain.resultRef
        self.errorMessage = domain.errorMessage
        self.attemptCount = domain.attemptCount
        self.maxAttempts = domain.maxAttempts
        self.nextRetryAt = domain.nextRetryAt
        self.documentId = domain.documentId
        self.sourceId = domain.sourceId
        self.transcriptId = domain.transcriptId
        self.createdAt = domain.createdAt
        self.startedAt = domain.startedAt
        self.completedAt = domain.completedAt
    }

    func toDomain() -> LLMJob {
        LLMJob(
            id: id ?? 0,
            jobType: LLMJobType(rawValue: jobType) ?? .transcription,
            status: LLMJobStatus(rawValue: status) ?? .pending,
            priority: priority,
            provider: LLMProvider(rawValue: provider) ?? .claude,
            model: model,
            accountId: accountId,
            payload: payload,
            resultRef: resultRef,
            errorMessage: errorMessage,
            attemptCount: attemptCount,
            maxAttempts: maxAttempts,
            nextRetryAt: nextRetryAt,
            documentId: documentId,
            sourceId: sourceId,
            transcriptId: transcriptId,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }
}
