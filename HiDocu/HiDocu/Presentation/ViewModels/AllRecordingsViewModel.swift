//
//  AllRecordingsViewModel.swift
//  HiDocu
//
//  ViewModel for the All Recordings view. Aggregates recordings from all sources
//  with document info and processing status.
//

import Foundation

struct AllRecordingsRow: Identifiable {
    let id: Int64  // recording ID
    let filename: String
    let filepath: String
    let title: String?
    let createdAt: Date?
    let durationSeconds: Int?
    let fileSizeBytes: Int?
    let recordingMode: RecordingMode?
    let syncStatus: RecordingSyncStatus?
    let recordingSourceId: Int64?
    // Source info
    var sourceName: String?
    var sourceDeviceModel: String?
    // Document info
    var documentInfo: [DocumentLink] = []
    var isProcessing: Bool = false

    /// User-friendly title: explicit title if set, otherwise filename.
    var displayTitle: String { title ?? filename }

    /// Sort proxy for optional dates.
    var sortableDate: Double { createdAt?.timeIntervalSince1970 ?? 0 }

    /// Backward-compatible computed property.
    var documentId: Int64? { documentInfo.first?.id }
}

@Observable
@MainActor
final class AllRecordingsViewModel {

    // MARK: - State

    private(set) var rows: [AllRecordingsRow] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    var selection: Set<Int64> = []
    var sortOrder: [KeyPathComparator<AllRecordingsRow>] = [
        .init(\.sortableDate, order: .reverse)
    ]

    var sortedRows: [AllRecordingsRow] {
        rows.sorted(using: sortOrder)
    }

    // MARK: - Dependencies

    private let recordingRepository: any RecordingRepositoryV2
    private let recordingSourceRepository: any RecordingSourceRepository
    private let sourceRepository: any SourceRepository
    private let recordingSourceService: RecordingSourceService
    private let llmQueueState: LLMQueueState

    // MARK: - Initialization

    init(
        recordingRepository: any RecordingRepositoryV2,
        recordingSourceRepository: any RecordingSourceRepository,
        sourceRepository: any SourceRepository,
        recordingSourceService: RecordingSourceService,
        llmQueueState: LLMQueueState
    ) {
        self.recordingRepository = recordingRepository
        self.recordingSourceRepository = recordingSourceRepository
        self.sourceRepository = sourceRepository
        self.recordingSourceService = recordingSourceService
        self.llmQueueState = llmQueueState
    }

    // MARK: - Actions

    func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let recordingsTask = recordingRepository.fetchAll()
            async let sourcesTask = recordingSourceRepository.fetchAll()

            let (recordings, sources) = try await (recordingsTask, sourcesTask)
            let sourceMap = Dictionary(
                sources.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var newRows = recordings.map { rec in
                let source = rec.recordingSourceId.flatMap { sourceMap[$0] }
                return AllRecordingsRow(
                    id: rec.id,
                    filename: rec.filename,
                    filepath: rec.filepath,
                    title: rec.title,
                    createdAt: rec.createdAt,
                    durationSeconds: rec.durationSeconds,
                    fileSizeBytes: rec.fileSizeBytes,
                    recordingMode: rec.recordingMode,
                    syncStatus: rec.syncStatus,
                    recordingSourceId: rec.recordingSourceId,
                    sourceName: source?.name,
                    sourceDeviceModel: source?.deviceModel
                )
            }

            // Populate document info
            let recordingIds = recordings.map(\.id)
            let docInfoMap: [Int64: [DocumentLink]]
            do {
                docInfoMap = try await sourceRepository.fetchDocumentInfoByRecordingIds(recordingIds)
            } catch {
                AppLogger.recordings.error("Failed to fetch document info: \(error.localizedDescription)")
                docInfoMap = [:]
            }
            for i in newRows.indices {
                if let info = docInfoMap[newRows[i].id] {
                    newRows[i].documentInfo = info
                }
            }

            // Processing status
            let activeDocIds = Set(llmQueueState.activeJobs.compactMap(\.documentId))
            let pendingDocIds = Set(llmQueueState.pendingJobs.compactMap(\.documentId))
            let processingDocIds = activeDocIds.union(pendingDocIds)
            if !processingDocIds.isEmpty {
                for i in newRows.indices {
                    let docIds = Set(newRows[i].documentInfo.map(\.id))
                    newRows[i].isProcessing = !docIds.isDisjoint(with: processingDocIds)
                }
            }

            rows = newRows
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.recordings.error("Failed to load all recordings: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Delete local copies for selected recording IDs.
    func deleteLocalCopies(ids: Set<Int64>) async {
        for id in ids {
            do {
                try await recordingSourceService.deleteLocalCopy(recordingId: id)
            } catch {
                AppLogger.recordings.error("Failed to delete local copy for recording \(id): \(error.localizedDescription)")
            }
        }
        await loadData()
    }
}
