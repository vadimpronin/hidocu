//
//  PromoteBanner.swift
//  HiDocu
//
//  Conditional banner shown when viewing a non-primary transcript variant.
//  Provides a one-click "Replace Document Body" action.
//

import SwiftUI

struct PromoteBanner: View {
    var onReplace: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Viewing alternative transcript")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            Spacer()

            Button("Replace Document Body") {
                onReplace()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Color.accentColor.opacity(0.12)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(height: 1)
        }
    }
}
