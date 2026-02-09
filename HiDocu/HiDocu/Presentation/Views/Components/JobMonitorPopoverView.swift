//
//  JobMonitorPopoverView.swift
//  HiDocu
//
//  Popover showing detailed LLM job queue status with active, pending, failed, and completed jobs.
//

import SwiftUI

/// Popover displaying LLM job queue status and job details.
struct JobMonitorPopoverView: View {
    let queueState: LLMQueueState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("LLM Jobs")
                    .font(.headline)
                Spacer()
                if queueState.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            Divider()

            // Job sections
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !queueState.activeJobs.isEmpty {
                        JobSection(title: "Active", icon: "gearshape.fill", color: .blue) {
                            ForEach(queueState.activeJobs) { job in
                                JobRow(job: job, showProgress: true)
                            }
                        }
                    }

                    if queueState.pendingCount > 0 {
                        JobSection(title: "Pending", icon: "clock.fill", color: .orange) {
                            HStack {
                                Text("\(queueState.pendingCount) jobs waiting")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }

                    if !queueState.recentFailed.isEmpty {
                        JobSection(title: "Failed", icon: "exclamationmark.triangle.fill", color: .red) {
                            ForEach(queueState.recentFailed) { job in
                                JobRow(job: job, showError: true)
                            }
                        }
                    }

                    if !queueState.recentCompleted.isEmpty {
                        JobSection(title: "Recent Completed", icon: "checkmark.circle.fill", color: .green) {
                            ForEach(queueState.recentCompleted) { job in
                                JobRow(job: job)
                            }
                        }
                    }

                    if queueState.activeJobs.isEmpty && queueState.pendingCount == 0 &&
                       queueState.recentFailed.isEmpty && queueState.recentCompleted.isEmpty {
                        Text("No jobs")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 350)
    }
}

// MARK: - Job Section

private struct JobSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)

            content
        }
    }
}

// MARK: - Job Row

private struct JobRow: View {
    let job: LLMJob
    var showProgress: Bool = false
    var showError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Job type icon
                Image(systemName: jobTypeIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                // Job description
                VStack(alignment: .leading, spacing: 2) {
                    Text(jobDescription)
                        .font(.subheadline)

                    HStack(spacing: 6) {
                        // Provider pill
                        Text(job.provider.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(job.provider.brandColor.opacity(0.2))
                            .foregroundStyle(job.provider.brandColor)
                            .clipShape(Capsule())

                        // Attempt count
                        if job.attemptCount > 1 {
                            Text("Attempt \(job.attemptCount)/\(job.maxAttempts)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // Timing
                        if let timing = jobTiming {
                            Text(timing)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if showProgress {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            // Error message
            if showError, let errorMessage = job.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var jobTypeIcon: String {
        switch job.jobType {
        case .transcription:
            return "waveform"
        case .summary:
            return "doc.text"
        case .judge:
            return "checkmark.seal"
        }
    }

    private var jobDescription: String {
        switch job.jobType {
        case .transcription:
            return "Transcribing"
        case .summary:
            return "Summarizing"
        case .judge:
            return "Judging"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt
    }()

    private var jobTiming: String? {
        if let completedAt = job.completedAt {
            return Self.relativeFormatter.localizedString(for: completedAt, relativeTo: Date())
        } else if let startedAt = job.startedAt {
            let elapsed = Date().timeIntervalSince(startedAt)
            return String(format: "%.0fs", elapsed)
        } else {
            return nil
        }
    }
}
