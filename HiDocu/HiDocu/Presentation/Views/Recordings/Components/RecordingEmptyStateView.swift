//
//  RecordingEmptyStateView.swift
//  HiDocu
//
//  Shared empty state placeholder for recording list views.
//

import SwiftUI

struct RecordingEmptyStateView: View {
    var title: String = "No Recordings"
    var subtitle: String?
    var errorMessage: String?
    var isLoading: Bool = false
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                onRefresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
