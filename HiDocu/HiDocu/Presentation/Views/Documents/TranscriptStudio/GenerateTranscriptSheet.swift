//
//  GenerateTranscriptSheet.swift
//  HiDocu
//
//  Sheet for configuring AI-powered transcript generation.
//

import SwiftUI

struct GenerateTranscriptSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onGenerate: (String, Int) -> Void

    @State private var selectedModelId = "gemini-3-flash-preview"
    @State private var variantCount = 1

    private let availableModels: [(id: String, name: String)] = [
        ("gemini-3-pro-preview", "Gemini 3 Pro Preview"),
        ("gemini-3-flash-preview", "Gemini 3 Flash Preview")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Generate Transcript")
                .font(.headline)
                .padding(.bottom, 12)

            Form {
                Picker("Model", selection: $selectedModelId) {
                    ForEach(availableModels, id: \.id) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .pickerStyle(.menu)

                Stepper("Number of Variants: \(variantCount)",
                        value: $variantCount, in: 1...3)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Generate") {
                    onGenerate(selectedModelId, variantCount)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 12)
        }
        .padding()
        .frame(width: 400)
    }
}
