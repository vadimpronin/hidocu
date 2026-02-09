//
//  DocumentListView.swift
//  HiDocu
//
//  List of documents for a folder or all documents.
//

import SwiftUI

struct DocumentListView: View {
    var viewModel: DocumentListViewModel
    @Binding var selectedDocumentIds: Set<Int64>
    var documentService: DocumentService
    var fileSystemService: FileSystemService
    var folderId: Int64?
    var folders: [Folder] = []
    var folderNodes: [FolderNode] = []
    var folderName: String?
    var isAllDocumentsView: Bool = false
    var onBeforeDelete: (() -> Void)?

    @State private var documentIdsToDelete: Set<Int64> = []
    @State private var documentToRename: Document?
    @State private var renameText = ""
    @State private var documentToMove: Document?
    @State private var errorMessage: String?

    var body: some View {
        List(selection: $selectedDocumentIds) {
            ForEach(viewModel.documents) { doc in
                DocumentRowView(document: doc)
                    .tag(doc.id)
                    .contextMenu {
                        Button("Rename...") {
                            renameText = doc.title
                            documentToRename = doc
                        }
                        if !folders.isEmpty {
                            Button("Move to Folder...") {
                                documentToMove = doc
                            }
                        }
                        Button("Reveal in Finder") {
                            revealInFinder(diskPath: doc.diskPath)
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        Divider()
                        Button("Delete", role: .destructive) {
                            if selectedDocumentIds.contains(doc.id) && selectedDocumentIds.count > 1 {
                                documentIdsToDelete = selectedDocumentIds
                            } else {
                                documentIdsToDelete = [doc.id]
                            }
                        }
                    }
            }
            .onMove(perform: isAllDocumentsView ? nil : { source, destination in
                viewModel.moveDocuments(from: source, to: destination)
            })
        }
        .confirmationDialog(
            documentIdsToDelete.count == 1 ? "Delete Document" : "Delete \(documentIdsToDelete.count) Documents",
            isPresented: Binding(
                get: { !documentIdsToDelete.isEmpty },
                set: { if !$0 { documentIdsToDelete = [] } }
            )
        ) {
            let ids = documentIdsToDelete
            if ids.count == 1,
               let docId = ids.first,
               let doc = viewModel.documents.first(where: { $0.id == docId }) {
                Button("Delete \"\(doc.title)\"", role: .destructive) {
                    onBeforeDelete?()
                    selectedDocumentIds = []
                    documentIdsToDelete = []
                    Task {
                        do {
                            try await documentService.deleteDocument(id: docId)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } else {
                Button("Delete \(ids.count) Documents", role: .destructive) {
                    onBeforeDelete?()
                    selectedDocumentIds = []
                    documentIdsToDelete = []
                    Task {
                        let failureCount = await documentService.deleteDocuments(ids: ids)
                        if failureCount > 0 {
                            errorMessage = "Failed to delete \(failureCount) of \(ids.count) documents."
                        }
                    }
                }
            }
        } message: {
            if documentIdsToDelete.count == 1,
               let docId = documentIdsToDelete.first,
               let doc = viewModel.documents.first(where: { $0.id == docId }) {
                Text("This will move \"\(doc.title)\" to the Trash.")
            } else {
                Text("This will move \(documentIdsToDelete.count) documents to the Trash.")
            }
        }
        .sheet(item: $documentToRename) { doc in
            RenameDocumentSheet(
                title: renameText,
                onRename: { newTitle in
                    Task {
                        do {
                            try await documentService.renameDocument(id: doc.id, newTitle: newTitle)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            )
        }
        .sheet(item: $documentToMove) { doc in
            MoveDocumentSheet(
                folderNodes: folderNodes,
                onMove: { targetFolderId in
                    Task {
                        do {
                            try await documentService.moveDocument(id: doc.id, toFolderId: targetFolderId)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            )
        }
        .errorBanner($errorMessage)
        .overlay {
            if viewModel.documents.isEmpty && !viewModel.isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.quaternary)
                    Text("No Documents")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        let doc = try? await documentService.createDocument(
                            title: "Untitled",
                            folderId: folderId
                        )
                        if let doc {
                            selectedDocumentIds = [doc.id]
                        }
                    }
                } label: {
                    Label("New Document", systemImage: "plus")
                }
            }
            if !isAllDocumentsView {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("Name (A-Z)") {
                            viewModel.sortDocuments(folderId: folderId, by: .nameAscending)
                        }
                        Divider()
                        Button("Date Created (Oldest First)") {
                            viewModel.sortDocuments(folderId: folderId, by: .dateCreatedAscending)
                        }
                        Button("Date Created (Newest First)") {
                            viewModel.sortDocuments(folderId: folderId, by: .dateCreatedDescending)
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .navigationTitle(folderName ?? "All Documents")
    }

    private func revealInFinder(diskPath: String) {
        let folderURL = fileSystemService.dataDirectory.appendingPathComponent(diskPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }
}

// MARK: - Document Row

struct DocumentRowView: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(.body.weight(.semibold))
                .lineLimit(1)

            Text(document.createdAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)

            if let preview = document.bodyPreview, !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rename Sheet

private struct RenameDocumentSheet: View {
    @State var title: String
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Document")
                .font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .focused($isFocused)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    onRename(title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .onAppear { isFocused = true }
    }
}

// MARK: - Move Sheet

private struct MoveDocumentSheet: View {
    let folderNodes: [FolderNode]
    let onMove: (Int64?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFolderId: Int64?

    var body: some View {
        VStack(spacing: 16) {
            Text("Move to Folder")
                .font(.headline)
            List(selection: $selectedFolderId) {
                Text("No Folder (Root)")
                    .tag(nil as Int64?)
                ForEach(flattenedFolders, id: \.id) { entry in
                    HStack {
                        ForEach(0..<entry.depth, id: \.self) { _ in
                            Spacer()
                                .frame(width: 16)
                        }
                        Label(entry.name, systemImage: "folder")
                    }
                    .tag(entry.id as Int64?)
                }
            }
            .frame(width: 300, height: 250)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move") {
                    onMove(selectedFolderId)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private struct FlatFolder {
        let id: Int64
        let name: String
        let depth: Int
    }

    private var flattenedFolders: [FlatFolder] {
        var result: [FlatFolder] = []
        func flatten(_ nodes: [FolderNode], depth: Int) {
            for node in nodes {
                result.append(FlatFolder(id: node.id, name: node.folder.name, depth: depth))
                flatten(node.children, depth: depth + 1)
            }
        }
        flatten(folderNodes, depth: 0)
        return result
    }
}
