//
//  APILogDTO.swift
//  HiDocu
//
//  Data Transfer Object for API logs - maps between database and domain model.
//

import Foundation
import GRDB

struct APILogDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "api_logs"

    var id: Int64?
    var provider: String
    var llmAccountId: Int64?
    var model: String
    var requestPayload: String?
    var responsePayload: String?
    var timestamp: Date
    var documentId: Int64?
    var sourceId: Int64?
    var transcriptId: Int64?
    var status: String
    var error: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var durationMs: Int?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let provider = Column(CodingKeys.provider)
        static let llmAccountId = Column(CodingKeys.llmAccountId)
        static let model = Column(CodingKeys.model)
        static let requestPayload = Column(CodingKeys.requestPayload)
        static let responsePayload = Column(CodingKeys.responsePayload)
        static let timestamp = Column(CodingKeys.timestamp)
        static let documentId = Column(CodingKeys.documentId)
        static let sourceId = Column(CodingKeys.sourceId)
        static let transcriptId = Column(CodingKeys.transcriptId)
        static let status = Column(CodingKeys.status)
        static let error = Column(CodingKeys.error)
        static let inputTokens = Column(CodingKeys.inputTokens)
        static let outputTokens = Column(CodingKeys.outputTokens)
        static let durationMs = Column(CodingKeys.durationMs)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case llmAccountId = "llm_account_id"
        case model
        case requestPayload = "request_payload"
        case responsePayload = "response_payload"
        case timestamp
        case documentId = "document_id"
        case sourceId = "source_id"
        case transcriptId = "transcript_id"
        case status
        case error
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case durationMs = "duration_ms"
    }

    init(from domain: APILogEntry) {
        self.id = domain.id == 0 ? nil : domain.id
        self.provider = domain.provider.rawValue
        self.llmAccountId = domain.llmAccountId
        self.model = domain.model
        self.requestPayload = domain.requestPayload
        self.responsePayload = domain.responsePayload
        self.timestamp = domain.timestamp
        self.documentId = domain.documentId
        self.sourceId = domain.sourceId
        self.transcriptId = domain.transcriptId
        self.status = domain.status
        self.error = domain.error
        self.inputTokens = domain.inputTokens
        self.outputTokens = domain.outputTokens
        self.durationMs = domain.durationMs
    }

    func toDomain() -> APILogEntry {
        APILogEntry(
            id: id ?? 0,
            provider: LLMProvider(rawValue: provider) ?? .claude,
            llmAccountId: llmAccountId,
            model: model,
            requestPayload: requestPayload,
            responsePayload: responsePayload,
            timestamp: timestamp,
            documentId: documentId,
            sourceId: sourceId,
            transcriptId: transcriptId,
            status: status,
            error: error,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: durationMs
        )
    }
}
