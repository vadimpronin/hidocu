//
//  GenerateTranscriptSheet.swift
//  HiDocu
//
//  Sheet for configuring AI-powered transcript generation.
//

import SwiftUI

struct GenerateTranscriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.container) private var container

    var onGenerate: (String, Int) -> Void

    @State private var selectedModelId: String = ""
    @State private var variantCount = 1

    var body: some View {
        VStack(spacing: 0) {
            Text("Generate Transcript")
                .font(.headline)
                .padding(.bottom, 12)

            Form {
                if let container {
                    LabeledContent("Model") {
                        ModelPickerMenu(
                            models: container.llmService.availableModels.filter(\.acceptAudio),
                            selectedModelId: $selectedModelId
                        )
                    }
                } else {
                    Text("Loading models...")
                        .foregroundStyle(.secondary)
                }

                Stepper("Number of Variants: \(variantCount)",
                        value: $variantCount, in: 1...3)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Generate") {
                    // Extract just the modelId (after the colon) for the callback
                    let modelIdOnly = selectedModelId.split(separator: ":", maxSplits: 1).last.map(String.init) ?? selectedModelId
                    onGenerate(modelIdOnly, variantCount)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedModelId.isEmpty)
            }
            .padding(.top, 12)
        }
        .padding()
        .frame(width: 400)
        .task {
            // Initialize selectedModelId from settings when the sheet appears
            if let container, selectedModelId.isEmpty {
                let defaultTranscription = container.settingsService.settings.llm.defaultTranscriptionModel
                let defaultProvider = container.settingsService.settings.llm.defaultTranscriptionProvider
                if !defaultTranscription.isEmpty {
                    selectedModelId = "\(defaultProvider):\(defaultTranscription)"
                } else if let firstModel = container.llmService.availableModels.first {
                    selectedModelId = firstModel.id
                }
            }
        }
    }
}
