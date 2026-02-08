//
//  MarkdownEditableView.swift
//  HiDocu
//
//  Reusable component that toggles between rendered Markdown (view mode) and raw TextEditor (edit mode).
//

import SwiftUI
import Textual

struct MarkdownEditableView: View {
    @Binding var text: String
    @Binding var isEditing: Bool
    var placeholder: String = "No content"

    @FocusState private var editorFocused: Bool

    var body: some View {
        content
            .onChange(of: isEditing) { _, newValue in
                editorFocused = newValue
            }
    }

    @ViewBuilder
    private var content: some View {
        if isEditing {
            // Use ZStack to force TextEditor to match the height of the content (Text)
            ZStack(alignment: .topLeading) {
                // Invisible text to determine height
                Text(text + "\n") // Add newline to ensure cursor room at end
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.clear)
                    .padding(8) // Match TextEditor standard padding
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20) // Extra padding for safety

                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden) // If available, cleaner
                    .frame(minHeight: 200)
            }
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 8) {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                Button("Start Writing") {
                    isEditing = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Start writing \(placeholder.lowercased())")
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            StructuredText(markdown: text)
                .textual.textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }
}
