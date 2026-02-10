//
//  DocumentListViewModel.swift
//  HiDocu
//
//  ViewModel for document list - observes documents for a folder or all documents.
//

import Foundation

@Observable
@MainActor
final class DocumentListViewModel {

    var documents: [Document] = []
    var isLoading = false
    var sortOrder: [KeyPathComparator<Document>] = [
        .init(\.sortOrder)
    ]
    var allowsManualReordering = true

    var sortedDocuments: [Document] {
        documents.sorted(using: sortOrder)
    }

    private let documentRepository: any DocumentRepository
    private let documentService: DocumentService
    private var observationTask: Task<Void, Never>?

    init(documentRepository: any DocumentRepository, documentService: DocumentService) {
        self.documentRepository = documentRepository
        self.documentService = documentService
    }

    func observeDocuments(folderId: Int64?) {
        observationTask?.cancel()
        allowsManualReordering = true
        sortOrder = [.init(\.sortOrder)]
        observationTask = Task {
            isLoading = true
            do {
                for try await docs in documentRepository.observeAll(folderId: folderId) {
                    self.documents = docs
                    self.isLoading = false
                }
            } catch {
                self.isLoading = false
            }
        }
    }

    func observeAllDocuments() {
        observationTask?.cancel()
        allowsManualReordering = false
        sortOrder = [.init(\.createdAt, order: .reverse)]
        observationTask = Task {
            isLoading = true
            do {
                for try await docs in documentRepository.observeAllDocuments() {
                    self.documents = docs
                    self.isLoading = false
                }
            } catch {
                self.isLoading = false
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Sorting

    func moveDocuments(from source: IndexSet, to destination: Int) {
        guard allowsManualReordering else { return }
        var reordered = sortedDocuments
        reordered.move(fromOffsets: source, toOffset: destination)
        documents = reordered  // Optimistic update
        let orderedIds = reordered.map(\.id)
        Task {
            do {
                try await documentService.reorderDocuments(orderedIds)
            } catch {
                // Next observation emission will restore DB state
                AppLogger.general.error("Failed to reorder documents: \(error.localizedDescription)")
            }
        }
    }

    func sortDocuments(folderId: Int64?, by criterion: DocumentSortCriterion) {
        _ = folderId
        switch criterion {
        case .nameAscending:
            allowsManualReordering = false
            sortOrder = [.init(\.title)]
        case .dateCreatedAscending:
            allowsManualReordering = false
            sortOrder = [.init(\.createdAt)]
        case .dateCreatedDescending:
            allowsManualReordering = false
            sortOrder = [.init(\.createdAt, order: .reverse)]
        }
    }

    func useManualOrder() {
        allowsManualReordering = true
        sortOrder = [.init(\.sortOrder)]
    }
}
