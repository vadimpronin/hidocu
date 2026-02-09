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

    /// Pending jobs waiting to execute (including deferred).
    private(set) var pendingJobs: [LLMJob] = []

    /// Recently completed jobs (last 5).
    private(set) var recentCompleted: [LLMJob] = []

    /// Recently failed jobs (last 5).
    private(set) var recentFailed: [LLMJob] = []

    /// Number of pending jobs (convenience for badges).
    var pendingCount: Int { pendingJobs.count }

    /// Whether any jobs are currently processing.
    var isProcessing: Bool { !activeJobs.isEmpty }

    /// Whether there are any jobs at all (active or pending).
    var hasWork: Bool { isProcessing || !pendingJobs.isEmpty }

    /// Updates the state from the queue processor (DB-backed, survives restart).
    func update(active: [LLMJob], pendingJobs: [LLMJob], recentFailed: [LLMJob], recentCompleted: [LLMJob]) {
        self.activeJobs = active
        self.pendingJobs = pendingJobs
        self.recentFailed = recentFailed
        self.recentCompleted = recentCompleted
    }
}
