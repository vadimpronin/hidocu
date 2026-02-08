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
    @State private var isMarkdownReady = false

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .focused($editorFocused)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isMarkdownReady {
                ScrollView {
                    StructuredText(markdown: text)
                        .textual.textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                isMarkdownReady = true
                            }
                        }
                    }
            }
        }
        .onChange(of: isEditing) { _, newValue in
            editorFocused = newValue
            if !newValue {
                isMarkdownReady = false
                DispatchQueue.main.async {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isMarkdownReady = true
                    }
                }
            }
        }
    }
}
