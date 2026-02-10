//
//  TrashView.swift
//  HiDocu
//
//  List of deleted documents with restore and permanent delete options.
//

import SwiftUI

struct TrashView: View {
    @State private var viewModel: TrashViewModel

    @State private var showEmptyTrashConfirmation = false
    @State private var idsToDeletePermanently: Set<Int64> = []
    @State private var idsToRestore: Set<Int64> = []

    init(trashService: TrashService) {
        _viewModel = State(initialValue: TrashViewModel(trashService: trashService))
    }

    var body: some View {
        @Bindable var bindableVM = viewModel
        let entriesById = Dictionary(uniqueKeysWithValues: viewModel.entries.map { ($0.id, $0) })

        DocumentTableView(
            rows: viewModel.sortedEntries,
            selection: $bindableVM.selection,
            sortOrder: $bindableVM.sortOrder,
            config: .trash,
            primaryAction: { row in
                idsToRestore = [row.id]
            },
            contextMenu: { selectedIds in
                Button(selectedIds.count == 1 ? "Restore" : "Restore \(selectedIds.count) Items") {
                    bindableVM.selection = selectedIds
                    Task {
                        await bindableVM.restoreSelection()
                    }
                }

                Divider()

                Button(
                    selectedIds.count == 1 ? "Delete Permanently" : "Delete \(selectedIds.count) Permanently",
                    role: .destructive
                ) {
                    idsToDeletePermanently = selectedIds
                }
            }
        )
        .confirmationDialog(
            idsToRestore.count == 1 ? "Restore Item" : "Restore \(idsToRestore.count) Items",
            isPresented: Binding(
                get: { !idsToRestore.isEmpty },
                set: { if !$0 { idsToRestore = [] } }
            )
        ) {
            Button(idsToRestore.count == 1 ? "Restore" : "Restore All") {
                let ids = idsToRestore
                idsToRestore = []
                bindableVM.selection = ids
                Task {
                    await bindableVM.restoreSelection()
                }
            }
        } message: {
            if idsToRestore.count == 1,
               let id = idsToRestore.first,
               let entry = entriesById[id] {
                Text("Restore \"\(entry.title)\" from Trash?")
            } else {
                Text("Restore \(idsToRestore.count) selected items from Trash?")
            }
        }
        .confirmationDialog(
            "Delete Permanently",
            isPresented: Binding(
                get: { !idsToDeletePermanently.isEmpty },
                set: { if !$0 { idsToDeletePermanently = [] } }
            )
        ) {
            Button(
                idsToDeletePermanently.count == 1
                ? "Delete Permanently"
                : "Delete \(idsToDeletePermanently.count) Permanently",
                role: .destructive
            ) {
                let ids = idsToDeletePermanently
                idsToDeletePermanently = []
                bindableVM.selection = ids
                Task {
                    await bindableVM.deleteSelectionPermanently()
                }
            }
        } message: {
            if idsToDeletePermanently.count == 1,
               let id = idsToDeletePermanently.first,
               let entry = entriesById[id] {
                Text("Permanently delete \"\(entry.title)\"? This cannot be undone.")
            } else {
                Text("Permanently delete \(idsToDeletePermanently.count) items? This cannot be undone.")
            }
        }
        .confirmationDialog(
            "Empty Trash",
            isPresented: $showEmptyTrashConfirmation
        ) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    await bindableVM.emptyTrash()
                }
            }
        } message: {
            Text("Permanently delete all items in the Trash? This cannot be undone.")
        }
        .errorBanner($bindableVM.errorMessage)
        .overlay {
            if viewModel.entries.isEmpty && !viewModel.isLoading {
                StandardEmptyStateView(
                    symbolName: "trash",
                    title: "Trash is Empty"
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty Trash") {
                    showEmptyTrashConfirmation = true
                }
                .disabled(viewModel.entries.isEmpty)
            }
        }
        .navigationTitle("Trash")
        .task {
            await bindableVM.loadEntries()
        }
    }
}
