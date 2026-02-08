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
    // Delay text selection enabling to let layout stabilize first
    @State private var isSelectionEnabled = false

    var body: some View {
        content
            .onChange(of: isEditing) { _, newValue in
                editorFocused = newValue
                if !newValue {
                    // Reset selection state when exiting edit mode
                    isSelectionEnabled = false
                }
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
            // Render directly without delay, but delay selection capabilities
            let st = StructuredText(markdown: text)
            
            Group {
                if isSelectionEnabled {
                    st.textual.textSelection(.enabled)
                } else {
                    // Do NOT apply .textual.textSelection(.disabled) here.
                    // Even with .disabled, Textual might attach layout observers that trigger the loop.
                    // By returning the view without the modifier, we ensure no Textual logic runs until stable.
                    st
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            // The parent ScrollView will handle scrolling.
            .task {
                // Small delay to allow layout pass to complete before enabling selection geometry calculations
                try? await Task.sleep(for: .milliseconds(100))
                isSelectionEnabled = true
            }
        }
    }
}
