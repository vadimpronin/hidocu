//
//  RecordingsListViewModel.swift
//  HiDocu
//
//  ViewModel for the recordings list: reactive observation, date grouping, filtering.
//

import Foundation

/// A group of recordings sharing the same calendar date.
struct RecordingDateGroup: Identifiable {
    let date: Date
    let recordings: [Recording]

    var id: Date { date }

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var headerTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return Self.mediumDateFormatter.string(from: date)
        }
    }
}

/// Observes the recording repository and presents grouped, filtered results.
@Observable
@MainActor
final class RecordingsListViewModel {

    // MARK: - State

    private(set) var groups: [RecordingDateGroup] = []
    private(set) var totalCount: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    // MARK: - Filter / Sort

    var statusFilter: RecordingStatus?
    var sortField: RecordingSortField = .createdAt
    var sortAscending: Bool = false

    // MARK: - Dependencies

    private let repository: any RecordingRepository
    private var observationTask: Task<Void, Never>?

    // MARK: - Init

    init(repository: any RecordingRepository) {
        self.repository = repository
    }

    /// Cancel the active observation. Call when the view disappears or this VM is no longer needed.
    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Public

    /// Start observing recordings. Call from the view's `.task {}` modifier.
    func startObserving() {
        guard observationTask == nil else { return }
        restartObservation()
    }

    /// Change the status filter and restart observation.
    func setFilter(_ status: RecordingStatus?) {
        statusFilter = status
        restartObservation()
    }

    // MARK: - Private

    private func restartObservation() {
        observationTask?.cancel()
        isLoading = true
        errorMessage = nil

        let filter = statusFilter
        let sort = sortField
        let ascending = sortAscending

        observationTask = Task { [weak self] in
            guard let self else { return }

            let stream = repository.observeAll(
                filterStatus: filter,
                sortBy: sort,
                ascending: ascending
            )

            do {
                for try await recordings in stream {
                    guard !Task.isCancelled else { break }
                    processRecordings(recordings)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// Group recordings by calendar date (single O(n) pass), then sort groups descending.
    private func processRecordings(_ recordings: [Recording]) {
        let calendar = Calendar.current
        var buckets: [Date: [Recording]] = [:]

        for recording in recordings {
            let day = calendar.startOfDay(for: recording.createdAt ?? Date.distantPast)
            buckets[day, default: []].append(recording)
        }

        groups = buckets
            .map { RecordingDateGroup(date: $0.key, recordings: $0.value) }
            .sorted { $0.date > $1.date }

        totalCount = recordings.count
        isLoading = false
    }
}
