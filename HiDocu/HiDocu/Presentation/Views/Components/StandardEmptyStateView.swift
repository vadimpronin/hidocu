//
//  StandardEmptyStateView.swift
//  HiDocu
//
//  Shared empty state placeholder used across list-based views.
//

import SwiftUI

struct StandardEmptyStateView: View {
    let symbolName: String
    let title: String
    var subtitle: String? = nil
    var errorMessage: String? = nil
    var isLoading: Bool = false
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if let onRefresh {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
