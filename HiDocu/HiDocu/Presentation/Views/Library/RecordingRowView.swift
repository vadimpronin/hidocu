//
//  RecordingRowView.swift
//  HiDocu
//
//  A single row in the recordings list showing title, metadata, and status.
//

import SwiftUI

struct RecordingRowView: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon
                .frame(width: 20)

            // Title + metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.displayTitle)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let createdAt = recording.createdAt {
                        Text(createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(recording.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let mode = recording.recordingMode {
                        modeBadge(mode)
                    }
                }
            }

            Spacer()

            // Status badge
            statusBadge
        }
        .padding(.vertical, 2)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch recording.status {
        case .new:
            Image(systemName: "circle.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .transcribed:
            Image(systemName: "text.bubble.fill")
                .font(.caption)
                .foregroundStyle(.purple)
        }
    }

    // MARK: - Mode Badge

    private func modeBadge(_ mode: RecordingMode) -> some View {
        HStack(spacing: 2) {
            Image(systemName: modeIcon(mode))
                .font(.caption2)
            Text(mode.rawValue.capitalized)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(.quaternary, in: Capsule())
    }

    private func modeIcon(_ mode: RecordingMode) -> String {
        switch mode {
        case .call:    return "phone"
        case .room:    return "mic"
        case .whisper: return "mouth"
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        Text(recording.status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(statusBadgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusBadgeColor.opacity(0.12), in: Capsule())
    }

    private var statusBadgeColor: Color {
        switch recording.status {
        case .new:         return .blue
        case .downloaded:  return .green
        case .transcribed: return .purple
        }
    }
}
