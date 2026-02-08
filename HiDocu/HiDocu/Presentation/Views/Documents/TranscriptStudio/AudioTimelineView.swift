//
//  AudioTimelineView.swift
//  HiDocu
//
//  Unified audio player with segmented source timeline.
//  Transport controls are placeholder-only (disabled) until audio playback is implemented.
//

import SwiftUI

struct AudioTimelineView: View {
    let sources: [SourceWithDetails]
    @Binding var activeSourceIndex: Int
    var onAddSource: () -> Void
    var onRemoveSource: ((Int64) -> Void)?

    private var totalDuration: Int {
        sources.compactMap { $0.recording?.durationSeconds }.reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 12) {
            transportControls

            VStack(spacing: 4) {
                if sources.count > 1 {
                    sourceSegments
                }
                progressBar
            }
            .frame(maxWidth: .infinity)

            timeDisplay

            Button {
                onAddSource()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Add Source")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 80)
        .background(.regularMaterial)
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 8) {
            Button {} label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .disabled(true)

            Button {} label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .disabled(true)

            Button {} label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .disabled(true)
        }
    }

    // MARK: - Source Segments

    private var sourceSegments: some View {
        HStack(spacing: 2) {
            ForEach(Array(sources.enumerated()), id: \.element.id) { index, detail in
                let duration = detail.recording?.durationSeconds ?? 0
                let fraction = totalDuration > 0 ? Double(duration) / Double(totalDuration) : 1.0 / Double(max(sources.count, 1))

                RoundedRectangle(cornerRadius: 4)
                    .fill(index == activeSourceIndex
                        ? Color.accentColor.opacity(0.2)
                        : Color(nsColor: .quaternaryLabelColor))
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .overlay {
                        HStack(spacing: 4) {
                            Text(detail.recording?.displayTitle ?? detail.source.displayName ?? "Source \(index + 1)")
                                .lineLimit(1)
                            if let dur = detail.recording?.durationSeconds {
                                Text(dur.formattedDuration)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(fraction)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeSourceIndex = index
                    }
                    .contextMenu {
                        Button("Remove Source", role: .destructive) {
                            onRemoveSource?(detail.source.id)
                        }
                    }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        Capsule()
            .fill(Color(nsColor: .quaternaryLabelColor))
            .frame(height: 6)
    }

    // MARK: - Time Display

    private var timeDisplay: some View {
        Text("--:-- / \(totalDuration > 0 ? totalDuration.formattedDuration : "--:--")")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}
