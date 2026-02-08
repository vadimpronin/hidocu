//
//  TranscriptStatusBar.swift
//  HiDocu
//
//  Bottom status bar showing editing state, word count, and edit toggle.
//

import SwiftUI

struct TranscriptStatusBar: View {
    let isModified: Bool
    let wordCount: Int
    @Binding var isEditing: Bool

    var body: some View {
        HStack {
            if isModified {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(wordCount) words")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button(isEditing ? "Done" : "Edit") {
                isEditing.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 28)
        .background(.bar)
    }
}
