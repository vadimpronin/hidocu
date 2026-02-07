//
//  DeviceDashboardViewModel.swift
//  HiDocu
//
//  ViewModel for the device dashboard view. Manages file listing,
//  import status checking, and sorting for the device file browser.
//

import Foundation

/// Represents a device file with its local import status.
struct DeviceFileRow: Identifiable {
    let fileInfo: DeviceFileInfo
    let isImported: Bool

    var id: String { fileInfo.filename }
    var filename: String { fileInfo.filename }
    var size: Int { fileInfo.size }
    var durationSeconds: Int { fileInfo.durationSeconds }
    var createdAt: Date? { fileInfo.createdAt }
    var mode: RecordingMode? { fileInfo.mode }

    // Sortable proxy properties
    var sortableDate: Double { createdAt?.timeIntervalSince1970 ?? 0 }
    var modeDisplayName: String { mode?.displayName ?? "—" }
}

@Observable
@MainActor
final class DeviceDashboardViewModel {

    // MARK: - State

    private(set) var files: [DeviceFileRow] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    var selection: Set<String> = []

    var sortOrder: [KeyPathComparator<DeviceFileRow>] = [
        .init(\.sortableDate, order: .reverse)
    ]

    var sortedFiles: [DeviceFileRow] {
        files.sorted(using: sortOrder)
    }

    // MARK: - Dependencies

    private let deviceController: DeviceController
    private let repository: any RecordingRepositoryV2

    // MARK: - Initialization

    init(
        deviceController: DeviceController,
        repository: any RecordingRepositoryV2
    ) {
        self.deviceController = deviceController
        self.repository = repository
    }

    // MARK: - Actions

    func loadFiles() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let deviceFiles = try await deviceController.listFiles()
            var rows: [DeviceFileRow] = []

            for file in deviceFiles {
                let imported = try await repository.exists(
                    filename: file.filename,
                    sizeBytes: file.size
                )
                rows.append(DeviceFileRow(fileInfo: file, isImported: imported))
            }

            files = rows
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.ui.error("Failed to load device files: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Re-check import status for all cached files without re-fetching from device.
    /// Called after import finishes to update checkmarks.
    func refreshImportStatus() async {
        guard !files.isEmpty else { return }

        var updatedRows: [DeviceFileRow] = []
        for row in files {
            let imported = (try? await repository.exists(
                filename: row.fileInfo.filename,
                sizeBytes: row.fileInfo.size
            )) ?? row.isImported
            updatedRows.append(DeviceFileRow(fileInfo: row.fileInfo, isImported: imported))
        }
        files = updatedRows
    }

    func deleteFiles(_ filenames: Set<String>) async {
        for filename in filenames {
            do {
                try await deviceController.deleteFile(filename: filename)
            } catch {
                AppLogger.ui.error("Failed to delete \(filename): \(error.localizedDescription)")
            }
        }

        selection.removeAll()
        await loadFiles()
        await deviceController.refreshStorageInfo()
    }

    /// Returns the DeviceFileInfo objects for the given set of filenames.
    func deviceFiles(for filenames: Set<String>) -> [DeviceFileInfo] {
        files.filter { filenames.contains($0.filename) }.map(\.fileInfo)
    }
}
