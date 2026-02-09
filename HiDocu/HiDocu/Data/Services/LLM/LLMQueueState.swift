//
//  LLMQueueState.swift
//  HiDocu
//
//  Observable state for the LLM job queue, exposed to SwiftUI.
//

import Foundation

/// Observable state for the LLM job queue, exposed to SwiftUI.
@Observable
@MainActor
final class LLMQueueState {
    /// Currently running jobs.
    private(set) var activeJobs: [LLMJob] = []

    /// Number of pending jobs waiting to execute.
    private(set) var pendingCount: Int = 0

    /// Recently completed jobs (last 5).
    private(set) var recentCompleted: [LLMJob] = []

    /// Recently failed jobs (last 5).
    private(set) var recentFailed: [LLMJob] = []

    /// Whether any jobs are currently processing.
    var isProcessing: Bool { !activeJobs.isEmpty }

    /// Whether there are any jobs at all (active or pending).
    var hasWork: Bool { isProcessing || pendingCount > 0 }

    /// Updates the state from the queue processor.
    func update(active: [LLMJob], pendingCount: Int) {
        self.activeJobs = active
        self.pendingCount = pendingCount
    }

    /// Records a completed job.
    func recordCompleted(_ job: LLMJob) {
        recentCompleted.insert(job, at: 0)
        if recentCompleted.count > 5 { recentCompleted.removeLast() }
    }

    /// Records a failed job.
    func recordFailed(_ job: LLMJob) {
        recentFailed.insert(job, at: 0)
        if recentFailed.count > 5 { recentFailed.removeLast() }
    }
}
