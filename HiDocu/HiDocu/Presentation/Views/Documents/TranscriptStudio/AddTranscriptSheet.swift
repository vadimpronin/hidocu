//
//  AddTranscriptSheet.swift
//  HiDocu
//
//  Sheet for adding a new transcript variant to a document.
//

import SwiftUI

struct AddTranscriptSheet: View {
    let documentId: Int64
    var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Transcript Variant")
                .font(.headline)

            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 200)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    Task {
                        await viewModel.addDocumentTranscript(
                            documentId: documentId,
                            text: text,
                            title: title.isEmpty ? nil : title
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }
}
