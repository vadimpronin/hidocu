//
//  DocumentStatusCell.swift
//  HiDocu
//
//  Table cell showing document link status for a recording.
//

import SwiftUI

struct DocumentStatusCell: View {
    let documentInfo: [DocumentLink]
    var isProcessing: Bool = false
    var onNavigateToDocument: ((Int64) -> Void)?
    var onCreateDocument: (() -> Void)?

    @State private var showPopover = false
    @State private var isHovering = false

    var body: some View {
        Group {
            if isProcessing {
                processingView
            } else if documentInfo.isEmpty {
                createButton
            } else if documentInfo.count == 1 {
                singleDocumentView
            } else {
                multiDocumentView
            }
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        HStack(spacing: 4) {
            Image(systemName: "gear")
                .symbolEffect(.rotate)
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text("Processing...")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
        .help("LLM processing in progress")
    }

    // MARK: - No Documents

    private var createButton: some View {
        Button {
            onCreateDocument?()
        } label: {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
        }
        .buttonStyle(.borderless)
        .opacity(isHovering ? 1.0 : 0.0)
        .onHover { hovering in isHovering = hovering }
        .help("Create document")
    }

    // MARK: - Single Document

    private var singleDocumentView: some View {
        Button {
            if let doc = documentInfo.first {
                onNavigateToDocument?(doc.id)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 12))
                Text(documentInfo.first?.title ?? "")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.borderless)
        .help(documentInfo.first?.title ?? "Go to document")
    }

    // MARK: - Multiple Documents

    private var multiDocumentView: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 12))
                Text("\(documentInfo.count) docs")
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.borderless)
        .help("\(documentInfo.count) linked documents")
        .popover(isPresented: $showPopover) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(documentInfo, id: \.id) { doc in
                    Button {
                        showPopover = false
                        onNavigateToDocument?(doc.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.system(size: 11))
                            Text(doc.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
        }
    }
}
