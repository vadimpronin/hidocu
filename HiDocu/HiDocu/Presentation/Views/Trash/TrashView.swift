//
//  TrashView.swift
//  HiDocu
//
//  List of deleted documents with restore and permanent delete options.
//

import SwiftUI

struct TrashView: View {
    var trashService: TrashService

    @State private var entries: [DeletionLogEntry] = []
    @State private var isLoading = true
    @State private var showEmptyTrashConfirmation = false
    @State private var entryToDelete: DeletionLogEntry?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.documentTitle ?? "Untitled")
                            .font(.body.weight(.semibold))
                        HStack(spacing: 8) {
                            Text("Deleted \(entry.deletedAt, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(entry.daysRemaining) days left")
                                .font(.caption)
                                .foregroundStyle(entry.daysRemaining < 7 ? .red : .secondary)
                        }
                        if let path = entry.folderPath, !path.isEmpty {
                            Text("from \(path)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("Restore") {
                        Task {
                            do {
                                try await trashService.restoreDocument(
                                    deletionLogId: entry.id,
                                    toFolderId: nil
                                )
                                await loadEntries()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .contextMenu {
                    Button("Restore") {
                        Task {
                            do {
                                try await trashService.restoreDocument(
                                    deletionLogId: entry.id,
                                    toFolderId: nil
                                )
                                await loadEntries()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    Button("Delete Permanently", role: .destructive) {
                        entryToDelete = entry
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Permanently",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            presenting: entryToDelete
        ) { entry in
            Button("Delete Permanently", role: .destructive) {
                Task {
                    do {
                        try await trashService.permanentlyDelete(deletionLogId: entry.id)
                        await loadEntries()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: { entry in
            Text("Permanently delete \"\(entry.documentTitle ?? "Untitled")\"? This cannot be undone.")
        }
        .confirmationDialog(
            "Empty Trash",
            isPresented: $showEmptyTrashConfirmation
        ) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    do {
                        try await trashService.emptyTrash()
                        await loadEntries()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Permanently delete all items in the Trash? This cannot be undone.")
        }
        .errorBanner($errorMessage)
        .overlay {
            if entries.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.largeTitle)
                        .foregroundStyle(.quaternary)
                    Text("Trash is Empty")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty Trash") {
                    showEmptyTrashConfirmation = true
                }
                .disabled(entries.isEmpty)
            }
        }
        .navigationTitle("Trash")
        .task { await loadEntries() }
    }

    private func loadEntries() async {
        isLoading = true
        entries = (try? await trashService.listTrashedDocuments()) ?? []
        isLoading = false
    }
}
