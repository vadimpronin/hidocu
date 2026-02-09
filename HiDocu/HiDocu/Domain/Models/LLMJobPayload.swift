//
//  LLMJobPayload.swift
//  HiDocu
//
//  Job-specific payload types for LLM queue operations.
//

import Foundation

/// Payload for a transcription job.
/// Contains audio file paths (relative to data directory) and source/transcript metadata.
struct TranscriptJobPayload: Codable, Sendable {
    let sourceId: Int64
    let transcriptId: Int64
    let audioRelativePaths: [String] // Relative paths to audio files
}

/// Payload for a summary generation job.
/// References the document to summarize.
struct SummaryJobPayload: Codable, Sendable {
    let documentId: Int64
    let modelOverride: String? // Optional specific model override
}

/// Payload for a transcript quality judge job.
/// Contains transcript IDs to evaluate.
struct JudgeJobPayload: Codable, Sendable {
    let documentId: Int64
    let transcriptIds: [Int64] // IDs of transcripts to judge
}
