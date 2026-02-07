//
//  FolderSettingsSheet.swift
//  HiDocu
//
//  Folder settings: transcription context, categorization context, preferences.
//

import SwiftUI

struct FolderSettingsSheet: View {
    let folderId: Int64
    var folderService: FolderService
    @Environment(\.dismiss) private var dismiss

    @State private var folder: Folder?
    @State private var transcriptionContext = ""
    @State private var categorizationContext = ""
    @State private var preferSummary = true
    @State private var minimizeBeforeLLM = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Folder Settings")
                .font(.headline)

            Form {
                Section("Context") {
                    VStack(alignment: .leading) {
                        Text("Transcription Context")
                            .font(.caption)
                        TextEditor(text: $transcriptionContext)
                            .frame(height: 80)
                            .font(.system(.body, design: .monospaced))
                            .border(Color.secondary.opacity(0.3))
                    }

                    VStack(alignment: .leading) {
                        Text("Categorization Context")
                            .font(.caption)
                        TextEditor(text: $categorizationContext)
                            .frame(height: 80)
                            .font(.system(.body, design: .monospaced))
                            .border(Color.secondary.opacity(0.3))
                    }
                }

                Section("Preferences") {
                    Toggle("Prefer Summary", isOn: $preferSummary)
                    Toggle("Minimize Before LLM", isOn: $minimizeBeforeLLM)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        try? await folderService.updateSettings(
                            id: folderId,
                            preferSummary: preferSummary,
                            minimizeBeforeLLM: minimizeBeforeLLM,
                            transcriptionContext: transcriptionContext,
                            categorizationContext: categorizationContext
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450, height: 500)
        .task {
            if let f = try? await folderService.fetchFolder(id: folderId) {
                folder = f
                transcriptionContext = f.transcriptionContext ?? ""
                categorizationContext = f.categorizationContext ?? ""
                preferSummary = f.preferSummary
                minimizeBeforeLLM = f.minimizeBeforeLLM
            }
        }
    }
}
