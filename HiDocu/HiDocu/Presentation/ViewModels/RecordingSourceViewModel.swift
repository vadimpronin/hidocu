//
//  RecordingSourceViewModel.swift
//  HiDocu
//
//  ViewModel for recording source detail view. Manages a single source's unified
//  recording list by merging device files (when online) with local recordings.
//

import Foundation

/// Unified row that merges device files with local recordings.
struct UnifiedRecordingRow: Identifiable {
    let id: String  // filename serves as ID
    let filename: String
    let createdAt: Date?
    let durationSeconds: Int
    let size: Int
    let mode: RecordingMode?
    var syncStatus: RecordingSyncStatus
    var recordingId: Int64?
    var documentId: Int64?

    // Sortable proxy properties
    var sortableDate: Double { createdAt?.timeIntervalSince1970 ?? 0 }
    var modeDisplayName: String { mode?.displayName ?? "—" }
}

@Observable
@MainActor
final class RecordingSourceViewModel {

    // MARK: - State

    private(set) var rows: [UnifiedRecordingRow] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    var selection: Set<String> = []
    var sortOrder: [KeyPathComparator<UnifiedRecordingRow>] = [
        .init(\.sortableDate, order: .reverse)
    ]

    var sortedRows: [UnifiedRecordingRow] {
        rows.sorted(using: sortOrder)
    }

    // MARK: - Dependencies

    private let recordingRepository: any RecordingRepositoryV2
    private let sourceRepository: any SourceRepository

    // Store device files for later access (needed for import operations)
    private var deviceFilesByFilename: [String: DeviceFileInfo] = [:]

    // MARK: - Initialization

    init(recordingRepository: any RecordingRepositoryV2, sourceRepository: any SourceRepository) {
        self.recordingRepository = recordingRepository
        self.sourceRepository = sourceRepository
    }

    // MARK: - Actions

    /// Load recordings for a source, optionally merging with device files when online.
    func loadRecordings(sourceId: Int64, deviceController: DeviceController?) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch local recordings for this source
            let localRecordings = try await recordingRepository.fetchBySourceId(sourceId)
            let localByFilename = Dictionary(
                localRecordings.map { ($0.filename, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            if let controller = deviceController, controller.isConnected {
                // Online: merge device files with local recordings
                let deviceFiles = try await controller.listFiles()

                // Store device files for later access (import operations)
                deviceFilesByFilename = Dictionary(
                    deviceFiles.map { ($0.filename, $0) },
                    uniquingKeysWith: { first, _ in first }
                )

                var unified: [UnifiedRecordingRow] = []
                var seenFilenames: Set<String> = []

                // Process device files
                for file in deviceFiles {
                    seenFilenames.insert(file.filename)
                    let localRec = localByFilename[file.filename]
                    let status: RecordingSyncStatus = localRec != nil ? .synced : .onDeviceOnly
                    unified.append(UnifiedRecordingRow(
                        id: file.filename,
                        filename: file.filename,
                        createdAt: file.createdAt,
                        durationSeconds: file.durationSeconds,
                        size: file.size,
                        mode: file.mode,
                        syncStatus: status,
                        recordingId: localRec?.id,
                        documentId: nil
                    ))
                }

                // Add local-only recordings (not on device anymore)
                for rec in localRecordings where !seenFilenames.contains(rec.filename) {
                    unified.append(UnifiedRecordingRow(
                        id: rec.filename,
                        filename: rec.filename,
                        createdAt: rec.createdAt,
                        durationSeconds: rec.durationSeconds ?? 0,
                        size: rec.fileSizeBytes ?? 0,
                        mode: rec.recordingMode,
                        syncStatus: .localOnly,
                        recordingId: rec.id,
                        documentId: nil
                    ))
                }

                rows = unified
            } else {
                // Offline: show local recordings only
                deviceFilesByFilename = [:]
                rows = localRecordings.map { rec in
                    UnifiedRecordingRow(
                        id: rec.filename,
                        filename: rec.filename,
                        createdAt: rec.createdAt,
                        durationSeconds: rec.durationSeconds ?? 0,
                        size: rec.fileSizeBytes ?? 0,
                        mode: rec.recordingMode,
                        syncStatus: .localOnly,
                        recordingId: rec.id,
                        documentId: nil
                    )
                }
            }

            // Populate document IDs from the sources table
            await populateDocumentIds()
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.recordings.error("Failed to load recordings: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Re-check import status and document links without re-fetching device file list.
    /// Called after import finishes to update checkmarks and document links.
    func refreshImportStatus(sourceId: Int64) async {
        guard !rows.isEmpty else { return }

        let importedFilenames = (try? await recordingRepository.fetchFilenamesForSource(sourceId)) ?? []

        // Re-fetch local recordings to get recording IDs for newly imported files
        let localRecordings = (try? await recordingRepository.fetchBySourceId(sourceId)) ?? []
        let localByFilename = Dictionary(
            localRecordings.map { ($0.filename, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for i in rows.indices {
            let onDevice = deviceFilesByFilename[rows[i].filename] != nil
            let isImported = importedFilenames.contains(rows[i].filename)

            if onDevice && isImported {
                rows[i].syncStatus = .synced
            } else if onDevice {
                rows[i].syncStatus = .onDeviceOnly
            } else {
                rows[i].syncStatus = .localOnly
            }

            // Update recording ID if it was nil (newly imported)
            if rows[i].recordingId == nil, let localRec = localByFilename[rows[i].filename] {
                rows[i].recordingId = localRec.id
            }
        }

        // Refresh document IDs (import creates new documents)
        await populateDocumentIds()
    }

    /// Return DeviceFileInfo objects for selected filenames (for import).
    func deviceFiles(for filenames: Set<String>) -> [DeviceFileInfo] {
        filenames.compactMap { deviceFilesByFilename[$0] }
    }

    // MARK: - Private

    /// Batch-fetch document IDs for all rows that have recording IDs.
    private func populateDocumentIds() async {
        let recordingIds = rows.compactMap(\.recordingId)
        guard !recordingIds.isEmpty else { return }

        let docIdMap = (try? await sourceRepository.fetchDocumentIdsByRecordingIds(recordingIds)) ?? [:]
        guard !docIdMap.isEmpty else { return }

        for i in rows.indices {
            if let recId = rows[i].recordingId, let docId = docIdMap[recId] {
                rows[i].documentId = docId
            }
        }
    }
}
