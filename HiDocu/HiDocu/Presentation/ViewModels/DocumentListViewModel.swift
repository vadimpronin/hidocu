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

    private let documentRepository: any DocumentRepository
    private let documentService: DocumentService
    private var observationTask: Task<Void, Never>?

    init(documentRepository: any DocumentRepository, documentService: DocumentService) {
        self.documentRepository = documentRepository
        self.documentService = documentService
    }

    func observeDocuments(folderId: Int64?) {
        observationTask?.cancel()
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
        var reordered = documents
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
        Task {
            do {
                try await documentService.sortDocuments(folderId: folderId, by: criterion)
            } catch {
                AppLogger.general.error("Failed to sort documents: \(error.localizedDescription)")
            }
        }
    }
}
