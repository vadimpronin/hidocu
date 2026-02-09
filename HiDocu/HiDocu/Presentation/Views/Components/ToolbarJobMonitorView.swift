//
//  ToolbarJobMonitorView.swift
//  HiDocu
//
//  Toolbar indicator showing LLM job queue status with badge and failure indicator.
//

import SwiftUI

/// Toolbar button showing job queue status with progress indicator and badges.
struct ToolbarJobMonitorView: View {
    let queueState: LLMQueueState
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                // Main icon
                Group {
                    if queueState.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "cpu")
                            .foregroundStyle(queueState.hasWork ? .primary : .secondary)
                    }
                }

                // Pending badge
                if queueState.pendingCount > 0 {
                    Text("\(queueState.pendingCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -8)
                }

                // Failure indicator
                if !queueState.recentFailed.isEmpty {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: 8, y: 8)
                }
            }
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .popover(isPresented: $showPopover) {
            JobMonitorPopoverView(queueState: queueState)
        }
        .help("LLM Job Queue")
    }
}
