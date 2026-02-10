//
//  LLMQueueService.swift
//  HiDocu
//
//  Background job processor for LLM operations with persistent queue.
//  Signal-based dispatch, per-account concurrency limits, automatic retry and recovery.
//

import Foundation

/// Background processor for LLM operations with persistent queue.
///
/// This actor:
/// - Maintains a persistent job queue via `LLMJobRepository`
/// - Processes jobs with per-account concurrency limits
/// - Handles retries with exponential backoff
/// - Recovers stale jobs on startup
/// - Signals to wake up on new work or retry timeouts
actor LLMQueueService {
    // MARK: - Dependencies

    private let jobRepository: any LLMJobRepository
    private let accountRepository: any LLMAccountRepository
    private let llmService: LLMService  // @MainActor, called via await
    private let quotaService: QuotaService  // @MainActor
    private let transcriptRepository: any TranscriptRepository
    private let documentService: DocumentService  // @MainActor
    private let fileSystemService: FileSystemService
    private let settingsService: SettingsService

    // MARK: - State

    private let state: LLMQueueState  // @MainActor, updated via await
    private var processingTask: Task<Void, Never>?
    private var signalContinuation: AsyncStream<Void>.Continuation?

    // MARK: - Concurrency Limits

    private let maxConcurrentGlobal = 3
    private let maxConcurrentPerAccount = 1
    private var runningJobs: [Int64: Task<Void, Never>] = [:]  // jobId -> task
    private var runningAccounts: [Int64: Int] = [:]  // accountId -> running job count
    private var accountRoundRobin: [LLMProvider: Int] = [:]  // round-robin counters for fair distribution

    // MARK: - Cleanup

    private let cleanupInterval: TimeInterval = 3600  // 1 hour
    private let completedJobRetention: TimeInterval = 86400  // 24 hours
    private var lastCleanupAt: Date = .distantPast

    // MARK: - Initialization

    init(
        jobRepository: any LLMJobRepository,
        accountRepository: any LLMAccountRepository,
        llmService: LLMService,
        quotaService: QuotaService,
        transcriptRepository: any TranscriptRepository,
        documentService: DocumentService,
        fileSystemService: FileSystemService,
        settingsService: SettingsService,
        state: LLMQueueState
    ) {
        self.jobRepository = jobRepository
        self.accountRepository = accountRepository
        self.llmService = llmService
        self.quotaService = quotaService
        self.transcriptRepository = transcriptRepository
        self.documentService = documentService
        self.fileSystemService = fileSystemService
        self.settingsService = settingsService
        self.state = state
    }

    // MARK: - Enqueue Methods

    /// Enqueues a transcription job for processing.
    ///
    /// - Parameters:
    ///   - documentId: Document ID for linking
    ///   - sourceId: Source ID containing the audio
    ///   - transcriptId: Transcript ID to store results
    ///   - provider: LLM provider to use
    ///   - model: Model identifier
    ///   - audioRelativePaths: Array of relative paths to audio files
    ///   - priority: Job priority (higher = sooner, default 0)
    /// - Returns: Created job record
    /// - Throws: Repository errors
    func enqueueTranscription(
        documentId: Int64,
        sourceId: Int64,
        transcriptId: Int64,
        provider: LLMProvider,
        model: String,
        audioRelativePaths: [String],
        priority: Int = 0
    ) async throws -> LLMJob {
        let payload = TranscriptJobPayload(
            sourceId: sourceId,
            transcriptId: transcriptId,
            audioRelativePaths: audioRelativePaths
        )
        let payloadJSON = try JSONEncoder().encode(payload)
        let payloadString = String(data: payloadJSON, encoding: .utf8)!

        let job = LLMJob(
            id: 0,
            jobType: .transcription,
            status: .pending,
            priority: priority,
            provider: provider,
            model: model,
            accountId: nil,
            payload: payloadString,
            resultRef: nil,
            errorMessage: nil,
            attemptCount: 0,
            maxAttempts: 3,
            nextRetryAt: nil,
            documentId: documentId,
            sourceId: sourceId,
            transcriptId: transcriptId,
            createdAt: Date(),
            startedAt: nil,
            completedAt: nil
        )

        let inserted = try await jobRepository.insert(job)
        AppLogger.llm.info("Enqueued transcription job id=\(inserted.id) for document \(documentId)")

        signal()
        return inserted
    }

    /// Enqueues a summary generation job for processing.
    ///
    /// - Parameters:
    ///   - documentId: Document ID to summarize
    ///   - provider: LLM provider to use
    ///   - model: Model identifier
    ///   - modelOverride: Optional full model override (e.g., "claude:claude-3-5-sonnet-20241022")
    ///   - priority: Job priority (higher = sooner, default 0)
    /// - Returns: Created job record
    /// - Throws: Repository errors
    func enqueueSummary(
        documentId: Int64,
        provider: LLMProvider,
        model: String,
        modelOverride: String? = nil,
        priority: Int = 0
    ) async throws -> LLMJob {
        let payload = SummaryJobPayload(
            documentId: documentId,
            modelOverride: modelOverride
        )
        let payloadJSON = try JSONEncoder().encode(payload)
        let payloadString = String(data: payloadJSON, encoding: .utf8)!

        let job = LLMJob(
            id: 0,
            jobType: .summary,
            status: .pending,
            priority: priority,
            provider: provider,
            model: model,
            accountId: nil,
            payload: payloadString,
            resultRef: nil,
            errorMessage: nil,
            attemptCount: 0,
            maxAttempts: 3,
            nextRetryAt: nil,
            documentId: documentId,
            sourceId: nil,
            transcriptId: nil,
            createdAt: Date(),
            startedAt: nil,
            completedAt: nil
        )

        let inserted = try await jobRepository.insert(job)
        AppLogger.llm.info("Enqueued summary job id=\(inserted.id) for document \(documentId)")

        signal()
        return inserted
    }

    /// Enqueues a judge job to evaluate multiple transcripts.
    ///
    /// - Parameters:
    ///   - documentId: Document ID for context
    ///   - transcriptIds: Array of transcript IDs to evaluate
    ///   - provider: LLM provider to use
    ///   - model: Model identifier
    ///   - priority: Job priority (higher = sooner, default 0)
    /// - Returns: Created job record
    /// - Throws: Repository errors
    func enqueueJudge(
        documentId: Int64,
        transcriptIds: [Int64],
        provider: LLMProvider,
        model: String,
        priority: Int = 0
    ) async throws -> LLMJob {
        let payload = JudgeJobPayload(
            documentId: documentId,
            transcriptIds: transcriptIds
        )
        let payloadJSON = try JSONEncoder().encode(payload)
        let payloadString = String(data: payloadJSON, encoding: .utf8)!

        let job = LLMJob(
            id: 0,
            jobType: .judge,
            status: .pending,
            priority: priority,
            provider: provider,
            model: model,
            accountId: nil,
            payload: payloadString,
            resultRef: nil,
            errorMessage: nil,
            attemptCount: 0,
            maxAttempts: 3,
            nextRetryAt: nil,
            documentId: documentId,
            sourceId: nil,
            transcriptId: nil,
            createdAt: Date(),
            startedAt: nil,
            completedAt: nil
        )

        let inserted = try await jobRepository.insert(job)
        AppLogger.llm.info("Enqueued judge job id=\(inserted.id) for document \(documentId)")

        signal()
        return inserted
    }

    // MARK: - Control

    /// Starts the background processing loop.
    func startProcessing() {
        guard processingTask == nil else {
            AppLogger.llm.warning("Queue processor already running")
            return
        }

        processingTask = Task { [weak self] in
            await self?.processLoop()
        }

        AppLogger.llm.info("Queue processor started")
    }

    /// Stops the background processing loop.
    func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
        signalContinuation?.finish()
        signalContinuation = nil
        AppLogger.llm.info("Queue processor stopped")
    }

    /// Cancels a specific job by ID.
    ///
    /// - Parameter jobId: Job ID to cancel
    /// - Throws: Repository errors
    func cancelJob(_ jobId: Int64) async throws {
        guard let job = try await jobRepository.fetchById(jobId) else {
            AppLogger.llm.warning("Job \(jobId) not found for cancellation")
            return
        }

        // Cancel running task if present
        if let task = runningJobs[jobId] {
            task.cancel()
            runningJobs.removeValue(forKey: jobId)
            decrementAccountCount(for: job.accountId)
        }

        // Update job status
        var cancelled = job
        cancelled.status = .cancelled
        cancelled.completedAt = Date()
        try await jobRepository.update(cancelled)

        AppLogger.llm.info("Cancelled job id=\(jobId)")
        signal()
    }

    /// Cancels all jobs for a specific document, including in-memory running tasks.
    ///
    /// - Parameter documentId: Document ID to cancel jobs for
    /// - Throws: Repository errors
    func cancelAllForDocument(_ documentId: Int64) async throws {
        // Cancel in-memory tasks for running jobs belonging to this document
        let documentJobs = try await jobRepository.fetchForDocument(documentId)
        for job in documentJobs where job.status == .running {
            if let task = runningJobs[job.id] {
                task.cancel()
                runningJobs.removeValue(forKey: job.id)
                decrementAccountCount(for: job.accountId)
            }
        }

        // Bulk cancel in DB
        try await jobRepository.cancelForDocument(documentId)
        AppLogger.llm.info("Cancelled all jobs for document \(documentId)")
        signal()
    }

    // MARK: - Signal-Based Dispatch

    /// Signals the processor that new work is available.
    private func signal() {
        signalContinuation?.yield()
    }

    /// Notify the queue that accounts changed (added, removed, or unpaused).
    /// Clears deferred retry times for the given provider so pending jobs become
    /// immediately eligible, then wakes the processor.
    func notifyAccountsChanged(provider: LLMProvider) async {
        do {
            try await jobRepository.clearDeferredRetry(provider: provider)
            AppLogger.llm.info("Queue: Cleared deferred retries for \(provider.rawValue) after account change")
        } catch {
            AppLogger.llm.error("Queue: Failed to clear deferred retries: \(error.localizedDescription)")
        }
        signal()
    }

    // MARK: - Processing Loop

    /// Main processing loop with signal-based wake-up.
    private func processLoop() async {
        // Create the signal stream (bufferingNewest(1) since all signals are identical voids)
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.signalContinuation = continuation

        // On startup, recover stale running jobs (started > 2 hours ago)
        await recoverStaleJobs()

        while !Task.isCancelled {
            // Try to pick up and execute available jobs
            await pickUpJobs()

            // Periodically clean up old completed jobs
            await cleanupCompletedJobs()

            // Wait for either:
            // - A signal that new work is available (from enqueue methods)
            // - A 30-second heartbeat timeout (for retry-after recovery)
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await _ in stream { return }
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(30))
                    }
                    // Wait for whichever finishes first
                    try await group.next()
                    group.cancelAll()
                }
            } catch {
                // Task.sleep throws on cancellation - that's fine
                if Task.isCancelled { break }
            }
        }

        continuation.finish()
    }

    /// Picks up pending/retryable jobs and starts execution.
    private func pickUpJobs() async {
        let activeCount = runningJobs.count
        let slotsAvailable = maxConcurrentGlobal - activeCount
        guard slotsAvailable > 0 else { return }

        // Fetch pending jobs + retryable jobs
        do {
            let pendingJobs = try await jobRepository.fetchPending(limit: slotsAvailable)
            let retryableJobs = try await jobRepository.fetchRetryable(now: Date())

            // Deduplicate by job ID
            var seen = Set<Int64>()
            let candidates = (pendingJobs + retryableJobs)
                .filter { job in
                    guard seen.insert(job.id).inserted else { return false }
                    return runningJobs[job.id] == nil
                }

            var activeAccountsCache: [LLMProvider: [LLMAccount]] = [:]
            var started = 0
            for job in candidates {
                guard started < slotsAvailable else { break }

                // Lazy-load active accounts for this provider
                if activeAccountsCache[job.provider] == nil {
                    activeAccountsCache[job.provider] = try await accountRepository.fetchActive(provider: job.provider)
                }

                // Find accounts not at their concurrency limit
                guard let providerAccounts = activeAccountsCache[job.provider] else { continue }
                let freeAccounts = providerAccounts.filter {
                    runningAccounts[$0.id, default: 0] < maxConcurrentPerAccount
                }
                guard !freeAccounts.isEmpty else { continue }

                // Round-robin among free accounts
                let counter = accountRoundRobin[job.provider, default: 0]
                let selected = freeAccounts[counter % freeAccounts.count]
                accountRoundRobin[job.provider] = counter + 1

                var jobWithAccount = job
                jobWithAccount.accountId = selected.id
                await startJob(jobWithAccount)
                started += 1
            }

            // Update UI state
            await updateState()
        } catch {
            AppLogger.llm.error("Queue: Failed to fetch jobs: \(error.localizedDescription)")
        }
    }

    /// Decrements the running job count for an account and removes the entry when it reaches zero.
    private func decrementAccountCount(for accountId: Int64?) {
        guard let accountId else { return }
        let count = (runningAccounts[accountId] ?? 0) - 1
        if count <= 0 {
            runningAccounts.removeValue(forKey: accountId)
        } else {
            runningAccounts[accountId] = count
        }
    }

    /// Starts a job execution in the background.
    /// The job must have `accountId` assigned by `pickUpJobs()` before calling this method.
    private func startJob(_ job: LLMJob) async {
        guard let accountId = job.accountId else {
            AppLogger.llm.error("Job \(job.id) started without accountId, skipping")
            return
        }

        // Mark as running in DB (also persists accountId)
        var runningJob = job
        runningJob.status = .running
        runningJob.startedAt = Date()
        do {
            try await jobRepository.update(runningJob)
        } catch {
            AppLogger.llm.error("Failed to mark job \(job.id) as running: \(error.localizedDescription)")
            return
        }

        // Track concurrency by account
        runningAccounts[accountId, default: 0] += 1

        // Spawn task
        let task = Task {
            await self.executeJob(runningJob)
        }
        runningJobs[job.id] = task
    }

    /// Executes a single job.
    private func executeJob(_ job: LLMJob) async {
        do {
            switch job.jobType {
            case .transcription:
                try await executeTranscription(job)
            case .summary:
                try await executeSummary(job)
            case .judge:
                try await executeJudge(job)
            }

            // Success — counts as an attempt (provider was reached)
            var completed = job
            completed.attemptCount += 1
            completed.status = .completed
            completed.completedAt = Date()
            do {
                try await jobRepository.update(completed)
            } catch {
                AppLogger.llm.error("Failed to mark job \(job.id) as completed: \(error.localizedDescription)")
            }

        } catch let error as LLMError {
            await handleJobError(job, error: error)
        } catch {
            await handleJobError(job, error: LLMError.networkError(underlying: error.localizedDescription))
        }

        // Cleanup tracking
        runningJobs.removeValue(forKey: job.id)
        decrementAccountCount(for: job.accountId)

        // After a transcription job finishes, check if all are done and enqueue judge if ready.
        if job.jobType == .transcription, let documentId = job.documentId {
            await checkAndEnqueueJudge(documentId: documentId)
        }

        // Signal to pick up more work
        signal()
        await updateState()
    }

    /// Handles job execution errors with retry logic.
    ///
    /// Only errors where we received a response from the provider count as attempts.
    /// Network/local errors retry with escalating backoff without consuming attempts.
    private func handleJobError(_ job: LLMJob, error: LLMError) async {
        var failedJob = job
        failedJob.errorMessage = error.localizedDescription

        // Determine if we actually reached the provider (exhaustive — compiler enforces coverage)
        let isProviderReached: Bool
        switch error {
        case .apiError, .rateLimited, .invalidResponse, .allAccountsExhausted:
            isProviderReached = true
        case .networkError, .tokenRefreshFailed, .authenticationFailed, .oauthTimeout,
             .noAccountsConfigured, .portInUse:
            isProviderReached = false
        case .documentNotFound:
            // Local data issue — fail immediately, no retry
            failedJob.status = .failed
            failedJob.completedAt = Date()
            try? await jobRepository.update(failedJob)
            AppLogger.llm.error("Job \(job.id) failed: document not found")
            await markTranscriptFailedIfNeeded(job)
            return
        case .generationCancelled:
            failedJob.status = .cancelled
            failedJob.completedAt = Date()
            try? await jobRepository.update(failedJob)
            AppLogger.llm.info("Job \(job.id) cancelled")
            return
        }

        // Only count as attempt if provider was actually reached
        if isProviderReached {
            failedJob.attemptCount += 1
        }

        // Rate limit handling: record and use paused_until for retry timing
        // Note: accountId is typically nil on enqueued jobs — rate limits are also
        // recorded inside LLMService when it catches them during execution.
        var isRateLimited = false
        if case .rateLimited(let provider, let retryAfter) = error {
            isRateLimited = true
            if let accountId = job.accountId {
                await quotaService.recordRateLimit(accountId: accountId, provider: provider, retryAfter: retryAfter)
            }
        } else if case .allAccountsExhausted = error {
            isRateLimited = true
        }

        // Network/local errors: retry with escalating backoff, never fail permanently
        if !isProviderReached {
            // Escalate: 30s, 60s, 120s, 300s (capped) based on consecutive network failures
            // attemptCount stays at 0 for network errors, so use a derived counter
            let networkRetries = max(0, failedJob.attemptCount == 0
                ? Int(failedJob.nextRetryAt?.timeIntervalSince(failedJob.createdAt) ?? 0) / 30
                : 0)
            let delays: [TimeInterval] = [30, 60, 120, 300]
            let delay = delays[min(networkRetries, delays.count - 1)]
            failedJob.status = .pending
            failedJob.nextRetryAt = Date().addingTimeInterval(delay)
            do {
                try await jobRepository.update(failedJob)
            } catch {
                AppLogger.llm.error("Failed to schedule network retry for job \(job.id): \(error.localizedDescription)")
            }
            AppLogger.llm.info("Job \(job.id) network error, retry in \(Int(delay))s (attempts unchanged at \(failedJob.attemptCount)): \(failedJob.errorMessage ?? "")")
            return
        }

        // Provider-reached errors: retry with limit
        if failedJob.attemptCount < failedJob.maxAttempts {
            failedJob.status = .pending  // back to pending for retry

            if isRateLimited {
                // Check if other unpaused accounts are available for immediate failover
                let activeAccounts = (try? await accountRepository.fetchActive(provider: job.provider)) ?? []
                failedJob.accountId = nil  // Clear — force pickUpJobs to re-select

                if !activeAccounts.isEmpty {
                    // Unpaused accounts available — retry immediately with account re-selection
                    failedJob.nextRetryAt = Date()
                    failedJob.errorMessage = nil
                    AppLogger.llm.info("Job \(job.id) rate-limited, retrying immediately with another account (\(activeAccounts.count) available)")
                } else {
                    // All accounts paused — wait for earliest unpause
                    let retryAt = await nextAccountAvailableDate(for: job.provider)
                    failedJob.nextRetryAt = retryAt
                    let delay = Int(retryAt.timeIntervalSince(Date()))
                    AppLogger.llm.info("Job \(job.id) rate-limited, all accounts paused, retry in \(delay)s (attempt \(failedJob.attemptCount)/\(failedJob.maxAttempts))")
                }
            } else {
                let backoff = backoffInterval(attempt: failedJob.attemptCount)
                failedJob.nextRetryAt = Date().addingTimeInterval(backoff)
                AppLogger.llm.info("Job \(job.id) scheduled for retry after \(Int(backoff))s (attempt \(failedJob.attemptCount)/\(failedJob.maxAttempts))")
            }

            do {
                try await jobRepository.update(failedJob)
            } catch {
                AppLogger.llm.error("Failed to schedule retry for job \(job.id): \(error.localizedDescription)")
            }
        } else {
            // Max retries exceeded — permanent failure
            failedJob.status = .failed
            failedJob.completedAt = Date()
            do {
                try await jobRepository.update(failedJob)
            } catch {
                AppLogger.llm.error("Failed to mark job \(job.id) as failed: \(error.localizedDescription)")
            }
            AppLogger.llm.error("Job \(job.id) failed after \(failedJob.maxAttempts) attempts: \(error.localizedDescription)")
            await markTranscriptFailedIfNeeded(job)
        }
    }

    /// If the job is a transcription job, marks the associated transcript as failed.
    private func markTranscriptFailedIfNeeded(_ job: LLMJob) async {
        guard job.jobType == .transcription else { return }
        do {
            let payloadData = Data(job.payload.utf8)
            let payload = try JSONDecoder().decode(TranscriptJobPayload.self, from: payloadData)

            if var transcript = try await transcriptRepository.fetchById(payload.transcriptId) {
                transcript.status = .failed
                transcript.modifiedAt = Date()
                try await transcriptRepository.update(transcript)
                AppLogger.llm.info("Marked transcript \(payload.transcriptId) as failed after job failure")
            }
        } catch {
            AppLogger.llm.error("Failed to mark transcript as failed: \(error.localizedDescription)")
        }
    }

    /// Returns the date when the next account becomes available for a provider.
    private func nextAccountAvailableDate(for provider: LLMProvider) async -> Date {
        let now = Date()
        do {
            let allAccounts = try await accountRepository.fetchAll(provider: provider)
            let nextAvailable = allAccounts
                .compactMap { $0.pausedUntil }
                .filter { $0 > now }
                .min()

            if let nextAvailable {
                return nextAvailable.addingTimeInterval(5)  // 5s buffer after unpause
            }
        } catch {
            // Fall through to default
        }
        // Fallback: 5 minutes
        return now.addingTimeInterval(300)
    }

    /// Computes backoff interval for retry attempts.
    private func backoffInterval(attempt: Int) -> TimeInterval {
        min(30 * pow(2, Double(attempt - 1)), 300) // 30s, 60s, 120s, 240s, capped at 300s
    }

    /// Recovers stale jobs that were running but never completed (app crash recovery).
    private func recoverStaleJobs() async {
        // Reset jobs that were "running" but started > 2 hours ago
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        do {
            let activeJobs = try await jobRepository.fetchActive()
            for var job in activeJobs {
                if let startedAt = job.startedAt, startedAt < twoHoursAgo {
                    job.status = .pending
                    job.startedAt = nil
                    try await jobRepository.update(job)
                    AppLogger.llm.info("Queue: Recovered stale job id=\(job.id)")
                }
            }
        } catch {
            AppLogger.llm.error("Queue: Failed to recover stale jobs: \(error.localizedDescription)")
        }
    }

    /// Updates the UI state with current queue status.
    private func updateState() async {
        do {
            let active = try await jobRepository.fetchActive()
            let pending = try await jobRepository.fetchAllPending(limit: 20)
            let failed = try await jobRepository.fetchRecentFailed(limit: 5)
            let completed = try await jobRepository.fetchRecentCompleted(limit: 5)
            await MainActor.run {
                state.update(active: active, pendingJobs: pending, recentFailed: failed, recentCompleted: completed)
            }
        } catch {
            AppLogger.llm.error("Queue: Failed to update state: \(error.localizedDescription)")
        }
    }

    // MARK: - Job Execution Methods

    /// Executes a transcription job.
    private func executeTranscription(_ job: LLMJob) async throws {
        // Decode payload
        let payloadData = Data(job.payload.utf8)
        let payload = try JSONDecoder().decode(TranscriptJobPayload.self, from: payloadData)

        AppLogger.llm.info("Executing transcription job \(job.id) for transcript \(payload.transcriptId)")

        // Load audio files from paths
        let attachments = try await loadAudioAttachments(relativePaths: payload.audioRelativePaths)

        // Call LLMService to generate transcript
        let transcriptText = try await self.llmService.generateSingleTranscript(
            attachments: attachments,
            model: job.model,
            transcriptId: payload.transcriptId,
            documentId: job.documentId,
            sourceId: job.sourceId,
            accountId: job.accountId
        )

        // Update transcript record with result text
        if var transcript = try await transcriptRepository.fetchById(payload.transcriptId) {
            transcript.fullText = transcriptText
            transcript.status = .ready
            transcript.modifiedAt = Date()
            try await transcriptRepository.update(transcript)
            AppLogger.llm.info("Updated transcript \(payload.transcriptId) with generated text")
        } else {
            AppLogger.llm.warning("Transcript \(payload.transcriptId) not found after generation")
        }
    }

    /// Executes a summary generation job.
    private func executeSummary(_ job: LLMJob) async throws {
        // Decode payload
        let payloadData = Data(job.payload.utf8)
        let payload = try JSONDecoder().decode(SummaryJobPayload.self, from: payloadData)

        AppLogger.llm.info("Executing summary job \(job.id) for document \(payload.documentId)")

        // Load document
        guard let document = try await self.documentService.fetchDocument(id: payload.documentId) else {
            throw LLMError.documentNotFound
        }

        // Call LLMService to generate summary
        _ = try await self.llmService.generateSummary(for: document, modelOverride: payload.modelOverride, accountId: job.accountId)

        AppLogger.llm.info("Summary generated for document \(payload.documentId)")
    }

    /// Executes a judge job to evaluate transcripts.
    private func executeJudge(_ job: LLMJob) async throws {
        // Decode payload
        let payloadData = Data(job.payload.utf8)
        let payload = try JSONDecoder().decode(JudgeJobPayload.self, from: payloadData)

        AppLogger.llm.info("Executing judge job \(job.id) for document \(payload.documentId)")

        // Load transcripts
        var transcripts: [Transcript] = []
        for transcriptId in payload.transcriptIds {
            if let transcript = try await transcriptRepository.fetchById(transcriptId) {
                transcripts.append(transcript)
            }
        }

        guard transcripts.count >= 2 else {
            throw LLMError.invalidResponse(detail: "Need at least 2 transcripts to evaluate, found \(transcripts.count)")
        }

        // Call LLMService to evaluate
        let judgeResponse = try await self.llmService.evaluateTranscripts(
            transcripts: transcripts,
            documentId: payload.documentId,
            provider: job.provider,
            model: job.model,
            accountId: job.accountId
        )

        // Set the best transcript as primary
        try await transcriptRepository.setPrimaryForDocument(id: judgeResponse.bestId, documentId: payload.documentId)

        // Write the best transcript text as document body
        if let bestTranscript = transcripts.first(where: { $0.id == judgeResponse.bestId }),
           let bestText = bestTranscript.fullText {
            try await self.documentService.writeBodyById(documentId: payload.documentId, content: bestText)
            AppLogger.llm.info("Wrote primary transcript \(judgeResponse.bestId) to document \(payload.documentId) body")
        }

        AppLogger.llm.info("Judge evaluation completed for document \(payload.documentId): bestId=\(judgeResponse.bestId)")

        // Auto-enqueue summary generation
        await enqueueSummaryIfNeeded(documentId: payload.documentId)
    }

    /// Enqueues a summary job for a document if one doesn't already exist.
    private func enqueueSummaryIfNeeded(documentId: Int64) async {
        do {
            // Check if we already have a summary job for this document
            let allJobs = try await jobRepository.fetchForDocument(documentId)
            let existingSummaryJobs = allJobs.filter { $0.jobType == .summary }
            guard existingSummaryJobs.isEmpty else {
                AppLogger.llm.debug("Summary job already exists for document \(documentId)")
                return
            }

            // Get summary settings
            let settings = await MainActor.run { self.settingsService.settings.llm }
            let summaryProvider = LLMProvider(rawValue: settings.defaultProvider) ?? .claude
            let summaryModel = settings.defaultModel.isEmpty ? "claude-3-5-sonnet-20241022" : settings.defaultModel

            _ = try await enqueueSummary(
                documentId: documentId,
                provider: summaryProvider,
                model: summaryModel,
                modelOverride: nil,
                priority: 0
            )

            AppLogger.llm.info("Auto-enqueued summary job for document \(documentId)")
        } catch {
            AppLogger.llm.error("Failed to auto-enqueue summary for document \(documentId): \(error.localizedDescription)")
        }
    }

    /// Loads audio attachments from relative paths.
    nonisolated private func loadAudioAttachments(relativePaths: [String]) async throws -> [LLMAttachment] {
        var attachments: [LLMAttachment] = []

        // Get data directory from FileSystemService (it's @Observable but dataDirectory is computed, not stored state)
        let dataDirectory = await MainActor.run {
            self.fileSystemService.dataDirectory
        }

        for relativePath in relativePaths {
            let fileURL = dataDirectory.appendingPathComponent(relativePath)

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                AppLogger.llm.error("Audio file not found: \(fileURL.path)")
                throw LLMError.invalidResponse(detail: "Audio file not found: \(relativePath)")
            }

            let fileData: Data
            do {
                fileData = try Data(contentsOf: fileURL)
            } catch {
                AppLogger.llm.error("Failed to read audio file: \(error.localizedDescription)")
                throw LLMError.invalidResponse(detail: "Failed to read audio file: \(relativePath)")
            }

            let ext = fileURL.pathExtension.lowercased()
            let mimeType = Self.audioMimeTypes[ext] ?? "audio/mpeg"
            attachments.append(LLMAttachment(data: fileData, mimeType: mimeType))
        }

        guard !attachments.isEmpty else {
            throw LLMError.invalidResponse(detail: "No audio files found in paths")
        }

        let totalSize = attachments.reduce(0) { $0 + $1.data.count }
        let sizeMBLog = Double(totalSize) / (1024 * 1024)
        AppLogger.llm.info("Loaded \(attachments.count) audio file(s), total \(String(format: "%.1f", sizeMBLog)) MB")

        return attachments
    }

    /// Checks if all transcription jobs for a document are complete, and if so, enqueues a judge job.
    private func checkAndEnqueueJudge(documentId: Int64) async {
        do {
            // Fetch all jobs for this document
            let allJobs = try await jobRepository.fetchForDocument(documentId)

            // Filter transcription jobs
            let transcriptionJobs = allJobs.filter { $0.jobType == .transcription }

            // Check if all transcription jobs have reached a terminal state
            let allComplete = transcriptionJobs.allSatisfy { job in
                job.status == .completed || job.status == .failed || job.status == .cancelled
            }

            guard allComplete else {
                AppLogger.llm.debug("Not all transcription jobs complete for document \(documentId), skipping judge")
                return
            }

            // Check if we already have a judge job for this document
            let existingJudgeJobs = allJobs.filter { $0.jobType == .judge }
            guard existingJudgeJobs.isEmpty else {
                AppLogger.llm.debug("Judge job already exists for document \(documentId)")
                return
            }

            // Get transcript IDs only from successfully completed jobs
            let transcriptIds = transcriptionJobs
                .filter { $0.status == .completed }
                .compactMap { $0.transcriptId }
            guard transcriptIds.count >= 2 else {
                AppLogger.llm.debug("Not enough transcripts (\(transcriptIds.count)) for judge, skipping")
                return
            }

            // Enqueue judge job using settings defaults
            let settings = await MainActor.run { self.settingsService.settings.llm }
            let judgeProvider = LLMProvider(rawValue: settings.defaultJudgeProvider) ?? .gemini
            let judgeModel = settings.defaultJudgeModel.isEmpty ? "gemini-3-pro-preview" : settings.defaultJudgeModel

            _ = try await enqueueJudge(
                documentId: documentId,
                transcriptIds: transcriptIds,
                provider: judgeProvider,
                model: judgeModel,
                priority: 0
            )

            AppLogger.llm.info("Auto-enqueued judge job for document \(documentId) with \(transcriptIds.count) transcripts")
        } catch {
            AppLogger.llm.error("Failed to check/enqueue judge for document \(documentId): \(error.localizedDescription)")
        }
    }

    // MARK: - Cleanup

    /// Deletes completed jobs older than the retention period.
    /// Called periodically from the processing loop.
    private func cleanupCompletedJobs() async {
        let now = Date()
        guard now.timeIntervalSince(lastCleanupAt) >= cleanupInterval else { return }
        lastCleanupAt = now

        let cutoff = now.addingTimeInterval(-completedJobRetention)
        do {
            try await jobRepository.deleteCompleted(olderThan: cutoff)
            AppLogger.llm.debug("Queue: Cleaned up completed jobs older than 24h")
        } catch {
            AppLogger.llm.error("Queue: Failed to clean up completed jobs: \(error.localizedDescription)")
        }
    }

    // MARK: - Job Status Query

    /// Checks if a pending or running summary job exists for the given document.
    func hasPendingSummaryJob(documentId: Int64) async -> Bool {
        do {
            let jobs = try await jobRepository.fetchForDocument(documentId)
            return jobs.contains { $0.jobType == .summary && ($0.status == .pending || $0.status == .running) }
        } catch {
            return false
        }
    }

    /// Checks if pending or running transcription/judge jobs exist for the given document.
    /// These are the jobs that produce document body content.
    func hasPendingBodyJob(documentId: Int64) async -> Bool {
        do {
            let jobs = try await jobRepository.fetchForDocument(documentId)
            return jobs.contains {
                ($0.jobType == .transcription || $0.jobType == .judge) &&
                ($0.status == .pending || $0.status == .running)
            }
        } catch {
            return false
        }
    }

    // MARK: - Constants

    /// MIME type mapping for audio file extensions.
    private static let audioMimeTypes: [String: String] = [
        "hda": "audio/mpeg",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "wav": "audio/wav",
        "aac": "audio/aac",
        "ogg": "audio/ogg",
        "flac": "audio/flac",
        "opus": "audio/opus",
        "aiff": "audio/aiff"
    ]
}
