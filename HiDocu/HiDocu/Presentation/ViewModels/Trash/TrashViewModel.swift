//
//  TrashViewModel.swift
//  HiDocu
//
//  ViewModel for trash table and actions.
//

import Foundation

@Observable
@MainActor
final class TrashViewModel {
    var entries: [DeletionLogEntry] = []
    var selection: Set<Int64> = []
    var sortOrder: [KeyPathComparator<DeletionLogEntry>] = [
        .init(\.deletedAt, order: .reverse)
    ]

    var isLoading = false
    var errorMessage: String?

    var sortedEntries: [DeletionLogEntry] {
        entries.sorted(using: sortOrder)
    }

    private let trashService: TrashService

    init(trashService: TrashService) {
        self.trashService = trashService
    }

    func loadEntries() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            entries = try await trashService.listTrashedDocuments()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func restoreSelection() async {
        let ids = selection
        guard !ids.isEmpty else { return }

        do {
            for id in ids {
                try await trashService.restoreDocument(deletionLogId: id, toFolderId: nil)
            }
            selection = []
            await loadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(_ id: Int64) async {
        selection = [id]
        await restoreSelection()
    }

    func deleteSelectionPermanently() async {
        let ids = selection
        guard !ids.isEmpty else { return }

        do {
            for id in ids {
                try await trashService.permanentlyDelete(deletionLogId: id)
            }
            selection = []
            await loadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePermanently(_ id: Int64) async {
        selection = [id]
        await deleteSelectionPermanently()
    }

    func emptyTrash() async {
        do {
            try await trashService.emptyTrash()
            selection = []
            await loadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
