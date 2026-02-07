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
    private var observationTask: Task<Void, Never>?

    init(documentRepository: any DocumentRepository) {
        self.documentRepository = documentRepository
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
}
